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

  public static void main(String[] args) throws Exception {
    Fakes.Recorder events = new Fakes.Recorder();
    Fakes.Clock clock = new Fakes.Clock(1791676800000L);
    Fakes.Storage storage = new Fakes.Storage();
    Fakes.PhotoShelf shelf = new Fakes.PhotoShelf();
    ICloudSync icloud = new ICloudSync(storage, clock, Fakes.sampleAlbum(), shelf.library, Fakes.inline(), events.album);
    LocalApi api = new LocalApi(storage, clock, new Fakes.CalendarShelf(), shelf, icloud, events);
    LocalServer server = new LocalServer(api);
    InetAddress loopback = InetAddress.getLoopbackAddress();
    port = server.start(loopback, 0);
    check(port > 0 && server.port() == port, "an ephemeral port is bound");
    same(port, server.start(loopback, 0), "starting twice keeps the same listener");

    LocalServer neighbour = new LocalServer(api);
    int fallback = neighbour.start(loopback, port);
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
    same(413, Fakes.overSocket(port, ("POST /v1/photos HTTP/1.1\r\nAuthorization: Bearer " + token
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

    List<Socket> stalled = new ArrayList<>();
    for (int i = 0; i < 3; i++) {
      Socket silent = new Socket(loopback, port);
      silent.getOutputStream().write("POST /v1/people HTTP/1.1\r\nContent-Le".getBytes(StandardCharsets.ISO_8859_1));
      silent.getOutputStream().flush();
      stalled.add(silent);
    }
    Socket halfBody = new Socket(loopback, port);
    OutputStream partial = halfBody.getOutputStream();
    partial.write(("POST /v1/people HTTP/1.1\r\nAuthorization: Bearer " + token + "\r\nContent-Length: 500\r\n\r\n{\"name\":").getBytes(StandardCharsets.ISO_8859_1));
    partial.flush();
    stalled.add(halfBody);
    long began = System.nanoTime();
    for (int i = 0; i < 3; i++) same(200, call("GET", "/v1/info", null).status, "the server answers while other clients stall");
    long waited = System.nanoTime();
    for (Socket silent : stalled) {
      silent.setSoTimeout(20000);
      InputStream in = silent.getInputStream();
      try {
        check(in.read() < 0, "a stalled client is disconnected without a reply");
      } catch (SocketTimeoutException stillOpen) {
        throw new AssertionError("a stalled client kept its connection");
      } catch (java.io.IOException reset) {
        checks++;
      }
      silent.close();
    }
    check((System.nanoTime() - began) / 1000000L < 19000L, "stalled clients are dropped within the read timeout");
    same(200, call("GET", "/v1/info", null).status, "the server is healthy after stalled clients");

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
