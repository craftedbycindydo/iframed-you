package com.wesbos.homehq;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public final class LocalServerTest {
  static int checks;
  static int port;
  static String token;

  static void check(boolean value, String message) {
    if (!value) throw new AssertionError(message);
    checks++;
  }

  static void same(Object expected, Object actual, String message) {
    check(expected.equals(actual), message + ": expected " + expected + " but was " + actual);
  }

  static Fakes.Reply call(String method, String target, String json) throws Exception {
    return Fakes.overSocket(port, Fakes.json(method, target, token, json));
  }

  static Socket opened(InetAddress address, String beginning) throws Exception {
    Socket socket = new Socket(address, port);
    socket.getOutputStream().write(beginning.getBytes(StandardCharsets.ISO_8859_1));
    socket.getOutputStream().flush();
    return socket;
  }

  static long closedAfter(Socket socket, long began, long patienceMillis) throws Exception {
    socket.setSoTimeout(250);
    InputStream in = socket.getInputStream();
    while ((System.nanoTime() - began) / 1000000L < patienceMillis) {
      try {
        if (in.read() < 0) return (System.nanoTime() - began) / 1000000L;
      } catch (SocketTimeoutException open) {
        continue;
      } catch (java.io.IOException reset) {
        return (System.nanoTime() - began) / 1000000L;
      }
    }
    return patienceMillis;
  }

  static Fakes.Reply as(InetAddress from, String bearer, String method, String target, String json) throws Exception {
    return Fakes.overSocket(from, port, Fakes.json(method, target, bearer, json));
  }

  static Fakes.Reply throttled(InetAddress from, byte[] request, int pieces, long pauseMillis) throws Exception {
    try (Socket socket = new Socket(from, port)) {
      socket.setSoTimeout(60000);
      OutputStream out = socket.getOutputStream();
      int piece = request.length / pieces + 1;
      for (int sent = 0; sent < request.length; sent += piece) {
        out.write(request, sent, Math.min(piece, request.length - sent));
        out.flush();
        Thread.sleep(pauseMillis);
      }
      java.io.ByteArrayOutputStream received = new java.io.ByteArrayOutputStream();
      byte[] buffer = new byte[65536];
      for (int count; (count = socket.getInputStream().read(buffer)) >= 0;) received.write(buffer, 0, count);
      return new Fakes.Reply(received.toByteArray());
    }
  }

  static void households(LocalApi api, Fakes.Recorder events, Fakes.Clock clock) throws Exception {
    final InetAddress first = InetAddress.getLoopbackAddress();
    final InetAddress second = InetAddress.getByName("::1");
    clock.now += 700000L;
    final String[] tokens = new String[3];
    final InetAddress[] homes = {first, second, first};
    for (int device = 0; device < 3; device++) {
      same(204, as(homes[device], null, "POST", "/v1/pair/start", null).status, "device " + device + " starts pairing");
      Fakes.Reply paired = as(homes[device], null, "POST", "/v1/pair/finish", "{\"code\":\"" + events.code + "\",\"deviceName\":\"Family phone " + device + "\"}");
      same(200, paired.status, "device " + device + " pairs over the socket");
      tokens[device] = (String) paired.object().get("token");
    }
    check(!tokens[0].equals(tokens[1]) && !tokens[1].equals(tokens[2]) && !tokens[0].equals(tokens[2]), "three devices hold three tokens");
    long base = (Long) as(first, tokens[0], "GET", "/v1/state", null).object().get("rev");
    same(200, as(second, tokens[1], "POST", "/v1/shopping", "{\"name\":\"From the second phone\"}").status, "one device writes");
    for (int device = 0; device < 3; device++) {
      Fakes.Reply seen = as(homes[device], tokens[device], "GET", "/v1/state?since=" + base, null);
      same(200, seen.status, "device " + device + " is told about the change");
      same(base + 1, seen.object().get("rev"), "device " + device + " sees exactly one revision");
      check(seen.text().contains("From the second phone"), "device " + device + " sees the other device's item");
      same(304, as(homes[device], tokens[device], "GET", "/v1/state?since=" + (base + 1), null).status, "device " + device + " is then up to date");
    }

    ExecutorService phones = Executors.newFixedThreadPool(12);
    List<Future<Map<String, Object>>> writes = new ArrayList<>();
    for (int write = 0; write < 12; write++) {
      final int number = write;
      writes.add(phones.submit(new Callable<Map<String, Object>>() {
        @Override public Map<String, Object> call() throws Exception {
          Fakes.Reply reply = as(homes[number % 3], tokens[number % 3], "POST", "/v1/shopping", "{\"name\":\"Together " + number + "\"}");
          same(200, reply.status, "simultaneous write " + number);
          return reply.object();
        }
      }));
    }
    java.util.Set<Object> ids = new java.util.HashSet<>();
    java.util.TreeSet<Long> revisions = new java.util.TreeSet<>();
    for (Future<Map<String, Object>> write : writes) {
      ids.add(Json.map(write.get().get("item")).get("id"));
      revisions.add((Long) write.get().get("rev"));
    }
    phones.shutdown();
    same(12, ids.size(), "twelve simultaneous writes from three devices get twelve ids");
    same(12, revisions.size(), "and twelve different revisions");
    same(base + 2, revisions.first(), "with no gap before them");
    same(base + 13, revisions.last(), "and none between them");
    Map<String, Object> together = as(second, tokens[1], "GET", "/v1/state", null).object();
    same(base + 13, together.get("rev"), "the frame ends on the last revision");
    int landed = 0;
    for (Object item : Json.list(together.get("shopping"))) if (((String) Json.map(item).get("name")).startsWith("Together ")) landed++;
    same(12, landed, "no simultaneous write is lost");

    final byte[] large = Fakes.jpeg(77, LocalApi.MAX_PHOTO);
    final boolean[] uploading = {true};
    final long[] slowestPoll = {0};
    final int[] polls = {0};
    Thread poller = new Thread(new Runnable() {
      @Override public void run() {
        try {
          while (uploading[0]) {
            long asked = System.nanoTime();
            int status = as(first, tokens[0], "GET", "/v1/state?since=0", null).status;
            if (status != 200) throw new AssertionError("poll during upload returned " + status);
            slowestPoll[0] = Math.max(slowestPoll[0], (System.nanoTime() - asked) / 1000000L);
            polls[0]++;
            Thread.sleep(150);
          }
        } catch (Exception failed) {
          slowestPoll[0] = Long.MAX_VALUE;
        }
      }
    });
    poller.start();
    ExecutorService senders = Executors.newFixedThreadPool(2);
    Future<Fakes.Reply> bigUpload = senders.submit(new Callable<Fakes.Reply>() {
      @Override public Fakes.Reply call() throws Exception {
        return throttled(first, Fakes.request("POST", "/v1/photos", tokens[0], "image/jpeg", large), 30, 100);
      }
    });
    Future<Fakes.Reply> otherUpload = senders.submit(new Callable<Fakes.Reply>() {
      @Override public Fakes.Reply call() throws Exception {
        return throttled(first, Fakes.request("POST", "/v1/photos", tokens[2], "image/jpeg", Fakes.jpeg(78, 3 * 1024 * 1024)), 20, 100);
      }
    });
    Fakes.Reply stored = bigUpload.get();
    Fakes.Reply alsoStored = otherUpload.get();
    uploading[0] = false;
    poller.join();
    senders.shutdown();
    same(200, stored.status, "a 15 MiB upload succeeds while the same address keeps polling");
    same(Digests.sha256(large), Json.map(stored.object().get("photo")).get("id"), "the large upload is stored intact");
    same(200, alsoStored.status, "a second phone behind the same address uploads at the same time");
    check(polls[0] >= 5 && slowestPoll[0] < 2000, "state polls from the uploading address stay quick, " + polls[0] + " polls, slowest " + slowestPoll[0] + " ms");

    String revokedId = null;
    for (Object device : as(first, tokens[0], "GET", "/v1/devices", null).list()) {
      if (Json.map(device).get("name").equals("Family phone 2")) revokedId = (String) Json.map(device).get("id");
    }
    same(204, as(first, tokens[0], "DELETE", "/v1/devices/" + revokedId, null).status, "one device is revoked");
    same(401, as(first, tokens[2], "GET", "/v1/state", null).status, "the revoked device is refused");
    same(200, as(first, tokens[0], "GET", "/v1/state", null).status, "the first device keeps working");
    same(200, as(second, tokens[1], "POST", "/v1/shopping", "{\"name\":\"Still here\"}").status, "the second device keeps writing");
    clock.now += 700000L;
    same(204, as(first, null, "POST", "/v1/pair/start", null).status, "the revoked device pairs again");
    Fakes.Reply again = as(first, null, "POST", "/v1/pair/finish", "{\"code\":\"" + events.code + "\",\"deviceName\":\"Family phone 2\"}");
    String renewed = (String) again.object().get("token");
    check(!renewed.equals(tokens[2]), "re-pairing issues a new token");
    same(200, as(first, renewed, "GET", "/v1/state", null).status, "the new token works");
    same(401, as(first, tokens[2], "GET", "/v1/state", null).status, "the old token stays dead");
  }

  public static void main(String[] args) throws Exception {
    Fakes.Recorder events = new Fakes.Recorder();
    Fakes.Clock clock = new Fakes.Clock(1791676800000L);
    Fakes.Storage storage = new Fakes.Storage();
    Fakes.PhotoShelf shelf = new Fakes.PhotoShelf();
    ICloudSync icloud = new ICloudSync(storage, clock, Fakes.sampleAlbum(), shelf.library, Fakes.inline(), events.album);
    LocalApi api = new LocalApi(storage, clock, new Fakes.CalendarShelf(), shelf, icloud, events);
    LocalServer server = new LocalServer(api);
    InetAddress loopback = InetAddress.getLoopbackAddress();
    port = server.start(null, 0);
    check(port > 0 && server.port() == port, "an ephemeral port is bound");
    same(port, server.start(null, 0), "starting twice keeps the same listener");

    LocalServer neighbour = new LocalServer(api);
    int fallback = neighbour.start(null, port);
    check(fallback > 0 && fallback != port, "a taken port falls back to a free one");
    same(200, Fakes.overSocket(fallback, Fakes.json("GET", "/v1/info", null, null)).status, "the fallback listener serves");
    neighbour.stop();
    same(0, neighbour.port(), "a stopped server reports no port");

    Fakes.Reply info = call("GET", "/v1/info", null);
    same(200, info.status, "info");
    same(api.frameId(), info.object().get("frameId"), "info frame id");
    same("close", info.headers.get("connection"), "connection close");
    same(401, call("GET", "/v1/state", null).status, "state needs pairing");

    same(204, call("POST", "/v1/pair/start", null).status, "pair start");
    check(events.code != null, "the frame shows a code");
    same(401, call("POST", "/v1/pair/finish", "{\"code\":\"" + (events.code.equals("111111") ? "222222" : "111111") + "\",\"deviceName\":\"Karan's iPhone\"}").status, "wrong code");
    Fakes.Reply paired = call("POST", "/v1/pair/finish", "{\"code\":\"" + events.code + "\",\"deviceName\":\"Karan's iPhone\"}");
    same(200, paired.status, "pair finish");
    token = (String) paired.object().get("token");
    same(api.frameId(), paired.object().get("frameId"), "pair result frame id");
    same("Skylit", paired.object().get("name"), "pair result name");
    same("Karan's iPhone", Json.map(call("GET", "/v1/devices", null).list().get(0)).get("name"), "device listed");

    same(0L, call("GET", "/v1/state", null).object().get("rev"), "empty state");
    Map<String, Object> person = Json.map(call("POST", "/v1/people", "{\"name\":\"Maya\",\"color\":\"#00A36C\"}").object().get("person"));
    Map<String, Object> chore = Json.map(call("POST", "/v1/chores", "{\"title\":\"Make bed\",\"emoji\":\"🛏️\",\"personId\":\"" + person.get("id") + "\",\"days\":[1,2,3,4,5]}").object().get("chore"));
    same("🛏️", chore.get("emoji"), "UTF-8 survives the socket");
    same(200, call("PUT", "/v1/chores/" + chore.get("id") + "/done", "{\"date\":\"2026-10-11\",\"done\":true}").status, "chore done");
    Map<String, Object> item = Json.map(call("POST", "/v1/shopping", "{\"name\":\"Milk\",\"qty\":2}").object().get("item"));
    same(200, call("PATCH", "/v1/shopping/" + item.get("id"), "{\"done\":true}").status, "item ticked");
    same(200, call("POST", "/v1/shopping/clear-done", null).status, "clear done");
    same(200, call("PUT", "/v1/settings/appearance", "{\"palette\":\"ocean\",\"mode\":\"dark\"}").status, "appearance");
    same(200, call("POST", "/v1/calendars", "{\"name\":\"Family\",\"color\":\"#2D5BFF\",\"url\":\"https://calendar.google.com/calendar/ical/test%40example.org/private-test/basic.ics\"}").status, "calendar");
    same(200, call("DELETE", "/v1/people/" + person.get("id"), null).status, "person removed");

    byte[] image = Fakes.jpeg(9, 3 * 1024 * 1024);
    Fakes.Reply uploaded = Fakes.overSocket(port, Fakes.request("POST", "/v1/photos", token, "image/jpeg", image));
    same(200, uploaded.status, "photo upload");
    String photoId = (String) Json.map(uploaded.object().get("photo")).get("id");
    same(Digests.sha256(image), photoId, "photo id");
    Fakes.Reply downloaded = call("GET", "/v1/photos/" + photoId, null);
    check(java.util.Arrays.equals(image, downloaded.body), "3 MiB photo round trips over the socket");
    same(photoId, Json.map(call("GET", "/v1/photos", null).list().get(0)).get("id"), "photo listed");
    same(413, Fakes.overSocket(port, ("POST /v1/photos HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer " + token
        + "\r\nContent-Type: image/jpeg\r\nContent-Length: 16000000\r\n\r\n").getBytes(StandardCharsets.ISO_8859_1)).status, "oversize upload refused from its header");
    same(400, Fakes.overSocket(port, "NOT HTTP\r\n\r\n".getBytes(StandardCharsets.ISO_8859_1)).status, "malformed request over the socket");

    Fakes.Reply state = call("GET", "/v1/state", null);
    Map<String, Object> seen = state.object();
    same(10L, seen.get("rev"), "ten changes are ten revisions");
    same("[]", Json.write(seen.get("people")), "people");
    check(Json.map(Json.list(seen.get("chores")).get(0)).get("personId") == null, "chore unassigned");
    same("[\"2026-10-11\"]", Json.write(Json.map(Json.list(seen.get("chores")).get(0)).get("done")), "chore done date");
    same("[]", Json.write(seen.get("shopping")), "shopping cleared");
    same("{\"count\":1}", Json.write(seen.get("photos")), "photo count");
    same("ocean", Json.map(Json.map(seen.get("settings")).get("appearance")).get("palette"), "appearance in state");
    check(!state.text().contains("private-test"), "no feed url in state");
    same(304, call("GET", "/v1/state?since=10", null).status, "304 over the socket");
    same(204, call("DELETE", "/v1/photos/" + photoId, null).status, "photo delete");
    same(200, call("GET", "/v1/state?since=10", null).status, "state after delete");

    ExecutorService clients = Executors.newFixedThreadPool(8);
    List<Future<Integer>> results = new ArrayList<>();
    for (int i = 0; i < 8; i++) {
      final int number = i;
      results.add(clients.submit(new Callable<Integer>() {
        @Override public Integer call() throws Exception {
          return LocalServerTest.call("POST", "/v1/shopping", "{\"name\":\"Item " + number + "\"}").status;
        }
      }));
    }
    for (Future<Integer> result : results) same(200, result.get(), "concurrent request");
    clients.shutdown();
    same(8, Json.list(call("GET", "/v1/state", null).object().get("shopping")).size(), "concurrent writes all land");
    same(19L, call("GET", "/v1/state", null).object().get("rev"), "concurrent writes each take one revision");

    final InetAddress other = InetAddress.getByName("::1");
    final List<Socket> attackers = new ArrayList<>();
    String finish = "POST /v1/pair/finish HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: 3000\r\n\r\n{\"code\":";
    String people = "POST /v1/people HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer " + token + "\r\nContent-Length: 60000\r\n\r\n{\"name\":";
    String[] openings = {"POST /v1/people HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Le", finish, people};
    for (int i = 0; i < 12; i++) attackers.add(opened(loopback, openings[i % 3]));
    final List<Socket> dribbling = new java.util.concurrent.CopyOnWriteArrayList<>(attackers);
    final boolean[] attacking = {true};
    Thread dribble = new Thread(new Runnable() {
      @Override public void run() {
        while (attacking[0]) {
          for (Socket socket : dribbling) {
            try {
              socket.getOutputStream().write(' ');
              socket.getOutputStream().flush();
            } catch (java.io.IOException cut) {
              continue;
            }
          }
          try {
            Thread.sleep(700);
          } catch (InterruptedException stopped) {
            return;
          }
        }
      }
    });
    dribble.setDaemon(true);
    dribble.start();
    long began = System.nanoTime();
    long slowest = 0;
    for (int second = 0; second < 7; second++) {
      long asked = System.nanoTime();
      same(200, Fakes.overSocket(other, port, Fakes.json("GET", "/v1/info", null, null)).status, "an unpaired request is answered during the attack");
      same(200, Fakes.overSocket(other, port, Fakes.json("GET", "/v1/state", token, null)).status, "a paired request is answered during the attack");
      slowest = Math.max(slowest, (System.nanoTime() - asked) / 1000000L);
      Thread.sleep(1000);
    }
    check(slowest < 2000, "another device is served within two seconds while twelve sockets dribble, slowest pair took " + slowest + " ms");
    long slowBegan = System.nanoTime();
    Socket slowFinish = opened(other, finish.replace("127.0.0.1", "[::1]"));
    Socket slowUpload = opened(other, "POST /v1/photos HTTP/1.1\r\nHost: [::1]\r\nAuthorization: Bearer " + token + "\r\nContent-Type: image/jpeg\r\nContent-Length: 5000000\r\n\r\n");
    dribbling.add(slowFinish);
    dribbling.add(slowUpload);
    long finishCut = closedAfter(slowFinish, slowBegan, 9000);
    check(finishCut >= 2500 && finishCut < 6000, "a dribbled unpaired body is cut off after about three seconds, took " + finishCut + " ms");
    long uploadCut = closedAfter(slowUpload, slowBegan, 15000);
    check(uploadCut < 13000, "a photo upload far below the minimum rate is cut off, took " + uploadCut + " ms");
    int cut = 0;
    for (Socket attacker : attackers) if (closedAfter(attacker, began, 22000) < 22000) cut++;
    same(12, cut, "every dribbling socket is disconnected");
    check((System.nanoTime() - began) / 1000000L < 30000, "twelve dribbling sockets are cleared within the queue and head limits");
    attacking[0] = false;
    for (Socket socket : dribbling) socket.close();

    List<Socket> idle = new ArrayList<>();
    int opened = LocalServer.WAITING_PER_SOURCE + LocalServer.SERVED_PER_SOURCE + 2;
    for (int i = 0; i < opened; i++) idle.add(new Socket(loopback, port));
    Thread.sleep(300);
    int refused = 0;
    for (Socket socket : idle) {
      socket.setSoTimeout(200);
      try {
        if (socket.getInputStream().read() < 0) refused++;
      } catch (SocketTimeoutException held) {
        continue;
      } catch (java.io.IOException reset) {
        refused++;
      }
    }
    same(LocalServer.WAITING_PER_SOURCE + LocalServer.SERVED_PER_SOURCE, opened - refused, "one address may hold three served and twelve waiting connections");
    same(200, Fakes.overSocket(other, port, Fakes.json("GET", "/v1/info", null, null)).status, "another device is unaffected by one address filling its allowance");
    for (Socket socket : idle) socket.close();
    Thread.sleep(300);
    same(400, Fakes.overSocket(port, "GET /v1/info HTTP/1.1\r\nHost: evil.test\r\n\r\n".getBytes(StandardCharsets.ISO_8859_1)).status, "a rebound host name is refused over the socket");
    same(200, call("GET", "/v1/info", null).status, "the server is healthy after stalled clients");

    households(api, events, clock);

    server.stop();
    try {
      new Socket(loopback, port).close();
      throw new AssertionError("the listener stayed open after stop");
    } catch (java.net.ConnectException expected) {
      checks++;
    }
    System.out.println("LocalServer: " + checks + " checks passed");
  }
}
