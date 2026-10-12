package com.wesbos.homehq;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

final class TccHttp implements TccClient.Transport {
  static final int MAX_ANSWER = 1024 * 1024;
  private static final int CONNECT_MILLIS = 15000;
  private static final int READ_MILLIS = 20000;
  private static final long LONGEST_TRANSFER_NANOS = 60000000000L;

  private final String origin;

  TccHttp() {
    this(TccClient.ORIGIN);
  }

  TccHttp(String origin) {
    this.origin = origin;
  }

  URL allowed(String path) throws IOException {
    if (path == null || !path.startsWith("/")) throw new IOException("Refused an address outside Total Connect Comfort");
    URL base = new URL(origin);
    URL url = new URL(origin + path);
    boolean trusted = url.getProtocol().equals(base.getProtocol()) && url.getHost().equals(base.getHost()) && url.getPort() == base.getPort()
        && url.getUserInfo() == null;
    if (!trusted) throw new IOException("Refused an address outside Total Connect Comfort");
    return url;
  }

  private static byte[] bounded(InputStream in) throws IOException {
    if (in == null) return new byte[0];
    long deadline = System.nanoTime() + LONGEST_TRANSFER_NANOS;
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    byte[] buffer = new byte[16384];
    for (int count; (count = in.read(buffer)) >= 0;) {
      if (out.size() + count > MAX_ANSWER || System.nanoTime() > deadline) throw new IOException("Total Connect Comfort answer exceeded its limit");
      out.write(buffer, 0, count);
    }
    return out.toByteArray();
  }

  @Override public TccClient.Reply send(String method, String path, Map<String, String> headers, String body) throws IOException {
    HttpURLConnection connection = (HttpURLConnection) allowed(path).openConnection();
    try {
      connection.setInstanceFollowRedirects(false);
      connection.setConnectTimeout(CONNECT_MILLIS);
      connection.setReadTimeout(READ_MILLIS);
      connection.setUseCaches(false);
      connection.setRequestMethod(method);
      for (Map.Entry<String, String> header : headers.entrySet()) connection.setRequestProperty(header.getKey(), header.getValue());
      if ("POST".equals(method)) {
        byte[] content = (body == null ? "" : body).getBytes(StandardCharsets.UTF_8);
        connection.setDoOutput(true);
        connection.setFixedLengthStreamingMode(content.length);
        try (OutputStream out = connection.getOutputStream()) {
          out.write(content);
        }
      }
      int status = connection.getResponseCode();
      List<String> cookies = new ArrayList<>();
      for (Map.Entry<String, List<String>> header : connection.getHeaderFields().entrySet()) {
        if ("set-cookie".equalsIgnoreCase(header.getKey())) cookies.addAll(header.getValue());
      }
      String text;
      try (InputStream in = status >= 400 ? connection.getErrorStream() : connection.getInputStream()) {
        text = new String(bounded(in), StandardCharsets.UTF_8);
      }
      return new TccClient.Reply(status, connection.getContentType(), connection.getHeaderField("Location"), cookies, text);
    } finally {
      connection.disconnect();
    }
  }
}
