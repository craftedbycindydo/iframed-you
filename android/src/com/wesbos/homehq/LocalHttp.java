package com.wesbos.homehq;

import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

final class LocalHttp {
  static final int MAX_HEAD = 8192;
  static final int MAX_HEADERS = 64;

  static final int BODY_GRACE_MILLIS = 3000;
  static final int BODY_BYTES_PER_SECOND = 64 * 1024;
  private static final int LONGEST_READ_MILLIS = 5000;
  private static final String HOSTS = "([0-9]{1,3}(\\.[0-9]{1,3}){3}|\\[[0-9A-Fa-f:.]+(%25[A-Za-z0-9._\\-]+)?\\]|[A-Za-z0-9\\-]+(\\.[A-Za-z0-9\\-]+)*\\.local\\.?)(:[0-9]{1,5})?";

  interface Body {
    byte[] read(int limit) throws ApiException, IOException;
  }

  interface Pace {
    void readWithin(int millis) throws IOException;
  }

  static final class Request {
    final String method;
    final String path;
    final Map<String, String> query;
    final Map<String, String> headers;
    String peer = "";

    Request(String method, String path, Map<String, String> query, Map<String, String> headers) {
      this.method = method;
      this.path = path;
      this.query = query;
      this.headers = headers;
    }
  }

  static final class Response {
    final int status;
    final String contentType;
    final byte[] body;

    private Response(int status, String contentType, byte[] body) {
      this.status = status;
      this.contentType = contentType;
      this.body = body;
    }

    static Response json(int status, Object value) {
      return new Response(status, "application/json; charset=utf-8", Json.write(value).getBytes(StandardCharsets.UTF_8));
    }

    static Response empty(int status) {
      return new Response(status, null, new byte[0]);
    }

    static Response jpeg(byte[] image) {
      return new Response(200, "image/jpeg", image);
    }

    static Response error(int status, String code, String message) {
      return json(status, Json.object("error", Json.object("code", code, "message", message)));
    }

    static Response error(ApiException problem) {
      return error(problem.status, problem.code, problem.getMessage());
    }
  }

  private LocalHttp() {}

  static Request readHead(InputStream in) throws ApiException, IOException {
    ByteArrayOutputStream head = new ByteArrayOutputStream();
    int newlines = 0;
    while (newlines < 2) {
      int next = in.read();
      if (next < 0) throw new EOFException();
      if (head.size() >= MAX_HEAD) throw ApiException.badRequest("Request headers are too long");
      head.write(next);
      if (next == '\n') newlines++;
      else if (next != '\r') newlines = 0;
    }
    String[] lines = new String(head.toByteArray(), StandardCharsets.ISO_8859_1).split("\r?\n");
    if (lines.length == 0 || lines.length > MAX_HEADERS + 1) throw ApiException.badRequest("Malformed request");
    String[] start = lines[0].split(" ", -1);
    if (start.length != 3 || !start[0].matches("[A-Z]{3,7}") || !start[2].matches("HTTP/1\\.[01]")) {
      throw ApiException.badRequest("Malformed request line");
    }
    String target = start[1];
    if (target.length() > 2048 || !target.matches("/[A-Za-z0-9/_\\-]*(\\?[A-Za-z0-9_\\-=&]*)?") || target.contains("//")) {
      throw ApiException.badRequest("Unsupported request path");
    }
    int mark = target.indexOf('?');
    Map<String, String> query = new HashMap<>();
    if (mark >= 0) {
      for (String pair : target.substring(mark + 1).split("&")) {
        int equals = pair.indexOf('=');
        if (!pair.isEmpty()) query.put(equals < 0 ? pair : pair.substring(0, equals), equals < 0 ? "" : pair.substring(equals + 1));
      }
    }
    Map<String, String> headers = new HashMap<>();
    for (int i = 1; i < lines.length; i++) {
      int colon = lines[i].indexOf(':');
      if (colon <= 0 || !lines[i].substring(0, colon).matches("[A-Za-z0-9!#$%&'*+.^_`|~\\-]+")) {
        throw ApiException.badRequest("Malformed header");
      }
      String name = lines[i].substring(0, colon).toLowerCase(Locale.ROOT);
      if (headers.put(name, lines[i].substring(colon + 1).trim()) != null && name.equals("content-length")) {
        throw ApiException.badRequest("Repeated Content-Length");
      }
    }
    if (headers.containsKey("transfer-encoding")) throw ApiException.badRequest("Send a Content-Length body");
    if (headers.containsKey("origin")) throw ApiException.badRequest("Browser requests are not accepted");
    String host = headers.get("host");
    if (host == null || !host.matches(HOSTS)) throw ApiException.badRequest("Address the frame by its IP address or .local name");
    return new Request(start[0], mark < 0 ? target : target.substring(0, mark), query, headers);
  }

  static Body body(final Request request, final InputStream in, final OutputStream out, final Pace pace) {
    return new Body() {
      private boolean consumed;

      @Override public byte[] read(int limit) throws ApiException, IOException {
        if (consumed) throw new IllegalStateException("Body already read");
        consumed = true;
        String declared = request.headers.get("content-length");
        if (declared == null) return new byte[0];
        if (!declared.matches("[0-9]{1,18}")) throw ApiException.badRequest("Malformed Content-Length");
        long length = Long.parseLong(declared);
        if (length > limit) throw ApiException.tooLarge("The request body is larger than " + limit + " bytes");
        if ("100-continue".equalsIgnoreCase(request.headers.get("expect"))) {
          out.write("HTTP/1.1 100 Continue\r\n\r\n".getBytes(StandardCharsets.ISO_8859_1));
          out.flush();
        }
        byte[] content = new byte[(int) length];
        int filled = 0;
        long started = System.nanoTime();
        long allowed = BODY_GRACE_MILLIS + length * 1000 / BODY_BYTES_PER_SECOND;
        while (filled < content.length) {
          long elapsed = (System.nanoTime() - started) / 1000000L;
          boolean behind = filled < (elapsed - BODY_GRACE_MILLIS) * BODY_BYTES_PER_SECOND / 1000;
          if (elapsed >= allowed || behind) throw new java.net.SocketTimeoutException("Request body arrived too slowly");
          pace.readWithin((int) Math.min(LONGEST_READ_MILLIS, allowed - elapsed));
          int count = in.read(content, filled, content.length - filled);
          if (count < 0) throw new EOFException();
          filled += count;
        }
        return content;
      }
    };
  }

  static void write(OutputStream out, Response response) throws IOException {
    StringBuilder head = new StringBuilder("HTTP/1.1 ").append(response.status).append(' ').append(reason(response.status)).append("\r\n");
    if (response.contentType != null) head.append("Content-Type: ").append(response.contentType).append("\r\n");
    if (response.status != 204 && response.status != 304) head.append("Content-Length: ").append(response.body.length).append("\r\n");
    head.append("Cache-Control: no-store\r\nConnection: close\r\n\r\n");
    out.write(head.toString().getBytes(StandardCharsets.ISO_8859_1));
    out.write(response.body);
    out.flush();
  }

  private static String reason(int status) {
    switch (status) {
      case 200: return "OK";
      case 204: return "No Content";
      case 304: return "Not Modified";
      case 400: return "Bad Request";
      case 401: return "Unauthorized";
      case 404: return "Not Found";
      case 409: return "Conflict";
      case 413: return "Payload Too Large";
      case 429: return "Too Many Requests";
      default: return "Internal Server Error";
    }
  }
}
