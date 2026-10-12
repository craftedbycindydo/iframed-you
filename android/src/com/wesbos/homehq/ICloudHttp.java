package com.wesbos.homehq;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import javax.net.ssl.HttpsURLConnection;

final class ICloudHttp implements ICloudAlbum.Transport {
  static final int MAX_ANSWER = 2 * 1024 * 1024;
  private static final int CONNECT_MILLIS = 15000;
  private static final int READ_MILLIS = 20000;
  private static final long LONGEST_TRANSFER_NANOS = 120000000000L;

  static URL allowed(String address, boolean api) throws IOException {
    URL url = new URL(address);
    String host = url.getHost();
    boolean trusted = "https".equals(url.getProtocol()) && url.getUserInfo() == null && url.getPort() == -1
        && (api ? ICloudAlbum.streamHost(host) : host.endsWith(".icloud-content.com") || host.endsWith(".icloud.com"));
    if (!trusted) throw new IOException("Refused an address outside iCloud");
    return url;
  }

  private static HttpsURLConnection open(URL url) throws IOException {
    HttpsURLConnection connection = (HttpsURLConnection) url.openConnection();
    connection.setInstanceFollowRedirects(false);
    connection.setConnectTimeout(CONNECT_MILLIS);
    connection.setReadTimeout(READ_MILLIS);
    connection.setUseCaches(false);
    connection.setRequestProperty("User-Agent", "Skylit");
    return connection;
  }

  private static byte[] bounded(InputStream in, int limit) throws IOException {
    if (in == null) return new byte[0];
    long deadline = System.nanoTime() + LONGEST_TRANSFER_NANOS;
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    byte[] buffer = new byte[32768];
    for (int count; (count = in.read(buffer)) >= 0;) {
      if (out.size() + count > limit || System.nanoTime() > deadline) throw new IOException("iCloud answer exceeded its limit");
      out.write(buffer, 0, count);
    }
    return out.toByteArray();
  }

  @Override public ICloudAlbum.Reply post(String address, String body) throws IOException {
    HttpsURLConnection connection = open(allowed(address, true));
    try {
      byte[] content = body.getBytes(StandardCharsets.UTF_8);
      connection.setRequestMethod("POST");
      connection.setDoOutput(true);
      connection.setFixedLengthStreamingMode(content.length);
      connection.setRequestProperty("Content-Type", "text/plain");
      try (OutputStream out = connection.getOutputStream()) {
        out.write(content);
      }
      int status = connection.getResponseCode();
      try (InputStream in = status >= 400 ? connection.getErrorStream() : connection.getInputStream()) {
        return new ICloudAlbum.Reply(status, new String(bounded(in, MAX_ANSWER), StandardCharsets.UTF_8));
      }
    } finally {
      connection.disconnect();
    }
  }

  @Override public byte[] get(String address, int limit) throws IOException {
    HttpsURLConnection connection = open(allowed(address, false));
    try {
      if (connection.getResponseCode() != 200) throw new IOException("Picture unavailable");
      if (connection.getContentLength() > limit) throw new IOException("Picture exceeds the size limit");
      try (InputStream in = connection.getInputStream()) {
        return bounded(in, limit);
      }
    } finally {
      connection.disconnect();
    }
  }
}
