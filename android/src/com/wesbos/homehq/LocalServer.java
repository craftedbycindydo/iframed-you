package com.wesbos.homehq;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.BindException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Collections;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

final class LocalServer {
  static final int PREFERRED_PORT = 8765;
  private static final int WORKERS = 4;
  private static final int WAITING_CONNECTIONS = 8;
  private static final int READ_TIMEOUT_MILLIS = 10000;
  private static final int HEAD_SECONDS = 15;
  private static final int EXCHANGE_SECONDS = 150;
  private static final int DRAIN_BYTES = 256 * 1024;

  private final LocalApi api;
  private final Set<Socket> open = Collections.newSetFromMap(new ConcurrentHashMap<Socket, Boolean>());
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
    ServerSocket socket = new ServerSocket();
    socket.setReuseAddress(true);
    try {
      socket.bind(new InetSocketAddress(address, preferredPort), 16);
    } catch (BindException taken) {
      socket.close();
      socket = new ServerSocket();
      socket.bind(new InetSocketAddress(address, 0), 16);
    }
    workers = new ThreadPoolExecutor(WORKERS, WORKERS, 30, TimeUnit.SECONDS,
        new ArrayBlockingQueue<Runnable>(WAITING_CONNECTIONS), threads);
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
    for (Socket socket : open) close(socket);
  }

  static boolean local(InetAddress peer) {
    byte[] raw = peer.getAddress();
    boolean uniqueLocal = raw.length == 16 && (raw[0] & 0xFE) == 0xFC;
    return peer.isLoopbackAddress() || peer.isSiteLocalAddress() || peer.isLinkLocalAddress() || uniqueLocal;
  }

  private void accept(ServerSocket accepting) {
    while (listener == accepting) {
      try {
        final Socket socket = accepting.accept();
        if (!local(socket.getInetAddress())) {
          close(socket);
          continue;
        }
        open.add(socket);
        try {
          workers.execute(new Runnable() {
            @Override public void run() {
              serve(socket);
            }
          });
        } catch (RejectedExecutionException busy) {
          open.remove(socket);
          close(socket);
        }
      } catch (IOException closedOrFailed) {
        if (listener != accepting) return;
      }
    }
  }

  private ScheduledFuture<?> closeAfter(final Socket socket, int seconds) {
    return watchdog.schedule(new Runnable() {
      @Override public void run() {
        close(socket);
      }
    }, seconds, TimeUnit.SECONDS);
  }

  private void serve(Socket socket) {
    ScheduledFuture<?> limit = null;
    try {
      limit = closeAfter(socket, HEAD_SECONDS);
      socket.setSoTimeout(READ_TIMEOUT_MILLIS);
      InputStream in = new BufferedInputStream(socket.getInputStream(), 16384);
      OutputStream out = new BufferedOutputStream(socket.getOutputStream(), 16384);
      LocalHttp.Response response;
      try {
        LocalHttp.Request request = LocalHttp.readHead(in);
        limit.cancel(false);
        limit = closeAfter(socket, EXCHANGE_SECONDS);
        response = api.handle(request, LocalHttp.body(request, in, out));
      } catch (ApiException malformed) {
        response = LocalHttp.Response.error(malformed);
      }
      LocalHttp.write(out, response);
      socket.shutdownOutput();
      socket.setSoTimeout(1000);
      byte[] unread = new byte[8192];
      for (int drained = 0, count; drained < DRAIN_BYTES && (count = in.read(unread)) >= 0;) drained += count;
    } catch (IOException | RuntimeException droppedConnection) {
      close(socket);
    } finally {
      if (limit != null) limit.cancel(false);
      close(socket);
      open.remove(socket);
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
