package com.wesbos.homehq;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.BindException;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.security.GeneralSecurityException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.SSLServerSocket;
import javax.net.ssl.SSLServerSocketFactory;
import javax.net.ssl.SSLSocket;

final class LocalServer {
  static final int PREFERRED_PORT = 8765;
  static final int WORKERS = 4;
  static final int SERVED_PER_SOURCE = 3;
  static final int WAITING_PER_SOURCE = 12;
  static final int WAITING_EVERYONE = 32;
  static final int WAIT_SECONDS = 15;
  static final int HEAD_SECONDS = 5;
  static final int EXCHANGE_SECONDS = 20;
  static final int UPLOAD_HANDLING_SECONDS = 60;
  static final String PROTOCOL = "TLSv1.2";
  static final String[] SUITES = {"TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"};
  private static final long DRAIN_NANOS = 1500000000L;
  private static final int DRAIN_BYTES = 256 * 1024;

  private static final class Connection {
    final Socket socket;
    final InetAddress source;
    ScheduledFuture<?> limit;

    Connection(Socket socket) {
      this.socket = socket;
      this.source = socket.getInetAddress();
    }
  }

  private final LocalApi api;
  private final List<Connection> waiting = new ArrayList<>();
  private final List<Connection> served = new ArrayList<>();
  private final ThreadFactory threads = new ThreadFactory() {
    @Override public Thread newThread(Runnable work) {
      Thread thread = new Thread(work, "skylit-local-api");
      thread.setDaemon(true);
      return thread;
    }
  };
  private ThreadPoolExecutor workers;
  private ScheduledThreadPoolExecutor watchdog;
  private volatile ServerSocket listener;

  LocalServer(LocalApi api) {
    this.api = api;
  }

  synchronized int start(InetAddress address, int preferredPort) throws IOException {
    if (listener != null) return listener.getLocalPort();
    SSLServerSocketFactory factory;
    try {
      factory = api.identity().tls().getServerSocketFactory();
    } catch (GeneralSecurityException unusable) {
      throw new IOException("The frame's TLS identity could not be used", unusable);
    }
    ServerSocket socket = secure(factory);
    socket.setReuseAddress(true);
    try {
      socket.bind(new InetSocketAddress(address, preferredPort), 16);
    } catch (BindException taken) {
      socket.close();
      socket = secure(factory);
      socket.bind(new InetSocketAddress(address, 0), 16);
    }
    workers = new ThreadPoolExecutor(WORKERS, WORKERS, 30, TimeUnit.SECONDS, new LinkedBlockingQueue<Runnable>(), threads);
    workers.allowCoreThreadTimeOut(true);
    watchdog = new ScheduledThreadPoolExecutor(1, threads);
    watchdog.setRemoveOnCancelPolicy(true);
    listener = socket;
    final ServerSocket accepting = socket;
    threads.newThread(new Runnable() {
      @Override public void run() {
        accept(accepting);
      }
    }).start();
    return socket.getLocalPort();
  }

  int port() {
    ServerSocket current = listener;
    return current == null ? 0 : current.getLocalPort();
  }

  synchronized void stop() {
    ServerSocket current = listener;
    if (current == null) return;
    listener = null;
    close(current);
    workers.shutdownNow();
    watchdog.shutdownNow();
    for (Connection connection : waiting) close(connection.socket);
    for (Connection connection : served) close(connection.socket);
    waiting.clear();
  }

  private static ServerSocket secure(SSLServerSocketFactory factory) throws IOException {
    SSLServerSocket socket = (SSLServerSocket) factory.createServerSocket();
    List<String> suites = new ArrayList<>(Arrays.asList(SUITES));
    suites.retainAll(Arrays.asList(socket.getSupportedCipherSuites()));
    if (suites.isEmpty() || !Arrays.asList(socket.getSupportedProtocols()).contains(PROTOCOL)) {
      socket.close();
      throw new IOException("Phone API disabled: this device offers neither " + SUITES[0] + " nor " + SUITES[1] + " over " + PROTOCOL);
    }
    socket.setEnabledProtocols(new String[] {PROTOCOL});
    socket.setEnabledCipherSuites(suites.toArray(new String[0]));
    return socket;
  }

  static String lanAddress() {
    try {
      for (NetworkInterface link : Collections.list(NetworkInterface.getNetworkInterfaces())) {
        if (!link.isUp() || link.isLoopback()) continue;
        for (InetAddress address : Collections.list(link.getInetAddresses())) {
          if (address instanceof Inet4Address && address.isSiteLocalAddress()) return address.getHostAddress();
        }
      }
      return "";
    } catch (IOException | RuntimeException unknown) {
      return "";
    }
  }

  static boolean local(InetAddress peer) {
    byte[] raw = peer.getAddress();
    boolean uniqueLocal = raw.length == 16 && (raw[0] & 0xFE) == 0xFC;
    return peer.isLoopbackAddress() || peer.isSiteLocalAddress() || peer.isLinkLocalAddress() || uniqueLocal;
  }

  private void accept(ServerSocket accepting) {
    while (listener == accepting) {
      try {
        Socket socket = accepting.accept();
        if (!local(socket.getInetAddress())) close(socket);
        else admit(new Connection(socket));
      } catch (IOException | RuntimeException closedOrFailed) {
        if (listener != accepting) return;
      }
    }
  }

  private static int from(List<Connection> connections, InetAddress source) {
    int count = 0;
    for (Connection connection : connections) if (connection.source.equals(source)) count++;
    return count;
  }

  private synchronized void admit(Connection connection) {
    if (listener == null || waiting.size() >= WAITING_EVERYONE || from(waiting, connection.source) >= WAITING_PER_SOURCE) {
      close(connection.socket);
      return;
    }
    connection.limit = closeAfter(connection.socket, WAIT_SECONDS);
    waiting.add(connection);
    dispatch();
  }

  private synchronized void dispatch() {
    for (Iterator<Connection> queue = waiting.iterator(); queue.hasNext();) if (queue.next().socket.isClosed()) queue.remove();
    for (Iterator<Connection> queue = waiting.iterator(); queue.hasNext() && served.size() < WORKERS;) {
      final Connection next = queue.next();
      if (from(served, next.source) >= SERVED_PER_SOURCE) continue;
      queue.remove();
      served.add(next);
      try {
        workers.execute(new Runnable() {
          @Override public void run() {
            try {
              serve(next);
            } finally {
              finished(next);
            }
          }
        });
      } catch (RejectedExecutionException stopping) {
        served.remove(next);
        close(next.socket);
      }
    }
  }

  private synchronized void finished(Connection connection) {
    served.remove(connection);
    if (listener != null) dispatch();
  }

  private ScheduledFuture<?> closeAfter(final Socket socket, int seconds) {
    return watchdog.schedule(new Runnable() {
      @Override public void run() {
        try {
          socket.setSoLinger(true, 0);
        } catch (IOException alreadyClosed) {
          return;
        }
        close(socket);
      }
    }, seconds, TimeUnit.SECONDS);
  }

  private static int exchangeSeconds(LocalHttp.Request request) {
    String declared = request.headers.get("content-length");
    boolean upload = request.method.equals("POST") && request.path.equals("/v1/photos") && declared != null && declared.matches("[0-9]{1,9}");
    if (!upload) return EXCHANGE_SECONDS;
    long bytes = Math.min(LocalApi.MAX_PHOTO, Long.parseLong(declared));
    return EXCHANGE_SECONDS + UPLOAD_HANDLING_SECONDS + (int) (bytes / LocalHttp.BODY_BYTES_PER_SECOND);
  }

  private void serve(Connection connection) {
    final Socket socket = connection.socket;
    try {
      connection.limit.cancel(false);
      connection.limit = closeAfter(socket, HEAD_SECONDS);
      socket.setSoTimeout(HEAD_SECONDS * 1000);
      ((SSLSocket) socket).startHandshake();
      InputStream in = new BufferedInputStream(socket.getInputStream(), 16384);
      OutputStream out = new BufferedOutputStream(socket.getOutputStream(), 16384);
      LocalHttp.Response response;
      try {
        LocalHttp.Request request = LocalHttp.readHead(in);
        connection.limit.cancel(false);
        connection.limit = closeAfter(socket, exchangeSeconds(request));
        response = api.handle(request, LocalHttp.body(request, in, out, new LocalHttp.Pace() {
          @Override public void readWithin(int millis) throws IOException {
            socket.setSoTimeout(Math.max(1, millis));
          }
        }));
      } catch (ApiException malformed) {
        response = LocalHttp.Response.error(malformed);
      }
      LocalHttp.write(out, response);
      try {
        socket.shutdownOutput();
      } catch (UnsupportedOperationException noHalfClose) {
        out.flush();
      }
      socket.setSoTimeout(500);
      long until = System.nanoTime() + DRAIN_NANOS;
      byte[] unread = new byte[8192];
      for (int drained = 0, count; drained < DRAIN_BYTES && System.nanoTime() < until && (count = in.read(unread)) >= 0;) drained += count;
    } catch (IOException | RuntimeException droppedConnection) {
      close(socket);
    } finally {
      connection.limit.cancel(false);
      close(socket);
    }
  }

  private static void close(java.io.Closeable resource) {
    try {
      resource.close();
    } catch (IOException alreadyClosed) {
      return;
    }
  }
}
