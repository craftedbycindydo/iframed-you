package com.wesbos.homehq;

import java.io.ByteArrayInputStream;
import java.io.EOFException;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.TimeZone;

public final class LocalApiTest {
  static final long START = 1791676800000L;
  static final long DAY = 86400000L;
  static final String FEED = "https://calendar.google.com/calendar/ical/test%40example.org/private-test/basic.ics";
  static int checks;

  static Fakes.Storage storage;
  static Fakes.Clock clock;
  static Fakes.CalendarShelf calendars;
  static Fakes.PhotoShelf photos;
  static Fakes.Recorder events;
  static LocalApi api;
  static String token;

  static Fakes.Album album = new Fakes.Album();
  static ICloudSync icloud;

  static ICloudSync sync(Fakes.Recorder recorder) {
    icloud = new ICloudSync(storage, clock, album, photos.library, Fakes.inline(), recorder.album);
    return icloud;
  }

  static void check(boolean value, String message) {
    if (!value) throw new AssertionError(message);
    checks++;
  }

  static void same(Object expected, Object actual, String message) {
    check(expected == null ? actual == null : expected.equals(actual), message + ": expected " + expected + " but was " + actual);
  }

  static void fresh() throws Exception {
    storage = new Fakes.Storage();
    clock = new Fakes.Clock(START);
    calendars = new Fakes.CalendarShelf();
    photos = new Fakes.PhotoShelf();
    events = new Fakes.Recorder();
    album = new Fakes.Album();
    api = new LocalApi(storage, clock, calendars, photos, sync(events), events);
    token = pair("Test phone");
  }

  static String pair(String deviceName) throws Exception {
    same(204, send("POST", "/v1/pair/start", null, null).status, "pair start");
    Fakes.Reply finished = send("POST", "/v1/pair/finish", null,
        "{\"code\":\"" + events.code + "\",\"deviceName\":\"" + deviceName + "\"}");
    same(200, finished.status, "pair finish");
    return (String) finished.object().get("token");
  }

  static Fakes.Reply send(String method, String target, String bearer, String json) throws Exception {
    return Fakes.inMemory(api, Fakes.json(method, target, bearer, json));
  }

  static Fakes.Reply call(String method, String target, String json) throws Exception {
    return send(method, target, token, json);
  }

  static Fakes.Reply raw(String text) throws Exception {
    return Fakes.inMemory(api, text.getBytes(StandardCharsets.ISO_8859_1));
  }

  static Map<String, Object> state() throws Exception {
    Fakes.Reply reply = call("GET", "/v1/state", null);
    same(200, reply.status, "state");
    return reply.object();
  }

  static long rev() throws Exception {
    return (Long) state().get("rev");
  }

  static Map<String, Object> row(Fakes.Reply reply, String key) throws Exception {
    same(200, reply.status, key + " status " + reply.text());
    return Json.map(reply.object().get(key));
  }

  static String repeat(String unit, int times) {
    StringBuilder text = new StringBuilder();
    for (int i = 0; i < times; i++) text.append(unit);
    return text.toString();
  }

  static void json() throws Exception {
    Map<String, Object> parsed = Json.map(Json.parse(" {\"a\":[1,-2.5,1e3,true,false,null],\"b\":\"x\\n\\u00e9\\\"\\ud83d\\ude00\",\"c\":{}} "));
    List<Object> numbers = Json.list(parsed.get("a"));
    same(1L, numbers.get(0), "integers stay whole");
    same(-2.5, numbers.get(1), "decimals parse");
    same(1000.0, numbers.get(2), "exponents parse");
    same("x\n\u00e9\"\ud83d\ude00", parsed.get("b"), "escapes decode");
    same(parsed, Json.parse(Json.write(parsed)), "write then parse round trips");
    same("\"\\u2028\\u0001\"", Json.write("\u2028\u0001"), "script-breaking characters are escaped");
    same("{\"n\":2,\"d\":51.05}", Json.write(Json.object("n", 2L, "d", 51.05)), "numbers keep their shape");
    String[] malformed = {"", "{", "{\"a\":1,}", "[1 2]", "{\"a\":01}", "\"\t\"", "{\"a\":1} x", "nul", "{a:1}", "\"\\x\"",
        "1e999", "-", repeat("[", 40) + repeat("]", 40)};
    for (String text : malformed) {
      try {
        Json.parse(text);
        throw new AssertionError("accepted malformed JSON " + text);
      } catch (Json.Malformed expected) {
        checks++;
      }
    }
  }

  static void http() throws Exception {
    fresh();
    same(400, raw("GARBAGE\r\n\r\n").status, "missing target and version");
    same(400, raw("get /v1/info HTTP/1.1\r\n\r\n").status, "lowercase method");
    same(400, raw("GET /v1/info HTTP/2.0\r\n\r\n").status, "unsupported version");
    same(400, raw("GET  /v1/info HTTP/1.1\r\n\r\n").status, "double space");
    same(400, raw("GET v1/info HTTP/1.1\r\n\r\n").status, "relative target");
    same(400, raw("GET /v1/photos/../../etc/passwd HTTP/1.1\r\n\r\n").status, "dot traversal");
    same(400, raw("GET /v1/photos/%2e%2e/secret HTTP/1.1\r\n\r\n").status, "encoded traversal");
    same(400, raw("GET /v1//state HTTP/1.1\r\n\r\n").status, "empty segment");
    same(400, raw("GET /v1/photos\\x HTTP/1.1\r\n\r\n").status, "backslash");
    same(400, raw("GET /v1/info HTTP/1.1\r\nNoColon\r\n\r\n").status, "header without colon");
    same(400, raw("GET /v1/info HTTP/1.1\r\nX-Long: " + repeat("a", 9000) + "\r\n\r\n").status, "oversize head");
    same(400, raw("GET /v1/info HTTP/1.1\r\n" + repeat("X-A: 1\r\n", 80) + "\r\n").status, "too many headers");
    same(400, raw("POST /v1/pair/finish HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n").status, "chunked body");
    same(400, raw("GET /v1/info HTTP/1.1\r\nOrigin: http://evil.test\r\n\r\n").status, "browser origin");
    same(400, raw("POST /v1/pair/finish HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\n{}").status, "repeated length");
    same(400, raw("POST /v1/pair/finish HTTP/1.1\r\nContent-Length: -1\r\n\r\n").status, "negative length");
    same(400, raw("POST /v1/pair/finish HTTP/1.1\r\nContent-Length: two\r\n\r\n").status, "worded length");
    Fakes.Reply bare = raw("GET /v1/info HTTP/1.0\nhost: x\n\n");
    same(200, bare.status, "bare newlines and HTTP/1.0 are tolerated");
    same("close", bare.headers.get("connection"), "connection closes");
    same("no-store", bare.headers.get("cache-control"), "responses are not cached");
    check(bare.headers.get("content-type").startsWith("application/json"), "json content type");
    try {
      raw("GET /v1/info HTTP/1.1\r\nHost: x\r\n");
      throw new AssertionError("truncated head answered");
    } catch (EOFException expected) {
      checks++;
    }
    try {
      raw("POST /v1/pair/finish HTTP/1.1\r\nContent-Length: 50\r\n\r\n{\"code\"");
      throw new AssertionError("truncated body answered");
    } catch (EOFException expected) {
      checks++;
    }

    Fakes.Reply info = send("GET", "/v1/info", null, null);
    same(1L, info.object().get("v"), "info version");
    same(api.frameId(), info.object().get("frameId"), "info frame id");
    same("Skylit", info.object().get("name"), "info name");

    Fakes.Reply oversize = raw("POST /v1/people HTTP/1.1\r\nAuthorization: Bearer " + token + "\r\nContent-Length: 65537\r\n\r\n");
    same(413, oversize.status, "json limit applies before the body is read");
    same("too_large", oversize.error(), "413 code");
    same(200, call("POST", "/v1/shopping", "{\"name\":\"Milk\",\"note\":\"" + repeat("a", 150) + "\"" + repeat(" ", 60000) + "}").status,
        "a body just under the limit is read");
    same(413, raw("POST /v1/photos HTTP/1.1\r\nAuthorization: Bearer " + token
        + "\r\nContent-Type: image/jpeg\r\nContent-Length: 15728641\r\n\r\n").status, "photo limit applies before the body is read");
    same(401, raw("POST /v1/photos HTTP/1.1\r\nContent-Type: image/jpeg\r\nContent-Length: 15728641\r\n\r\n").status,
        "auth is checked before any upload is read");
    Fakes.Reply continued = raw("POST /v1/people HTTP/1.1\r\nAuthorization: Bearer " + token
        + "\r\nExpect: 100-continue\r\nContent-Length: 33\r\n\r\n{\"name\":\"Maya\",\"color\":\"#00A36C\"}");
    same(100, continued.status, "expect continue is honoured");

    same(404, call("GET", "/v1/nothing", null).status, "unknown route");
    same("not_found", call("GET", "/v2/state", null).error(), "unknown version");
    same(404, call("GET", "/", null).status, "root");
    same(404, call("GET", "/v1/people", null).status, "wrong method on people");
    same(404, call("DELETE", "/v1/state", null).status, "wrong method on state");
    same(404, call("POST", "/v1/info", null).status, "wrong method on info");
    same(404, call("PUT", "/v1/chores/c1/undone", "{}").status, "unknown chore action");
    same(404, call("PUT", "/v1/people/p1/done", "{}").status, "action on the wrong resource");
    same(404, call("GET", "/v1/people/p1/extra/deep", null).status, "too many segments");
    same(401, send("GET", "/v1/nothing", null, null).status, "unknown routes still need a token");
    same(400, call("POST", "/v1/people", "{\"name\":").status, "malformed json");
    same(400, call("POST", "/v1/people", "[1]").status, "json array body");
    same(400, call("POST", "/v1/people", null).status, "missing body");
    Fakes.Reply problem = call("POST", "/v1/people", "nonsense");
    same("bad_request", problem.error(), "error code");
    check(Json.map(problem.object().get("error")).get("message") instanceof String, "error message");

    check(LocalServer.local(InetAddress.getByName("192.168.1.20")), "home network peers are served");
    check(LocalServer.local(InetAddress.getByName("10.0.0.7")), "private peers are served");
    check(LocalServer.local(InetAddress.getByName("127.0.0.1")), "loopback is served");
    check(LocalServer.local(InetAddress.getByName("fd12:3456::1")), "unique local IPv6 is served");
    check(LocalServer.local(InetAddress.getByName("fe80::1")), "link local IPv6 is served");
    check(!LocalServer.local(InetAddress.getByName("8.8.8.8")), "internet peers are refused");
    check(!LocalServer.local(InetAddress.getByName("2001:4860:4860::8888")), "internet IPv6 peers are refused");
  }

  static Fakes.Reply finish(String code) throws Exception {
    return send("POST", "/v1/pair/finish", null, "{\"code\":\"" + code + "\",\"deviceName\":\"Phone\"}");
  }

  static String wrongCode() {
    return events.code.equals("000000") ? "000001" : "000000";
  }

  static void pairing() throws Exception {
    fresh();
    check(token.matches("[0-9a-f]{64}"), "token is 32 random bytes in hex");
    check(!storage.values.toString().contains(token), "the token itself is never stored");
    check(storage.values.get("devices").contains(Digests.sha256(token.getBytes(StandardCharsets.US_ASCII))), "its SHA-256 is stored");
    same(1, events.count("shown"), "code shown once");
    same(1, events.count("hidden"), "code hidden after use");
    List<Object> devices = call("GET", "/v1/devices", null).list();
    same(1, devices.size(), "one device");
    Map<String, Object> device = Json.map(devices.get(0));
    same("Test phone", device.get("name"), "device name");
    same("2026-10-11T00:00:00Z", device.get("pairedAt"), "pairedAt is ISO-8601");
    check(!device.containsKey("hash") && device.keySet().size() == 3, "device rows expose only id, name, pairedAt");

    same(409, finish("123456").status, "no active code");
    same(400, send("POST", "/v1/pair/finish", null, "{\"code\":123456,\"deviceName\":\"Phone\"}").status, "numeric code");
    same(400, send("POST", "/v1/pair/finish", null, "{\"code\":\"12345\",\"deviceName\":\"Phone\"}").status, "short code");

    send("POST", "/v1/pair/start", null, null);
    String used = events.code;
    check(used.matches("[0-9]{6}"), "six digit code");
    same(START + 120000L, events.expiresAt, "code lasts 120 seconds");
    same(400, send("POST", "/v1/pair/finish", null, "{\"code\":\"" + used + "\"}").status, "device name is required");
    same(400, send("POST", "/v1/pair/finish", null, "{\"code\":\"" + used + "\",\"deviceName\":\"  \"}").status, "blank device name");
    same(200, finish(used).status, "a rejected body does not consume the code");
    same(409, finish(used).status, "a code cannot be reused");

    send("POST", "/v1/pair/start", null, null);
    String expiring = events.code;
    clock.now += 119999L;
    same(401, finish(wrongCode()).status, "wrong code just before expiry");
    clock.now += 1L;
    Fakes.Reply expired = finish(expiring);
    same(409, expired.status, "expired code");
    same("conflict", expired.error(), "expired code slug");
    check(events.code == null, "expired code is hidden");

    send("POST", "/v1/pair/start", null, null);
    String replaced = events.code;
    send("POST", "/v1/pair/start", null, null);
    String replacement = events.code;
    if (!replaced.equals(replacement)) same(401, finish(replaced).status, "a replaced code stops working");
    same(200, finish(replacement).status, "the replacement works");

    clock.now += 700000L;
    send("POST", "/v1/pair/start", null, null);
    String guarded = events.code;
    for (int attempt = 1; attempt <= 4; attempt++) {
      Fakes.Reply wrong = finish(wrongCode());
      same(401, wrong.status, "wrong attempt " + attempt);
      same("unauthorized", wrong.error(), "wrong attempt slug");
    }
    Fakes.Reply fifth = finish(wrongCode());
    same(429, fifth.status, "the fifth wrong attempt is rate limited");
    same("rate_limited", fifth.error(), "429 slug");
    check(events.code == null, "an exhausted code is hidden");
    same(429, finish(guarded).status, "the right code no longer works after five wrong attempts");
    same(429, send("POST", "/v1/pair/start", null, null).status, "pairing is locked out after an exhausted code");
    clock.now += Pairing.FIRST_LOCKOUT - 1;
    same(429, send("POST", "/v1/pair/start", null, null).status, "still locked just before the lockout ends");
    clock.now += 1;
    same(204, send("POST", "/v1/pair/start", null, null).status, "pairing resumes after the lockout");
    same(200, finish(events.code).status, "a fresh code pairs");

    clock.now += 700000L;
    for (int started = 1; started <= Pairing.MAX_STARTS; started++) {
      same(204, send("POST", "/v1/pair/start", null, null).status, "start " + started);
    }
    same(429, send("POST", "/v1/pair/start", null, null).status, "too many starts in ten minutes");
    clock.now += Pairing.START_WINDOW;
    same(204, send("POST", "/v1/pair/start", null, null).status, "starts are allowed again later");

    storage = new Fakes.Storage();
    events = new Fakes.Recorder();
    api = new LocalApi(storage, clock, calendars, photos, sync(events), events);
    for (int paired = 0; paired < Pairing.MAX_DEVICES; paired++) {
      clock.now += 700000L;
      pair("Phone " + paired);
    }
    clock.now += 700000L;
    send("POST", "/v1/pair/start", null, null);
    same(409, finish(events.code).status, "device limit");
  }

  static void tokens() throws Exception {
    fresh();
    same(401, send("GET", "/v1/state", null, null).status, "missing token");
    same("unauthorized", send("GET", "/v1/state", null, null).error(), "401 slug");
    same(401, send("GET", "/v1/state", repeat("0", 64), null).status, "unknown token");
    same(401, send("GET", "/v1/state", token.substring(0, 63), null).status, "short token");
    same(401, send("GET", "/v1/state", token.toUpperCase(), null).status, "tokens are case sensitive");
    same(401, raw("GET /v1/state HTTP/1.1\r\nAuthorization: Basic " + token + "\r\n\r\n").status, "wrong scheme");
    same(401, raw("GET /v1/state HTTP/1.1\r\nAuthorization: " + token + "\r\n\r\n").status, "missing scheme");
    same(200, raw("GET /v1/state HTTP/1.1\r\nauthorization: Bearer " + token + "\r\n\r\n").status, "header names ignore case");
    for (String target : new String[] {"/v1/devices", "/v1/photos", "/v1/photos/" + repeat("a", 64)}) {
      same(401, send("GET", target, null, null).status, "token needed for " + target);
    }
    same(401, send("POST", "/v1/people", null, "{\"name\":\"Maya\",\"color\":\"#00A36C\"}").status, "mutations need a token");

    clock.now += 700000L;
    String second = pair("Second phone");
    List<Object> devices = call("GET", "/v1/devices", null).list();
    same(2, devices.size(), "two devices");
    String secondId = null;
    for (Object device : devices) if (Json.map(device).get("name").equals("Second phone")) secondId = (String) Json.map(device).get("id");
    same(404, call("DELETE", "/v1/devices/unknown", null).status, "unknown device");
    same(204, call("DELETE", "/v1/devices/" + secondId, null).status, "revoke over HTTP");
    same(401, send("GET", "/v1/state", second, null).status, "revoked token stops working");
    same(200, call("GET", "/v1/state", null).status, "other tokens keep working");
    same(404, call("DELETE", "/v1/devices/" + secondId, null).status, "revoking twice");

    Map<String, Object> status = Json.map(Json.parse(api.pairingStatus(8765, true)));
    same(8765L, status.get("port"), "status port");
    same(Boolean.TRUE, status.get("advertised"), "status advertised");
    same(1, Json.list(status.get("devices")).size(), "status devices");
    check(!api.pairingRevoke("unknown"), "bridge revoke of an unknown device");
    clock.now += 700000L;
    String third = pair("Third phone");
    String thirdId = null;
    for (Object device : call("GET", "/v1/devices", null).list()) {
      if (Json.map(device).get("name").equals("Third phone")) thirdId = (String) Json.map(device).get("id");
    }
    check(api.pairingRevoke(thirdId), "bridge revoke");
    same(401, send("GET", "/v1/state", third, null).status, "bridge revoked token stops working");
    check(api.pairingRevokeAll(), "bridge revoke all");
    same(401, call("GET", "/v1/state", null).status, "revoke all removes every token");
    same("[]", Json.write(Json.map(Json.parse(api.pairingStatus(0, false))).get("devices")), "no devices remain");
  }

  static void household() throws Exception {
    fresh();
    Map<String, Object> empty = state();
    same(0L, empty.get("rev"), "initial rev");
    same("[]", Json.write(empty.get("people")) , "no people");
    same("{\"location\":null,\"appearance\":{\"palette\":\"linen\",\"mode\":\"auto\"},\"icloudAlbum\":null}", Json.write(empty.get("settings")), "default settings");
    same("[]", Json.write(empty.get("calendars")), "no calendars");
    same("{\"count\":0}", Json.write(empty.get("photos")), "no photos");

    Fakes.Reply created = call("POST", "/v1/people", "{\"name\":\"  Maya \",\"color\":\"#00A36C\",\"id\":\"mine\"}");
    Map<String, Object> maya = row(created, "person");
    same(1L, created.object().get("rev"), "rev after first change");
    same("Maya", maya.get("name"), "names are trimmed");
    same("#00A36C", maya.get("color"), "colour kept");
    String mayaId = (String) maya.get("id");
    check(!mayaId.equals("mine"), "ids are assigned by the frame");
    same(1, events.count("household"), "dashboard told about the change");
    same(1L, Json.map(Json.parse(events.snapshot)).get("rev"), "dashboard snapshot carries the rev");
    check(!Json.map(Json.parse(events.snapshot)).containsKey("settings"), "dashboard snapshot is only the household");

    String[] badPeople = {"{\"name\":\"\",\"color\":\"#00A36C\"}", "{\"name\":\"   \",\"color\":\"#00A36C\"}",
        "{\"name\":\"" + repeat("a", 81) + "\",\"color\":\"#00A36C\"}", "{\"name\":7,\"color\":\"#00A36C\"}",
        "{\"name\":\"A\"}", "{\"color\":\"#00A36C\"}", "{\"name\":\"A\",\"color\":\"00A36C\"}",
        "{\"name\":\"A\",\"color\":\"#00A36\"}", "{\"name\":\"A\",\"color\":\"#GGGGGG\"}", "{\"name\":\"A\",\"color\":\"red\"}",
        "{\"name\":\"A\\u0007B\",\"color\":\"#00A36C\"}"};
    for (String body : badPeople) same(400, call("POST", "/v1/people", body).status, "rejected person " + body);
    same(200, call("POST", "/v1/people", "{\"name\":\"" + repeat("a", 80) + "\",\"color\":\"#abcdef\"}").status, "80 characters fit");
    same(200, call("POST", "/v1/people", "{\"name\":\"" + repeat("\ud83d\ude00", 80) + "\",\"color\":\"#abcdef\"}").status, "80 emoji fit");
    same(3L, rev(), "rejected requests do not change the rev");

    Map<String, Object> renamed = row(call("PATCH", "/v1/people/" + mayaId, "{\"name\":\"Maya B\"}"), "person");
    same("Maya B", renamed.get("name"), "patch name");
    same("#00A36C", renamed.get("color"), "patch keeps other fields");
    same(4L, rev(), "patch bumps rev once");
    same(4L, call("PATCH", "/v1/people/" + mayaId, "{\"name\":\"Maya B\"}").object().get("rev"), "an unchanged patch keeps the rev");
    same(4L, call("PATCH", "/v1/people/" + mayaId, "{}").object().get("rev"), "an empty patch keeps the rev");
    same(400, call("PATCH", "/v1/people/" + mayaId, "{\"name\":\"OK\",\"color\":\"bad\"}").status, "patch validates every field");
    same("Maya B", Json.map(Json.list(state().get("people")).get(0)).get("name"), "a rejected patch changes nothing");
    same(404, call("PATCH", "/v1/people/p999", "{\"name\":\"X\"}").status, "patch unknown person");
    same(404, call("DELETE", "/v1/people/p999", null).status, "delete unknown person");

    Fakes.Reply choreReply = call("POST", "/v1/chores", "{\"title\":\"Make bed\",\"emoji\":\"\ud83d\udecf\ufe0f\",\"personId\":\"" + mayaId + "\",\"days\":[5,1,3,1,2.0]}");
    Map<String, Object> chore = row(choreReply, "chore");
    String choreId = (String) chore.get("id");
    same("[1,2,3,5]", Json.write(chore.get("days")), "days are sorted and unique");
    same(mayaId, chore.get("personId"), "chore person");
    same("\ud83d\udecf\ufe0f", chore.get("emoji"), "chore emoji");
    same("[]", Json.write(chore.get("done")), "chore starts not done");
    Map<String, Object> plain = row(call("POST", "/v1/chores", "{\"title\":\"Water plants\"}"), "chore");
    same("{\"id\":\"" + plain.get("id") + "\",\"title\":\"Water plants\",\"emoji\":\"\",\"personId\":null,\"days\":[],\"done\":[]}",
        Json.write(plain), "chore defaults");
    String[] badChores = {"{}", "{\"title\":\"\"}", "{\"title\":\"" + repeat("b", 81) + "\"}", "{\"title\":\"A\",\"days\":[7]}",
        "{\"title\":\"A\",\"days\":[-1]}", "{\"title\":\"A\",\"days\":[1.5]}", "{\"title\":\"A\",\"days\":\"1\"}",
        "{\"title\":\"A\",\"days\":[\"1\"]}", "{\"title\":\"A\",\"personId\":\"p999\"}", "{\"title\":\"A\",\"personId\":5}",
        "{\"title\":\"A\",\"emoji\":5}", "{\"title\":\"A\",\"emoji\":\"" + repeat("e", 17) + "\"}"};
    for (String body : badChores) same(400, call("POST", "/v1/chores", body).status, "rejected chore " + body);
    Map<String, Object> edited = row(call("PATCH", "/v1/chores/" + choreId, "{\"title\":\"Make the bed\",\"days\":[],\"personId\":null,\"emoji\":\"\"}"), "chore");
    same("Make the bed", edited.get("title"), "chore title patch");
    same("[]", Json.write(edited.get("days")), "chore days patch");
    check(edited.get("personId") == null, "chore can be unassigned");
    same(200, call("PATCH", "/v1/chores/" + choreId, "{\"personId\":\"" + mayaId + "\"}").status, "chore reassigned");
    same(400, call("PATCH", "/v1/chores/" + choreId, "{\"days\":[9]}").status, "chore patch validates");
    same(404, call("PATCH", "/v1/chores/c999", "{\"title\":\"X\"}").status, "patch unknown chore");

    long beforeDone = rev();
    Map<String, Object> ticked = row(call("PUT", "/v1/chores/" + choreId + "/done", "{\"date\":\"2026-10-11\",\"done\":true}"), "chore");
    same("[\"2026-10-11\"]", Json.write(ticked.get("done")), "chore marked done");
    same(beforeDone + 1, rev(), "done bumps rev");
    call("PUT", "/v1/chores/" + choreId + "/done", "{\"date\":\"2026-10-11\",\"done\":true}");
    same(beforeDone + 1, rev(), "marking done twice changes nothing");
    call("PUT", "/v1/chores/" + choreId + "/done", "{\"date\":\"2026-10-09\",\"done\":true}");
    same("[\"2026-10-09\",\"2026-10-11\"]", Json.write(Json.map(Json.list(state().get("chores")).get(0)).get("done")), "done dates stay sorted");
    Map<String, Object> unticked = row(call("PUT", "/v1/chores/" + choreId + "/done", "{\"date\":\"2026-10-09\",\"done\":false}"), "chore");
    same("[\"2026-10-11\"]", Json.write(unticked.get("done")), "chore unmarked");
    String[] badDone = {"{\"date\":\"2026-10-11\"}", "{\"done\":true}", "{\"date\":\"2026-02-30\",\"done\":true}",
        "{\"date\":\"11-10-2026\",\"done\":true}", "{\"date\":20261011,\"done\":true}", "{\"date\":\"2026-10-11\",\"done\":\"yes\"}",
        "{\"date\":\"2026-09-27\",\"done\":true}", "{\"date\":\"2026-10-13\",\"done\":true}"};
    for (String body : badDone) same(400, call("PUT", "/v1/chores/" + choreId + "/done", body).status, "rejected done " + body);
    same(200, call("PUT", "/v1/chores/" + choreId + "/done", "{\"date\":\"2026-09-28\",\"done\":true}").status, "oldest kept day is accepted");
    same(200, call("PUT", "/v1/chores/" + choreId + "/done", "{\"date\":\"2026-10-12\",\"done\":true}").status, "tomorrow is accepted");
    same(404, call("PUT", "/v1/chores/c999/done", "{\"date\":\"2026-10-11\",\"done\":true}").status, "done on unknown chore");

    long beforePrune = rev();
    clock.now += DAY;
    same("[\"2026-10-11\",\"2026-10-12\"]", Json.write(Json.map(Json.list(state().get("chores")).get(0)).get("done")), "day 15 is pruned");
    clock.now += 12 * DAY;
    same("[\"2026-10-11\",\"2026-10-12\"]", Json.write(Json.map(Json.list(state().get("chores")).get(0)).get("done")), "13 days later still kept");
    clock.now += DAY;
    same("[\"2026-10-12\"]", Json.write(Json.map(Json.list(state().get("chores")).get(0)).get("done")), "14 days later pruned");
    clock.now += DAY;
    same("[]", Json.write(Json.map(Json.list(Json.map(Json.parse(api.householdSnapshot())).get("chores")).get(0)).get("done")), "bridge snapshot prunes too");
    same(beforePrune, rev(), "pruning is not a revision");
    check(!storage.values.get("household").contains("2026-10-1"), "pruned dates leave storage");

    same(200, call("DELETE", "/v1/people/" + mayaId, null).status, "delete person");
    Map<String, Object> afterRemoval = state();
    check(Json.map(Json.list(afterRemoval.get("chores")).get(0)).get("personId") == null, "removing a person unassigns their chores");
    same(2, Json.list(afterRemoval.get("people")).size(), "person removed");
    same(2, Json.list(afterRemoval.get("chores")).size(), "chores survive person removal");
    same(beforePrune + 1, afterRemoval.get("rev"), "person removal is one revision");
    same("{\"rev\":" + (beforePrune + 2) + "}", call("DELETE", "/v1/chores/" + choreId, null).text(), "delete chore returns only the rev");
    same(404, call("DELETE", "/v1/chores/" + choreId, null).status, "delete chore twice");

    Map<String, Object> milk = row(call("POST", "/v1/shopping", "{\"name\":\"Milk\",\"qty\":2,\"note\":\"whole\",\"done\":true}"), "item");
    String milkId = (String) milk.get("id");
    same("{\"id\":\"" + milkId + "\",\"name\":\"Milk\",\"qty\":2,\"note\":\"whole\",\"done\":false}", Json.write(milk), "item created");
    Map<String, Object> bread = row(call("POST", "/v1/shopping", "{\"name\":\"Bread\"}"), "item");
    same(1L, bread.get("qty"), "qty defaults to one");
    same("", bread.get("note"), "note defaults to empty");
    String[] badItems = {"{}", "{\"name\":\"\"}", "{\"name\":\"" + repeat("c", 81) + "\"}", "{\"name\":\"A\",\"qty\":0}",
        "{\"name\":\"A\",\"qty\":100}", "{\"name\":\"A\",\"qty\":1.5}", "{\"name\":\"A\",\"qty\":\"2\"}", "{\"name\":\"A\",\"qty\":null}",
        "{\"name\":\"A\",\"note\":5}", "{\"name\":\"A\",\"note\":\"" + repeat("n", 201) + "\"}"};
    for (String body : badItems) same(400, call("POST", "/v1/shopping", body).status, "rejected item " + body);
    same(200, call("POST", "/v1/shopping", "{\"name\":\"Eggs\",\"qty\":99}").status, "qty 99 fits");
    Map<String, Object> bought = row(call("PATCH", "/v1/shopping/" + milkId, "{\"done\":true,\"qty\":3,\"note\":\"\",\"name\":\"Oat milk\"}"), "item");
    same("{\"id\":\"" + milkId + "\",\"name\":\"Oat milk\",\"qty\":3,\"note\":\"\",\"done\":true}", Json.write(bought), "item patched");
    same(400, call("PATCH", "/v1/shopping/" + milkId, "{\"done\":\"yes\"}").status, "item patch validates");
    same(404, call("PATCH", "/v1/shopping/s999", "{\"done\":true}").status, "patch unknown item");
    long beforeClear = rev();
    same("{\"rev\":" + (beforeClear + 1) + "}", call("POST", "/v1/shopping/clear-done", null).text(), "clear done");
    same(2, Json.list(state().get("shopping")).size(), "ticked items removed");
    same(beforeClear + 1, call("POST", "/v1/shopping/clear-done", null).object().get("rev"), "clearing nothing keeps the rev");
    same(200, call("DELETE", "/v1/shopping/" + bread.get("id"), null).status, "delete item");
    same(404, call("DELETE", "/v1/shopping/" + bread.get("id"), null).status, "delete item twice");

    long current = rev();
    same(304, call("GET", "/v1/state?since=" + current, null).status, "unchanged state is 304");
    same(0, call("GET", "/v1/state?since=" + current, null).body.length, "304 has no body");
    same(200, call("GET", "/v1/state?since=" + (current - 1), null).status, "older rev gets the state");
    same(200, call("GET", "/v1/state?since=" + (current + 5), null).status, "a rev from another life gets the state");
    same(400, call("GET", "/v1/state?since=abc", null).status, "since must be a number");
    same(400, call("GET", "/v1/state?since=", null).status, "since must not be empty");
  }

  static void limits() throws Exception {
    fresh();
    for (int i = 0; i < HouseholdStore.MAX_PEOPLE; i++) same(200, call("POST", "/v1/people", "{\"name\":\"P" + i + "\",\"color\":\"#112233\"}").status, "person " + i);
    Fakes.Reply full = call("POST", "/v1/people", "{\"name\":\"Extra\",\"color\":\"#112233\"}");
    same(400, full.status, "13th person");
    same("bad_request", full.error(), "limit slug");
    for (int i = 0; i < HouseholdStore.MAX_CHORES; i++) same(200, call("POST", "/v1/chores", "{\"title\":\"C" + i + "\"}").status, "chore " + i);
    same(400, call("POST", "/v1/chores", "{\"title\":\"Extra\"}").status, "101st chore");
    for (int i = 0; i < HouseholdStore.MAX_ITEMS; i++) same(200, call("POST", "/v1/shopping", "{\"name\":\"S" + i + "\"}").status, "item " + i);
    same(400, call("POST", "/v1/shopping", "{\"name\":\"Extra\"}").status, "201st item");
    same((long) (12 + 100 + 200), rev(), "every accepted change is exactly one revision");
    same(200, call("DELETE", "/v1/people/p1", null).status, "delete frees a slot");
    same(200, call("POST", "/v1/people", "{\"name\":\"Again\",\"color\":\"#112233\"}").status, "slot can be reused");
    check(storage.values.get("household").length() < 64 * 1024, "a full household stays small");
  }

  static Map<String, Object> mutate(String json) throws Exception {
    return Json.map(Json.parse(api.householdMutate(json)));
  }

  static void bridge() throws Exception {
    fresh();
    same("{\"rev\":0,\"people\":[],\"chores\":[],\"shopping\":[]}", api.householdSnapshot(), "empty bridge snapshot");
    Map<String, Object> added = mutate("{\"op\":\"person.add\",\"name\":\"Maya\",\"color\":\"#00A36C\"}");
    same(Boolean.TRUE, added.get("ok"), "person.add");
    String person = (String) Json.map(Json.list(Json.map(added.get("snapshot")).get("people")).get(0)).get("id");
    same(Boolean.TRUE, mutate("{\"op\":\"person.update\",\"id\":\"" + person + "\",\"color\":\"#123456\"}").get("ok"), "person.update");
    Map<String, Object> withChore = mutate("{\"op\":\"chore.add\",\"title\":\"Dishes\",\"personId\":\"" + person + "\"}");
    String chore = (String) Json.map(Json.list(Json.map(withChore.get("snapshot")).get("chores")).get(0)).get("id");
    same(Boolean.TRUE, mutate("{\"op\":\"chore.update\",\"id\":\"" + chore + "\",\"days\":[0,6]}").get("ok"), "chore.update");
    Map<String, Object> done = mutate("{\"op\":\"chore.done\",\"id\":\"" + chore + "\",\"date\":\"2026-10-11\",\"done\":true}");
    same("[\"2026-10-11\"]", Json.write(Json.map(Json.list(Json.map(done.get("snapshot")).get("chores")).get(0)).get("done")), "chore.done");
    Map<String, Object> withItem = mutate("{\"op\":\"item.add\",\"name\":\"Milk\",\"qty\":2}");
    String item = (String) Json.map(Json.list(Json.map(withItem.get("snapshot")).get("shopping")).get(0)).get("id");
    same(Boolean.TRUE, mutate("{\"op\":\"item.update\",\"id\":\"" + item + "\",\"done\":true}").get("ok"), "item.update");
    mutate("{\"op\":\"item.add\",\"name\":\"Bread\"}");
    Map<String, Object> cleared = mutate("{\"op\":\"items.clearDone\"}");
    same(1, Json.list(Json.map(cleared.get("snapshot")).get("shopping")).size(), "items.clearDone");
    String bread = (String) Json.map(Json.list(Json.map(cleared.get("snapshot")).get("shopping")).get(0)).get("id");
    same(Boolean.TRUE, mutate("{\"op\":\"item.remove\",\"id\":\"" + bread + "\"}").get("ok"), "item.remove");
    Map<String, Object> removed = mutate("{\"op\":\"person.remove\",\"id\":\"" + person + "\"}");
    check(Json.map(Json.list(Json.map(removed.get("snapshot")).get("chores")).get(0)).get("personId") == null, "person.remove unassigns");
    Map<String, Object> last = mutate("{\"op\":\"chore.remove\",\"id\":\"" + chore + "\"}");
    same(12L, Json.map(last.get("snapshot")).get("rev"), "twelve bridge changes are twelve revisions");
    same(12L, rev(), "the phone sees dashboard changes");
    same(12, events.count("household"), "every change is announced");

    String[] rejected = {"{\"op\":\"person.add\",\"name\":\"\",\"color\":\"#00A36C\"}", "{\"op\":\"nothing\"}", "{}", "[]", "not json", "",
        "{\"op\":\"item.remove\",\"id\":\"s999\"}", "{\"op\":\"chore.done\",\"id\":\"c1\"}"};
    for (String json : rejected) {
      Map<String, Object> result = mutate(json);
      same(Boolean.FALSE, result.get("ok"), "rejected " + json);
      check(result.get("error") instanceof String && !result.containsKey("snapshot"), "error text for " + json);
    }
    same(12L, rev(), "rejected bridge calls change nothing");
  }

  static void settings() throws Exception {
    fresh();
    Fakes.Reply located = call("PUT", "/v1/settings/location", "{\"name\":\"Calgary\",\"latitude\":51.05,\"longitude\":-114.07,\"timezone\":\"America/Edmonton\"}");
    same("{\"rev\":1}", located.text(), "location saved");
    same("{\"location\":{\"name\":\"Calgary\",\"latitude\":51.05,\"longitude\":-114.07,\"timezone\":\"America/Edmonton\"}}", events.settings, "dashboard asked to apply the location");
    same("{\"name\":\"Calgary\",\"latitude\":51.05,\"longitude\":-114.07,\"timezone\":\"America/Edmonton\"}",
        Json.write(Json.map(state().get("settings")).get("location")), "state serves the location");
    same(200, call("PUT", "/v1/settings/location", "{\"name\":\"Tokyo\",\"latitude\":35,\"longitude\":139}").status, "timezone is optional");
    check(Json.map(Json.map(state().get("settings")).get("location")).get("timezone") == null, "missing timezone is null");
    String[] badLocations = {"{}", "{\"name\":\"\",\"latitude\":1,\"longitude\":1}", "{\"name\":\"A\",\"latitude\":91,\"longitude\":1}",
        "{\"name\":\"A\",\"latitude\":1,\"longitude\":-181}", "{\"name\":\"A\",\"latitude\":\"1\",\"longitude\":1}",
        "{\"name\":\"A\",\"latitude\":1}", "{\"name\":\"A\",\"latitude\":1,\"longitude\":1,\"timezone\":\"bad zone!\"}",
        "{\"name\":\"A\",\"latitude\":1,\"longitude\":1,\"timezone\":5}"};
    for (String body : badLocations) same(400, call("PUT", "/v1/settings/location", body).status, "rejected location " + body);

    same("{\"rev\":3}", call("PUT", "/v1/settings/appearance", "{\"palette\":\"ocean\",\"mode\":\"dark\"}").text(), "appearance saved");
    same("{\"appearance\":{\"palette\":\"ocean\",\"mode\":\"dark\"}}", events.settings, "dashboard asked to apply the appearance");
    for (String palette : new String[] {"linen", "sage", "stone", "ocean", "plum", "contrast"}) {
      same(200, call("PUT", "/v1/settings/appearance", "{\"palette\":\"" + palette + "\",\"mode\":\"auto\"}").status, "palette " + palette);
    }
    String[] badAppearances = {"{}", "{\"palette\":\"cocoa\",\"mode\":\"auto\"}", "{\"palette\":\"linen\",\"mode\":\"dim\"}",
        "{\"palette\":\"linen\"}", "{\"palette\":5,\"mode\":\"auto\"}"};
    for (String body : badAppearances) same(400, call("PUT", "/v1/settings/appearance", body).status, "rejected appearance " + body);
    long before = rev();
    same(before, call("PUT", "/v1/settings/appearance", "{\"palette\":\"contrast\",\"mode\":\"auto\"}").object().get("rev"), "an unchanged setting keeps the rev");

    check(api.reportSettings("{\"location\":{\"name\":\"Tokyo\",\"latitude\":35.0,\"longitude\":139.0,\"timezone\":null},\"appearance\":{\"palette\":\"contrast\",\"mode\":\"auto\"}}"),
        "dashboard report accepted");
    same(before, rev(), "a matching report is not a change");
    check(api.reportSettings("{\"location\":null,\"appearance\":{\"palette\":\"plum\",\"mode\":\"light\"}}"), "dashboard report of a change");
    same(before + 1, rev(), "a changed report is one revision");
    same("{\"location\":null,\"appearance\":{\"palette\":\"plum\",\"mode\":\"light\"},\"icloudAlbum\":null}", Json.write(state().get("settings")), "state serves reported settings");
    check(api.reportSettings("{\"location\":{\"name\":\"Tokyo\",\"latitude\":35.6,\"longitude\":139.7,\"timezone\":\"Asia/Tokyo\",\"country\":\"JP\"}}"), "partial report with extra fields");
    same("{\"name\":\"Tokyo\",\"latitude\":35.6,\"longitude\":139.7,\"timezone\":\"Asia/Tokyo\"}", Json.write(Json.map(state().get("settings")).get("location")), "only contract fields are kept");
    same("plum", Json.map(Json.map(state().get("settings")).get("appearance")).get("palette"), "a partial report keeps the rest");
    for (String bad : new String[] {"", "nope", "[]", "{\"appearance\":{\"theme\":\"linen\"}}", "{\"location\":{\"name\":\"X\"}}", "{\"appearance\":null}"}) {
      check(!api.reportSettings(bad), "rejected report " + bad);
    }
    same(before + 2, rev(), "rejected reports change nothing");

    clock.now = START + 16 * 3600000L;
    String chore = (String) row(call("POST", "/v1/chores", "{\"title\":\"Tokyo chore\"}"), "chore").get("id");
    same(200, call("PUT", "/v1/chores/" + chore + "/done", "{\"date\":\"2026-10-13\",\"done\":true}").status, "dates follow the chosen city zone");
    same(400, call("PUT", "/v1/chores/" + chore + "/done", "{\"date\":\"2026-10-14\",\"done\":true}").status, "two days ahead in the city zone");
  }

  static void calendarsOverHttp() throws Exception {
    fresh();
    Fakes.Reply added = call("POST", "/v1/calendars", "{\"name\":\" Family \",\"color\":\"#2D5BFF\",\"url\":\"" + FEED + "\"}");
    Map<String, Object> calendar = row(added, "calendar");
    same("{\"id\":\"" + calendar.get("id") + "\",\"name\":\"Family\",\"color\":\"#2D5BFF\"}", Json.write(calendar), "calendar created without its url");
    same(1L, added.object().get("rev"), "calendar add is one revision");
    check(!added.text().contains("private-") && !added.text().contains("basic.ics"), "the feed url is never echoed");
    Fakes.Reply stateReply = call("GET", "/v1/state", null);
    same("[{\"id\":\"" + calendar.get("id") + "\",\"name\":\"Family\",\"color\":\"#2D5BFF\"}]", Json.write(stateReply.object().get("calendars")), "state lists calendars");
    check(!stateReply.text().contains("private-") && !stateReply.text().contains("url"), "state never carries feed urls");
    same(409, call("POST", "/v1/calendars", "{\"name\":\"Again\",\"color\":\"#2D5BFF\",\"url\":\"" + FEED + "\"}").status, "duplicate feed");
    String[] badUrls = {FEED.replace("https:", "http:"), FEED.replace("calendar.google.com", "calendar.google.com.evil.test"), FEED + "?x=1",
        "https://127.0.0.1/calendar/ical/test/public/basic.ics", "https://calendar.google.com/calendar/u/0/r", "file:///etc/passwd", ""};
    for (String url : badUrls) {
      same(400, call("POST", "/v1/calendars", "{\"name\":\"Bad\",\"color\":\"#2D5BFF\",\"url\":\"" + url + "\"}").status, "rejected feed " + url);
    }
    String[] badCalendars = {"{\"name\":\"\",\"color\":\"#2D5BFF\",\"url\":\"" + FEED + "x\"}", "{\"name\":\"A\",\"color\":\"blue\",\"url\":\"" + FEED + "\"}",
        "{\"name\":\"A\",\"color\":\"#2D5BFF\"}", "{\"name\":\"A\",\"color\":\"#2D5BFF\",\"url\":5}", "{\"name\":\"" + repeat("n", 81) + "\",\"color\":\"#2D5BFF\",\"url\":\"" + FEED + "\"}"};
    for (String body : badCalendars) same(400, call("POST", "/v1/calendars", body).status, "rejected calendar " + body);
    for (int i = 2; i <= 6; i++) {
      same(200, call("POST", "/v1/calendars", "{\"name\":\"C" + i + "\",\"color\":\"#2D5BFF\",\"url\":\"" + FEED.replace("private-test", "private-test" + i) + "\"}").status, "calendar " + i);
    }
    same(400, call("POST", "/v1/calendars", "{\"name\":\"C7\",\"color\":\"#2D5BFF\",\"url\":\"" + FEED.replace("private-test", "private-test7") + "\"}").status, "seventh calendar");
    same(6L, rev(), "six calendars are six revisions");
    same("{\"rev\":7}", call("DELETE", "/v1/calendars/" + calendar.get("id"), null).text(), "calendar removed");
    same(404, call("DELETE", "/v1/calendars/" + calendar.get("id"), null).status, "calendar removed twice");
    same(5, Json.list(state().get("calendars")).size(), "five calendars remain");
    calendars.add("On frame", "#112233", FEED);
    same(8L, rev(), "a calendar added on the frame is a revision for the phone");
    same(304, call("GET", "/v1/state?since=8", null).status, "and only one");
  }

  static Fakes.Reply upload(byte[] image, String type) throws Exception {
    return Fakes.inMemory(api, Fakes.request("POST", "/v1/photos", token, type, image));
  }

  static void photosOverHttp() throws Exception {
    fresh();
    byte[] first = Fakes.jpeg(1, 20000);
    byte[] second = Fakes.jpeg(2, 30000);
    Fakes.Reply stored = upload(first, "image/jpeg");
    Map<String, Object> photo = row(stored, "photo");
    String id = (String) photo.get("id");
    same(Digests.sha256(first), id, "photo id is the SHA-256 of the bytes");
    check(id.matches("[a-f0-9]{64}"), "photo id is 64 hex");
    same("2026-10-11T00:00:00Z", photo.get("addedAt"), "addedAt is ISO-8601");
    same(1L, stored.object().get("rev"), "upload is one revision");
    clock.now += 60000L;
    Fakes.Reply again = upload(first, "image/jpeg");
    same(200, again.status, "same bytes accepted");
    same(Json.write(photo), Json.write(again.object().get("photo")), "same bytes return the existing photo");
    same(1L, again.object().get("rev"), "a duplicate is not a revision");
    same("{\"count\":1}", Json.write(state().get("photos")), "duplicate is stored once");
    same(200, upload(second, "image/jpeg; charset=binary").status, "content type parameters are tolerated");
    List<Object> listed = call("GET", "/v1/photos", null).list();
    same(2, listed.size(), "two photos listed");
    same(Digests.sha256(second), Json.map(listed.get(0)).get("id"), "newest first");
    same("2026-10-11T00:01:00Z", Json.map(listed.get(0)).get("addedAt"), "second addedAt");
    check(Json.map(listed.get(0)).keySet().size() == 2, "photo rows expose only id and addedAt");

    Fakes.Reply fetched = call("GET", "/v1/photos/" + id, null);
    same(200, fetched.status, "photo fetched");
    same("image/jpeg", fetched.headers.get("content-type"), "photo content type");
    same(String.valueOf(first.length), fetched.headers.get("content-length"), "photo length");
    check(java.util.Arrays.equals(first, fetched.body), "photo bytes round trip");

    byte[] png = Fakes.jpeg(3, 5000);
    png[0] = (byte) 0x89;
    png[1] = 'P';
    same(400, upload(png, "image/jpeg").status, "non-JPEG bytes are rejected");
    same(400, upload(new byte[] {(byte) 0xFF, (byte) 0xD8}, "image/jpeg").status, "a truncated JPEG header is rejected");
    same(400, upload(new byte[0], "image/jpeg").status, "an empty body is rejected");
    same(400, upload(first, "image/png").status, "other content types are rejected");
    same(400, upload(first, null).status, "a content type is required");
    same(400, upload("{\"photo\":true}".getBytes(StandardCharsets.UTF_8), "application/json").status, "json is not a photo");
    same(413, upload(Fakes.jpeg(4, LocalApi.MAX_PHOTO + 1), "image/jpeg").status, "over 15 MiB is too large");
    same(200, upload(Fakes.jpeg(5, LocalApi.MAX_PHOTO), "image/jpeg").status, "exactly 15 MiB fits");
    photos.accepting = false;
    same(400, upload(Fakes.jpeg(6, 5000), "image/jpeg").status, "a picture the library refuses is a 400");
    photos.accepting = true;
    same(3L, rev(), "rejected uploads are not revisions");

    same(404, call("GET", "/v1/photos/" + repeat("0", 64), null).status, "unknown photo");
    same(404, call("GET", "/v1/photos/short", null).status, "malformed photo id");
    same(404, call("GET", "/v1/photos/" + id.toUpperCase(), null).status, "ids are lowercase only");
    same(400, raw("GET /v1/photos/..%2f" + id + " HTTP/1.1\r\nAuthorization: Bearer " + token + "\r\n\r\n").status, "photo traversal");
    same(400, raw("GET /v1/photos/" + id + ".jpg HTTP/1.1\r\nAuthorization: Bearer " + token + "\r\n\r\n").status, "photo ids have no extension");
    Fakes.Reply deleted = call("DELETE", "/v1/photos/" + id, null);
    same(204, deleted.status, "photo deleted");
    same(0, deleted.body.length, "204 has no body");
    same(404, call("GET", "/v1/photos/" + id, null).status, "deleted photo is gone");
    same(404, call("DELETE", "/v1/photos/" + id, null).status, "delete twice");
    same(404, call("DELETE", "/v1/photos/nope", null).status, "delete malformed id");
    same(4L, rev(), "delete is one revision");
    same("{\"count\":2}", Json.write(state().get("photos")), "count after delete");
    same(200, upload(first, "image/jpeg").status, "a deleted photo can be sent again");
    photos.add(Fakes.jpeg(7, 5000), clock.now);
    same(6L, rev(), "a picture arriving by email is a revision for the phone");
  }

  static void persistence() throws Exception {
    fresh();
    call("POST", "/v1/people", "{\"name\":\"Maya\",\"color\":\"#00A36C\"}");
    call("POST", "/v1/chores", "{\"title\":\"Make bed\",\"emoji\":\"\ud83d\udecf\ufe0f\",\"personId\":\"p1\",\"days\":[1,2]}");
    call("PUT", "/v1/chores/c2/done", "{\"date\":\"2026-10-11\",\"done\":true}");
    call("POST", "/v1/shopping", "{\"name\":\"Milk \\\"2%\\\"\",\"qty\":2,\"note\":\"caf\u00e9\"}");
    call("PUT", "/v1/settings/location", "{\"name\":\"Calgary\",\"latitude\":51.05,\"longitude\":-114.07,\"timezone\":\"America/Edmonton\"}");
    call("PUT", "/v1/settings/appearance", "{\"palette\":\"sage\",\"mode\":\"dark\"}");
    String before = call("GET", "/v1/state", null).text();
    String frameId = api.frameId();
    String devices = call("GET", "/v1/devices", null).text();

    api = new LocalApi(storage, clock, calendars, photos, sync(events), new Fakes.Recorder());
    same(before, call("GET", "/v1/state", null).text(), "state survives a restart byte for byte");
    same(frameId, api.frameId(), "frame id survives a restart");
    same(devices, call("GET", "/v1/devices", null).text(), "paired devices survive a restart");
    Map<String, Object> next = row(call("POST", "/v1/people", "{\"name\":\"Noor\",\"color\":\"#123456\"}"), "person");
    same("p4", next.get("id"), "ids are never reused after a restart");
    same(7L, rev(), "rev continues after a restart");

    storage.values.put("household", "{broken");
    storage.values.put("devices", "{\"not\":\"a list\"}");
    storage.values.put("settings", "[]");
    storage.values.put("frameId", "../../etc");
    api = new LocalApi(storage, clock, calendars, photos, sync(events), new Fakes.Recorder());
    same(401, call("GET", "/v1/state", null).status, "unreadable device storage pairs nobody");
    token = null;
    events = new Fakes.Recorder();
    api = new LocalApi(storage, clock, calendars, photos, sync(events), events);
    clock.now += 700000L;
    token = pair("Recovered");
    Map<String, Object> recovered = state();
    same(0L, recovered.get("rev"), "unreadable household storage starts empty");
    same("{\"location\":null,\"appearance\":{\"palette\":\"linen\",\"mode\":\"auto\"},\"icloudAlbum\":null}", Json.write(recovered.get("settings")), "unreadable settings fall back to defaults");
    check(api.frameId().matches("[0-9a-f\\-]{36}"), "an unreadable frame id is replaced");

    HouseholdStore store = new HouseholdStore(new Fakes.Storage());
    same(1L, store.touch(), "touch is one revision");
    same("2026-10-11", FrameTime.day(START, TimeZone.getTimeZone("UTC")), "day in UTC");
    same("2026-10-10", FrameTime.day(START, TimeZone.getTimeZone("America/Edmonton")), "day in the frame zone");
    same("2026-03-01", FrameTime.shift("2026-02-28", 1), "shift over a month end");
    same("2025-12-31", FrameTime.shift("2026-01-13", -13), "shift over a year end");
    check(FrameTime.validDay("2028-02-29") && !FrameTime.validDay("2026-02-29") && !FrameTime.validDay("2026-13-01") && !FrameTime.validDay(null), "calendar days are validated");
    check(Digests.same("abc", "abc") && !Digests.same("abc", "abd") && !Digests.same("abc", "abcd") && !Digests.same("", "a"), "constant time comparison");
    same("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Digests.sha256(new byte[0]), "sha-256 of nothing");
  }

  public static void main(String[] args) throws Exception {
    TimeZone.setDefault(TimeZone.getTimeZone("UTC"));
    json();
    http();
    pairing();
    tokens();
    household();
    limits();
    bridge();
    settings();
    calendarsOverHttp();
    photosOverHttp();
    persistence();
    System.out.println("LocalApi: " + checks + " checks passed");
  }
}
