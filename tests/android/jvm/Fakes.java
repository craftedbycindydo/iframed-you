package com.wesbos.homehq;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

final class Fakes {
  static final LocalHttp.Pace UNPACED = new LocalHttp.Pace() {
    @Override public void readWithin(int millis) {}
  };

  private Fakes() {}

  static final class Storage implements KeyValue {
    final Map<String, String> values = new HashMap<>();

    @Override public synchronized String get(String key) {
      return values.get(key);
    }

    @Override public synchronized void put(String key, String value) {
      values.put(key, value);
    }
  }

  static final class Clock implements FrameTime.Clock {
    volatile long now;
    volatile long jumped;
    final FrameTime.Uptime steady = new FrameTime.Uptime() {
      @Override public long millis() {
        return now;
      }
    };

    Clock(long now) {
      this.now = now;
    }

    @Override public long now() {
      return now + jumped;
    }
  }

  static final class Uptime implements FrameTime.Uptime {
    volatile long now = 5000L;

    @Override public long millis() {
      return now;
    }
  }

  interface Wire {
    Reply send(byte[] raw) throws Exception;
  }

  static final class Phone {
    final byte[] nP = random(32);
    final byte[] token = random(32);
    String session;
    byte[] nF;
    String code;
    String pick;

    String bearer() {
      return Digests.hex(token);
    }

    Reply start(Wire wire, String name) throws Exception {
      Reply reply = wire.send(json("POST", "/v2/pair/start", null, Json.write(Json.object("commit", Digests.sha256(nP),
          "tokenHash", Digests.sha256(token), "deviceName", name))));
      if (reply.status == 200) {
        session = (String) reply.object().get("session");
        nF = Digests.bytes(reply.object().get("nF"));
      }
      return reply;
    }

    Reply reveal(Wire wire, byte[] fpRaw) throws Exception {
      byte[] digest = Pairing.digest(nP, nF, fpRaw);
      code = Pairing.code(digest);
      pick = Pairing.pick(digest);
      return wire.send(json("POST", "/v2/pair/reveal", null, Json.write(Json.object("session", session, "nP", Digests.hex(nP)))));
    }

    Reply result(Wire wire) throws Exception {
      return wire.send(json("GET", "/v2/pair/result?session=" + session, null, null));
    }

    Reply cancel(Wire wire) throws Exception {
      return wire.send(json("POST", "/v2/pair/cancel", null, Json.write(Json.object("session", session))));
    }
  }

  static byte[] random(int length) {
    byte[] bytes = new byte[length];
    new java.security.SecureRandom().nextBytes(bytes);
    return bytes;
  }

  static Wire memory(final LocalApi api) {
    return new Wire() {
      @Override public Reply send(byte[] raw) throws Exception {
        return inMemory(api, raw);
      }
    };
  }

  static Wire socket(final InetAddress address, final int port) {
    return new Wire() {
      @Override public Reply send(byte[] raw) throws Exception {
        return overSocket(address, port, raw);
      }
    };
  }

  static String pair(LocalApi api, Recorder events, Wire wire, String name) throws Exception {
    Phone phone = new Phone();
    if (!api.pairingOpen().contains("\"ok\":true")) throw new AssertionError("the pairing window did not open");
    Reply started = phone.start(wire, name);
    if (started.status != 200) throw new AssertionError("pair start returned " + started.status + " " + started.text());
    int revealed = phone.reveal(wire, api.identity().fpRaw).status;
    if (revealed != 204) throw new AssertionError("pair reveal returned " + revealed);
    if (!phone.code.equals(events.pairing.get("code"))) throw new AssertionError("the phone and the frame disagree on the code");
    if (!api.pairingTap(phone.pick)) throw new AssertionError("tapping the phone's number did not approve");
    Reply result = phone.result(wire);
    if (result.status != 200) throw new AssertionError("pair result returned " + result.status);
    api.pairingCancel();
    return phone.bearer();
  }

  static final class CalendarShelf implements LocalApi.Calendars {
    private final List<Map<String, Object>> feeds = new ArrayList<>();
    private int created;

    @Override public synchronized List<Object> list() {
      List<Object> visible = new ArrayList<>();
      for (Map<String, Object> feed : feeds) {
        visible.add(Json.object("id", feed.get("id"), "name", feed.get("name"), "color", feed.get("color"), "fetchedAt", 0));
      }
      return visible;
    }

    @Override public synchronized String add(String name, String color, String url) {
      if (!CalendarFeed.valid(url) || feeds.size() >= 6) return "";
      for (Map<String, Object> feed : feeds) if (feed.get("url").equals(url)) return "";
      String id = "k" + (++created);
      feeds.add(Json.object("id", id, "name", name, "color", color, "url", url));
      return id;
    }

    @Override public synchronized boolean remove(String id) {
      for (int i = 0; i < feeds.size(); i++) {
        if (feeds.get(i).get("id").equals(id)) {
          feeds.remove(i);
          return true;
        }
      }
      return false;
    }
  }

  static final class PhotoShelf implements LocalApi.Photos {
    private final Map<String, byte[]> images = new LinkedHashMap<>();
    private final Map<String, Long> added = new HashMap<>();
    final Set<String> fromAlbum = new HashSet<>();
    final Set<String> hidden = new HashSet<>();
    volatile boolean accepting = true;
    volatile int capacity = 30;
    volatile int albumDownloads;

    final ICloudSync.Library library = new ICloudSync.Library() {
      @Override public List<ICloudAlbum.Stored> pictures() {
        synchronized (PhotoShelf.this) {
          List<ICloudAlbum.Stored> stored = new ArrayList<>();
          for (LocalApi.Photo photo : list()) stored.add(new ICloudAlbum.Stored(photo.id, photo.addedAt, fromAlbum.contains(photo.id)));
          return stored;
        }
      }

      @Override public Set<String> excluded() {
        synchronized (PhotoShelf.this) {
          return new HashSet<>(hidden);
        }
      }

      @Override public boolean add(byte[] image, long at) {
        synchronized (PhotoShelf.this) {
          albumDownloads++;
          String id = Digests.sha256(image);
          if (!accepting || hidden.contains(id)) return false;
          if (!images.containsKey(id)) {
            images.put(id, image);
            added.put(id, at);
            fromAlbum.add(id);
          }
          return true;
        }
      }

      @Override public void remove(String id) {
        synchronized (PhotoShelf.this) {
          if (fromAlbum.contains(id)) PhotoShelf.this.remove(id);
        }
      }

      @Override public void removeAll() {
        synchronized (PhotoShelf.this) {
          for (String id : new ArrayList<>(fromAlbum)) PhotoShelf.this.remove(id);
        }
      }

      @Override public int capacity() {
        return capacity;
      }
    };

    synchronized void trash(String id) {
      remove(id);
      hidden.add(id);
    }

    @Override public synchronized List<LocalApi.Photo> list() {
      List<LocalApi.Photo> listed = new ArrayList<>();
      for (String id : images.keySet()) listed.add(new LocalApi.Photo(id, added.get(id)));
      Collections.sort(listed, new Comparator<LocalApi.Photo>() {
        @Override public int compare(LocalApi.Photo left, LocalApi.Photo right) {
          return Long.compare(right.addedAt, left.addedAt);
        }
      });
      return listed;
    }

    @Override public synchronized boolean add(byte[] jpeg, long addedAt) {
      if (!accepting) return false;
      String id = Digests.sha256(jpeg);
      images.put(id, jpeg);
      added.put(id, addedAt);
      return true;
    }

    @Override public synchronized byte[] read(String id) {
      return images.get(id);
    }

    @Override public synchronized boolean remove(String id) {
      added.remove(id);
      fromAlbum.remove(id);
      return images.remove(id) != null;
    }
  }

  static class Album implements ICloudAlbum.Transport {
    final List<Map<String, Object>> photos = new ArrayList<>();
    final Map<String, byte[]> assets = new HashMap<>();
    final Set<String> expired = new HashSet<>();
    final List<String> posts = Collections.synchronizedList(new ArrayList<String>());
    volatile String name = "Family";
    volatile String home;
    volatile String location = "cvws.icloud-content.com";
    volatile String rawStream;
    volatile String rawUrls;
    volatile int status = 200;
    volatile boolean offline;
    volatile boolean alwaysMoved;
    volatile int downloads;

    synchronized String add(String guid, String created, byte[] image, int... edges) {
      Map<String, Object> derivatives = new LinkedHashMap<>();
      String largest = null;
      for (int edge : edges) {
        String checksum = Digests.sha256((guid + edge).getBytes(StandardCharsets.UTF_8)).substring(0, 40);
        derivatives.put(String.valueOf(edge * 3 / 4), Json.object("checksum", checksum, "fileSize", String.valueOf(image.length),
            "width", String.valueOf(edge), "height", String.valueOf(edge * 3 / 4)));
        assets.put(checksum, image);
        largest = checksum;
      }
      photos.add(Json.object("photoGuid", guid, "dateCreated", created, "batchDateCreated", created, "caption", "",
          "mediaAssetType", null, "derivatives", derivatives));
      return largest;
    }

    synchronized void addVideo(String guid, String created) {
      Map<String, Object> row = Json.object("photoGuid", guid, "dateCreated", created, "mediaAssetType", "video");
      row.put("derivatives", Json.object("PosterFrame", Json.object("checksum", Digests.sha256(guid.getBytes(StandardCharsets.UTF_8)).substring(0, 40),
          "fileSize", "1000", "width", "640", "height", "480")));
      photos.add(row);
    }

    synchronized void drop(String guid) {
      for (int i = 0; i < photos.size(); i++) if (photos.get(i).get("photoGuid").equals(guid)) photos.remove(i--);
    }

    @Override public synchronized ICloudAlbum.Reply post(String url, String body) throws IOException {
      String host = ICloudHttp.allowed(url, true).getHost();
      posts.add(url + " " + body);
      if (offline) throw new IOException("offline");
      if (alwaysMoved) return new ICloudAlbum.Reply(330, "{\"X-Apple-MMe-Host\":\"p" + (posts.size() % 90 + 10) + "-sharedstreams.icloud.com\"}");
      if (home != null && !home.equals(host)) return new ICloudAlbum.Reply(330, Json.write(Json.object("X-Apple-MMe-Host", home)));
      if (status != 200) return new ICloudAlbum.Reply(status, "");
      if (url.endsWith("/webstream")) {
        if (rawStream != null) return new ICloudAlbum.Reply(200, rawStream);
        return new ICloudAlbum.Reply(200, Json.write(Json.object("streamName", name, "userFirstName", "A", "streamCtag", "ctag",
            "itemsReturned", String.valueOf(photos.size()), "photos", new ArrayList<Object>(photos))));
      }
      if (rawUrls != null) return new ICloudAlbum.Reply(200, rawUrls);
      Map<String, Object> items = new LinkedHashMap<>();
      try {
        for (Object guid : Json.list(Json.map(Json.parse(body)).get("photoGuids"))) {
          for (Map<String, Object> photo : photos) {
            if (!photo.get("photoGuid").equals(guid)) continue;
            for (Object derivative : Json.map(photo.get("derivatives")).values()) {
              String checksum = (String) Json.map(derivative).get("checksum");
              items.put(checksum, Json.object("url_expiry", "2026-10-12T03:00:00Z", "url_location", location, "url_path", "/S/" + checksum + "/IMG.JPG?o=abc&v=1&z=https%3A%2F%2Fp10-content.icloud.com%3A443&e=1"));
            }
          }
        }
      } catch (Json.Malformed impossible) {
        throw new IOException(impossible);
      }
      return new ICloudAlbum.Reply(200, Json.write(Json.object("locations", Json.object(), "items", items)));
    }

    @Override public synchronized byte[] get(String url, int limit) throws IOException {
      ICloudHttp.allowed(url, false);
      downloads++;
      String checksum = url.split("/")[4];
      if (offline || expired.contains(checksum) || !assets.containsKey(checksum)) throw new IOException("unavailable");
      if (assets.get(checksum).length > limit) throw new IOException("too large");
      return assets.get(checksum);
    }
  }

  static byte[] picture(int seed) {
    try {
      java.awt.image.BufferedImage image = new java.awt.image.BufferedImage(960, 720, java.awt.image.BufferedImage.TYPE_INT_RGB);
      java.awt.Graphics2D paint = image.createGraphics();
      paint.setPaint(new java.awt.GradientPaint(0, 0, java.awt.Color.getHSBColor(seed * 0.17f, 0.45f, 0.95f), 960, 720, java.awt.Color.getHSBColor(seed * 0.17f + 0.2f, 0.6f, 0.6f)));
      paint.fillRect(0, 0, 960, 720);
      paint.setColor(java.awt.Color.WHITE);
      paint.fillOval(180 + seed * 60, 200, 260, 260);
      paint.dispose();
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      javax.imageio.ImageIO.write(image, "jpg", out);
      return out.toByteArray();
    } catch (IOException impossible) {
      throw new IllegalStateException(impossible);
    }
  }

  static Album sampleAlbum() {
    Album album = new Album();
    for (int i = 1; i <= 4; i++) album.add("0000000" + i + "-AAAA-BBBB-CCCC-00000000000" + i, "2026-10-0" + i + "T12:00:00Z", picture(i), 342, 2048);
    album.addVideo("00000009-AAAA-BBBB-CCCC-000000000009", "2026-10-09T12:00:00Z");
    return album;
  }

  static ICloudSync.Runner inline() {
    return new ICloudSync.Runner() {
      @Override public void start(Runnable work) {
        work.run();
      }
    };
  }

  static final class Recorder implements LocalApi.Events {
    final List<String> seen = Collections.synchronizedList(new ArrayList<String>());
    final ICloudSync.Listener album = new ICloudSync.Listener() {
      @Override public void changed() {
        seen.add("album");
      }
    };
    volatile Map<String, Object> pairing = Json.object("phase", "idle");
    volatile long remaining = -1;
    volatile String snapshot;
    volatile String settings;

    @Override public void householdChanged(String latest) {
      snapshot = latest;
      seen.add("household");
    }

    @Override public void pairingChanged(String state, long left) {
      try {
        pairing = Json.map(Json.parse(state));
      } catch (Json.Malformed impossible) {
        throw new IllegalStateException(impossible);
      }
      remaining = left;
      seen.add((String) pairing.get("phase"));
    }

    @Override public void settingsRequested(String requested) {
      settings = requested;
      seen.add("settings");
    }

    int count(String event) {
      int total = 0;
      synchronized (seen) {
        for (String entry : seen) if (entry.equals(event)) total++;
      }
      return total;
    }
  }

  static final class Reply {
    final int status;
    final Map<String, String> headers = new HashMap<>();
    final byte[] body;
    final byte[] raw;
    byte[] fpRaw;
    String suite;

    Reply(byte[] raw) {
      this.raw = raw;
      int split = -1;
      for (int i = 0; i + 3 < raw.length && split < 0; i++) {
        if (raw[i] == '\r' && raw[i + 1] == '\n' && raw[i + 2] == '\r' && raw[i + 3] == '\n') split = i;
      }
      String[] lines = new String(raw, 0, split, StandardCharsets.ISO_8859_1).split("\r\n");
      status = Integer.parseInt(lines[0].split(" ")[1]);
      for (int i = 1; i < lines.length; i++) {
        int colon = lines[i].indexOf(':');
        headers.put(lines[i].substring(0, colon).toLowerCase(), lines[i].substring(colon + 1).trim());
      }
      body = java.util.Arrays.copyOfRange(raw, split + 4, raw.length);
    }

    String text() {
      return new String(body, StandardCharsets.UTF_8);
    }

    Map<String, Object> object() throws Json.Malformed {
      return Json.map(Json.parse(text()));
    }

    List<Object> list() throws Json.Malformed {
      return Json.list(Json.parse(text()));
    }

    String error() throws Json.Malformed {
      return (String) Json.map(object().get("error")).get("code");
    }
  }

  static byte[] request(String method, String target, String token, String contentType, byte[] body) {
    StringBuilder head = new StringBuilder(method + " " + target + " HTTP/1.1\r\nHost: 192.168.1.20:8765\r\n");
    if (token != null) head.append("Authorization: Bearer ").append(token).append("\r\n");
    if (contentType != null) head.append("Content-Type: ").append(contentType).append("\r\n");
    if (body != null) head.append("Content-Length: ").append(body.length).append("\r\n");
    head.append("\r\n");
    return join(head.toString().getBytes(StandardCharsets.ISO_8859_1), body == null ? new byte[0] : body);
  }

  static byte[] json(String method, String target, String token, String json) {
    return request(method, target, token, json == null ? null : "application/json",
        json == null ? null : json.getBytes(StandardCharsets.UTF_8));
  }

  static byte[] join(byte[] first, byte[] second) {
    byte[] joined = java.util.Arrays.copyOf(first, first.length + second.length);
    System.arraycopy(second, 0, joined, first.length, second.length);
    return joined;
  }

  static Reply inMemory(LocalApi api, byte[] raw) throws IOException {
    InputStream in = new ByteArrayInputStream(raw);
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    LocalHttp.Response response;
    try {
      LocalHttp.Request request = LocalHttp.readHead(in);
      response = api.handle(request, LocalHttp.body(request, in, out, UNPACED));
    } catch (ApiException malformed) {
      response = LocalHttp.Response.error(malformed);
    }
    LocalHttp.write(out, response);
    return new Reply(out.toByteArray());
  }

  static Reply overSocket(int port, byte[] raw) throws IOException {
    return overSocket(InetAddress.getLoopbackAddress(), port, raw);
  }

  static SSLSocket tls(InetAddress address, int port, String protocol, String... suites) throws IOException {
    try {
      SSLContext context = SSLContext.getInstance("TLS");
      context.init(null, new TrustManager[] {new X509TrustManager() {
        @Override public void checkClientTrusted(java.security.cert.X509Certificate[] chain, String type) {}

        @Override public void checkServerTrusted(java.security.cert.X509Certificate[] chain, String type) {}

        @Override public java.security.cert.X509Certificate[] getAcceptedIssuers() {
          return new java.security.cert.X509Certificate[0];
        }
      }}, null);
      SSLSocket socket = (SSLSocket) context.getSocketFactory().createSocket(address, port);
      socket.setEnabledProtocols(new String[] {protocol});
      socket.setEnabledCipherSuites(suites.length == 0 ? LocalServer.SUITES : suites);
      socket.setSoTimeout(20000);
      return socket;
    } catch (java.security.GeneralSecurityException impossible) {
      throw new IOException(impossible);
    }
  }

  static SSLSocket tls(InetAddress address, int port) throws IOException {
    SSLSocket socket = tls(address, port, LocalServer.PROTOCOL);
    socket.startHandshake();
    return socket;
  }

  static Reply overSocket(InetAddress address, int port, byte[] raw) throws IOException {
    try (SSLSocket socket = tls(address, port)) {
      OutputStream out = socket.getOutputStream();
      out.write(raw);
      out.flush();
      ByteArrayOutputStream received = new ByteArrayOutputStream();
      InputStream in = socket.getInputStream();
      byte[] buffer = new byte[65536];
      for (int count; (count = in.read(buffer)) >= 0;) received.write(buffer, 0, count);
      Reply reply = new Reply(received.toByteArray());
      reply.fpRaw = Digests.digest(socket.getSession().getPeerCertificates()[0].getEncoded());
      reply.suite = socket.getSession().getCipherSuite();
      return reply;
    } catch (java.security.cert.CertificateEncodingException impossible) {
      throw new IOException(impossible);
    }
  }

  static byte[] jpeg(int seed, int length) {
    byte[] image = new byte[length];
    new java.util.Random(seed).nextBytes(image);
    image[0] = (byte) 0xFF;
    image[1] = (byte) 0xD8;
    image[2] = (byte) 0xFF;
    image[3] = (byte) 0xE0;
    return image;
  }
}
