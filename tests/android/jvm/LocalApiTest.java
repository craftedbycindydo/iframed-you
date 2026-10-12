package com.wesbos.homehq;

import java.io.ByteArrayInputStream;
import java.io.EOFException;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
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
  static Fakes.Uptime uptime;
  static Fakes.CalendarShelf calendars;
  static Fakes.PhotoShelf photos;
  static Fakes.Recorder events;
  static LocalApi api;
  static String token;
  static final Fakes.Wire wire = new Fakes.Wire() {
    @Override public Fakes.Reply send(byte[] raw) throws Exception {
      return Fakes.inMemory(api, raw);
    }
  };

  static Fakes.Album album = new Fakes.Album();
  static ICloudSync icloud;

  static ICloudSync sync(Fakes.Recorder recorder) {
    icloud = new ICloudSync(storage, clock, clock.steady, album, photos.library, Fakes.inline(), recorder.album);
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
    uptime = new Fakes.Uptime();
    calendars = new Fakes.CalendarShelf();
    photos = new Fakes.PhotoShelf();
    events = new Fakes.Recorder();
    album = new Fakes.Album();
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), events);
    token = pair("Test phone");
  }

  static String pair(String deviceName) throws Exception {
    return Fakes.pair(api, events, wire, deviceName);
  }

  static Fakes.Reply send(String method, String target, String bearer, String json) throws Exception {
    return Fakes.inMemory(api, Fakes.json(method, target, bearer, json));
  }

  static Fakes.Reply call(String method, String target, String json) throws Exception {
    return send(method, target, token, json);
  }

  static Fakes.Reply raw(String text) throws Exception {
    int firstLine = text.indexOf('\n');
    boolean addressed = text.toLowerCase().contains("host:") || firstLine < 0;
    String sent = addressed ? text : text.substring(0, firstLine + 1) + "Host: 192.168.1.20\r\n" + text.substring(firstLine + 1);
    return Fakes.inMemory(api, sent.getBytes(StandardCharsets.ISO_8859_1));
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
    same("{\"n\":2,\"d\":39.74}", Json.write(Json.object("n", 2L, "d", 39.74)), "numbers keep their shape");
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
    same(400, raw("get /v2/info HTTP/1.1\r\n\r\n").status, "lowercase method");
    same(400, raw("GET /v2/info HTTP/2.0\r\n\r\n").status, "unsupported version");
    same(400, raw("GET  /v2/info HTTP/1.1\r\n\r\n").status, "double space");
    same(400, raw("GET v1/info HTTP/1.1\r\n\r\n").status, "relative target");
    same(400, raw("GET /v1/photos/../../etc/passwd HTTP/1.1\r\n\r\n").status, "dot traversal");
    same(400, raw("GET /v1/photos/%2e%2e/secret HTTP/1.1\r\n\r\n").status, "encoded traversal");
    same(400, raw("GET /v1//state HTTP/1.1\r\n\r\n").status, "empty segment");
    same(400, raw("GET /v1/photos\\x HTTP/1.1\r\n\r\n").status, "backslash");
    same(400, raw("GET /v2/info HTTP/1.1\r\nNoColon\r\n\r\n").status, "header without colon");
    same(400, raw("GET /v2/info HTTP/1.1\r\nX-Long: " + repeat("a", 9000) + "\r\n\r\n").status, "oversize head");
    same(400, raw("GET /v2/info HTTP/1.1\r\n" + repeat("X-A: 1\r\n", 80) + "\r\n").status, "too many headers");
    same(400, raw("POST /v2/pair/start HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n").status, "chunked body");
    same(400, raw("GET /v2/info HTTP/1.1\r\nOrigin: http://evil.test\r\n\r\n").status, "browser origin");
    same(400, raw("POST /v2/pair/start HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\n{}").status, "repeated length");
    same(400, raw("POST /v2/pair/start HTTP/1.1\r\nContent-Length: -1\r\n\r\n").status, "negative length");
    same(400, raw("POST /v2/pair/start HTTP/1.1\r\nContent-Length: two\r\n\r\n").status, "worded length");
    Fakes.Reply bare = raw("GET /v2/info HTTP/1.0\nhost: 10.0.0.2\n\n");
    same(200, bare.status, "bare newlines and HTTP/1.0 are tolerated");
    same("close", bare.headers.get("connection"), "connection closes");
    same("no-store", bare.headers.get("cache-control"), "responses are not cached");
    check(bare.headers.get("content-type").startsWith("application/json"), "json content type");
    try {
      raw("GET /v2/info HTTP/1.1\r\nHost: x\r\n");
      throw new AssertionError("truncated head answered");
    } catch (EOFException expected) {
      checks++;
    }
    try {
      raw("POST /v2/pair/start HTTP/1.1\r\nContent-Length: 50\r\n\r\n{\"code\"");
      throw new AssertionError("truncated body answered");
    } catch (EOFException expected) {
      checks++;
    }

    Fakes.Reply info = send("GET", "/v2/info", null, null);
    same(2L, info.object().get("v"), "info version");
    same(Boolean.FALSE, info.object().get("pairing"), "info says no pairing window is open");
    same("[v, frameId, name, pairing]", info.object().keySet().toString(), "info fields");
    same(401, send("GET", "/v1/info", null, null).status, "the first version's info is gone");
    same(401, send("POST", "/v1/pair/start", null, null).status, "and so is its pairing");
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
    same(404, call("POST", "/v2/info", null).status, "wrong method on info");
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

  static String run(int from) {
    StringBuilder text = new StringBuilder();
    for (int value = from; value < from + 32; value++) text.append(String.format("%02x", value));
    return text.toString();
  }

  static Fakes.Reply start(String commit, String tokenHash, Object deviceName) throws Exception {
    return send("POST", "/v2/pair/start", null, Json.write(Json.object("commit", commit, "tokenHash", tokenHash, "deviceName", deviceName)));
  }

  static void open() throws Exception {
    same(Boolean.TRUE, Json.map(Json.parse(api.pairingOpen())).get("ok"), "the frame opens a pairing window");
  }

  static Fakes.Phone revealed(String name) throws Exception {
    Fakes.Phone phone = new Fakes.Phone();
    open();
    same(200, phone.start(wire, name).status, "start for " + name);
    same(204, phone.reveal(wire, api.identity().fpRaw).status, "reveal for " + name);
    return phone;
  }

  static String decoy(Fakes.Phone phone) {
    for (Object number : Json.list(events.pairing.get("numbers"))) if (!number.equals(phone.pick)) return (String) number;
    throw new AssertionError("no decoy shown");
  }

  static boolean accepting() throws Exception {
    return (Boolean) send("GET", "/v2/info", null, null).object().get("pairing");
  }

  static void pairing() throws Exception {
    byte[] nP = Digests.bytes(run(0x00));
    byte[] nF = Digests.bytes(run(0x20));
    byte[] fpRaw = Digests.bytes(run(0x40));
    same("630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd", Digests.sha256(nP), "test vector commit");
    byte[] vector = Pairing.digest(nP, nF, fpRaw);
    same("526438df18ab2fc054b103a87964836abe6e20d4118d11b6a6e50ebbca57d7af", Digests.hex(vector), "test vector D");
    same("299871", Pairing.code(vector), "test vector code");
    same("64", Pairing.pick(vector), "test vector pick");
    byte[] high = new byte[32];
    java.util.Arrays.fill(high, (byte) 0xFF);
    same("967295", Pairing.code(high), "the code uses unsigned arithmetic");
    same("95", Pairing.pick(high), "the pick uses unsigned arithmetic");
    same("000000", Pairing.code(new byte[32]), "the code keeps leading zeros");
    same("00", Pairing.pick(new byte[32]), "the pick keeps a leading zero");
    check(Digests.bytes("AB") == null && Digests.bytes("abc") == null && Digests.bytes("zz") == null && Digests.bytes(12) == null, "only lowercase hex pairs decode");
    same("00ff10", Digests.hex(Digests.bytes("00ff10")), "hex round trips");

    fresh();
    check(token.matches("[0-9a-f]{64}"), "the phone's token is 32 random bytes in hex");
    String saved = storage.values.get(Identity.KEY);
    check(!saved.contains(token), "the token itself is never stored");
    check(saved.contains(Digests.sha256(Digests.bytes(token))), "the SHA-256 of its 32 bytes is stored");
    check(storage.values.get("devices") == null, "nothing is kept under the first version's key");
    same("[waiting, code, paired, idle]", events.seen.toString(), "the frame walks through waiting, code and paired");
    List<Object> devices = call("GET", "/v1/devices", null).list();
    same(1, devices.size(), "one device");
    Map<String, Object> device = Json.map(devices.get(0));
    same("Test phone", device.get("name"), "device name");
    same("2026-10-11T00:00:00Z", device.get("pairedAt"), "pairedAt is ISO-8601");
    same("2026-10-11T00:00:00Z", device.get("lastSeen"), "lastSeen starts at pairing");
    same(Boolean.TRUE, device.get("self"), "the caller's own device is marked");
    check(!device.containsKey("hash") && device.keySet().size() == 5, "device rows expose only id, name, pairedAt, lastSeen, self");

    Fakes.Phone early = new Fakes.Phone();
    Fakes.Reply outside = early.start(wire, "Early phone");
    same(409, outside.status, "start outside a window");
    same("conflict", outside.error(), "start outside a window slug");
    check(!accepting(), "info reports no window");
    same(409, send("POST", "/v2/pair/reveal", null, "{\"session\":\"" + repeat("0", 32) + "\",\"nP\":\"" + run(0) + "\"}").status, "reveal outside a window");
    same(409, send("POST", "/v2/pair/cancel", null, "{\"session\":\"" + repeat("0", 32) + "\"}").status, "cancel outside a window");
    same(404, send("GET", "/v2/pair/result?session=" + repeat("0", 32), null, null).status, "result for a session that never existed");
    check(!api.pairingTap("00") && !api.pairingCancel(), "taps do nothing with no window");

    open();
    same("waiting", events.pairing.get("phase"), "the frame waits for a phone");
    same(Pairing.WINDOW, events.remaining, "the window lasts 120 seconds");
    same(120000L, events.pairing.get("remaining"), "and says so to the dashboard");
    check(accepting(), "info reports the open window");
    String good = run(0x00);
    Object[][] malformed = {{good.toUpperCase(), good, "Phone"}, {good, good.toUpperCase(), "Phone"}, {good.substring(2), good, "Phone"}, {good + "00", good, "Phone"},
        {good.substring(0, 63) + "g", good, "Phone"}, {good, good.substring(0, 63), "Phone"}, {good, good, null}, {good, good, "   "}, {good, good, repeat("n", 41)},
        {good, good, "Pho‮ne"}, {good, good, "Pho\u0007ne"}, {good, good, 7L}, {null, good, "Phone"}, {good, null, "Phone"}, {1L, good, "Phone"}};
    for (Object[] body : malformed) {
      Fakes.Reply refused = send("POST", "/v2/pair/start", null, Json.write(Json.object("commit", body[0], "tokenHash", body[1], "deviceName", body[2])));
      same(400, refused.status, "malformed start " + Json.write(java.util.Arrays.asList(body)));
    }
    same(400, send("POST", "/v2/pair/start", null, "[]").status, "start needs an object");
    same(413, raw("POST /v2/pair/start HTTP/1.1\r\nContent-Length: 4097\r\n\r\n").status, "unpaired bodies are limited to 4 KiB");
    check(accepting(), "a malformed start does not use up the window");

    Fakes.Phone decoyed = new Fakes.Phone();
    Fakes.Reply started = decoyed.start(wire, "  " + repeat("n", 40) + "  ");
    same(200, started.status, "the first start in a window");
    check(decoyed.session.matches("[0-9a-f]{32}") && Digests.hex(decoyed.nF).matches("[0-9a-f]{64}") && started.object().size() == 2, "start returns a session and nF and nothing else");
    check(!started.text().contains("token"), "the frame never sends a token");
    check(!accepting(), "the window is used up by the first start");
    for (int again = 0; again < 2; again++) {
      Fakes.Reply busy = new Fakes.Phone().start(wire, "Second phone");
      same(409, busy.status, "a second start in the same window");
      same("pairing_busy", busy.error(), "a second start slug");
    }
    same("waiting", events.pairing.get("phase"), "the frame shows no code before reveal");
    same(202, decoyed.result(wire).status, "result before reveal");
    check(!api.pairingTap("00"), "nothing can be tapped before reveal");
    same(400, send("GET", "/v2/pair/result?session=" + decoyed.session.toUpperCase(), null, null).status, "uppercase session");
    same(400, send("GET", "/v2/pair/result?session=" + decoyed.session.substring(2), null, null).status, "short session");
    same(400, send("GET", "/v2/pair/result", null, null).status, "missing session");
    same(404, send("GET", "/v2/pair/result?session=" + repeat("0", 32), null, null).status, "another session's result");
    same(400, send("POST", "/v2/pair/reveal", null, "{\"session\":\"" + decoyed.session + "\",\"nP\":\"" + Digests.hex(decoyed.nP).toUpperCase() + "\"}").status, "uppercase nP");
    same(400, send("POST", "/v2/pair/reveal", null, "{\"session\":\"" + decoyed.session + "\",\"nP\":\"" + Digests.hex(decoyed.nP).substring(2) + "\"}").status, "short nP");
    same(409, send("POST", "/v2/pair/reveal", null, "{\"session\":\"" + repeat("0", 32) + "\",\"nP\":\"" + Digests.hex(decoyed.nP) + "\"}").status, "reveal for another session");
    same(204, decoyed.reveal(wire, api.identity().fpRaw).status, "reveal");
    same("code", events.pairing.get("phase"), "the frame shows the code after reveal");
    Fakes.Reply racing = new Fakes.Phone().start(wire, "Racing phone");
    same(409, racing.status, "a second phone while the code is showing");
    same("pairing_busy", racing.error(), "is told another phone holds the window");
    same("code", events.pairing.get("phase"), "and does not disturb the first phone's code");
    same(decoyed.code, events.pairing.get("code"), "the frame and the phone compute the same code");
    check(decoyed.code.matches("[0-9]{6}") && decoyed.pick.matches("[0-9]{2}"), "six digits and two digits");
    List<Object> numbers = Json.list(events.pairing.get("numbers"));
    check(numbers.size() == 3 && new java.util.HashSet<>(numbers).size() == 3 && numbers.contains(decoyed.pick), "three different numbers include the phone's");
    check(!Json.write(events.pairing).contains("pick"), "the dashboard is not told which number is right");
    same(decoyed.pick, api.pairingPick(), "the frame knows the pick");
    same(409, decoyed.reveal(wire, api.identity().fpRaw).status, "reveal twice");
    same("code", events.pairing.get("phase"), "a repeated reveal changes nothing");
    same(202, decoyed.result(wire).status, "result before approval");
    check(!api.pairingTap(decoy(decoyed)), "a decoy does not approve");
    same("cancelled", events.pairing.get("phase"), "a decoy ends the session on the frame");
    same("decoy", events.pairing.get("reason"), "and says why");
    Fakes.Reply refused = decoyed.result(wire);
    same(403, refused.status, "result after a decoy");
    same("forbidden", refused.error(), "403 slug");
    check(!api.pairingTap(decoyed.pick), "the right number no longer works after a decoy");
    same(401, send("GET", "/v1/state", decoyed.bearer(), null).status, "a refused phone holds no token");
    same(409, new Fakes.Phone().start(wire, "Phone").status, "the window stays closed after a decoy");
    same("conflict", new Fakes.Phone().start(wire, "Phone").error(), "and is reported as no window, not as a busy one");
    same(1, call("GET", "/v1/devices", null).list().size(), "nothing was paired");

    Fakes.Phone liar = new Fakes.Phone();
    open();
    liar.start(wire, "Liar");
    Fakes.Reply lie = send("POST", "/v2/pair/reveal", null, "{\"session\":\"" + liar.session + "\",\"nP\":\"" + run(0x60) + "\"}");
    same(400, lie.status, "reveal with the wrong nP");
    same("cancelled", events.pairing.get("phase"), "a wrong nP ends the session");
    same(403, liar.result(wire).status, "result after a wrong nP");
    same(409, liar.reveal(wire, api.identity().fpRaw).status, "the right nP is too late");

    Fakes.Phone quitter = revealed("Quitter");
    same(204, quitter.cancel(wire).status, "cancel from the phone");
    same("phone", events.pairing.get("reason"), "the frame says the phone cancelled");
    same(204, quitter.cancel(wire).status, "cancel twice");
    same(403, quitter.result(wire).status, "result after cancel");
    check(!api.pairingTap(quitter.pick), "the number no longer works after cancel");
    same(400, send("POST", "/v2/pair/cancel", null, "{\"session\":\"" + quitter.session.toUpperCase() + "\"}").status, "uppercase session in cancel");
    same(409, send("POST", "/v2/pair/cancel", null, "{\"session\":\"" + repeat("0", 32) + "\"}").status, "cancel for another session");

    Fakes.Phone dismissed = revealed("Dismissed");
    check(api.pairingCancel(), "Cancel on the frame");
    same("frame", events.pairing.get("reason"), "the frame says it was cancelled there");
    same(403, dismissed.result(wire).status, "result after Cancel on the frame");
    check(api.pairingCancel(), "closing the cancelled screen");
    same("idle", events.pairing.get("phase"), "returns the frame to idle");
    same(403, dismissed.result(wire).status, "the result outlives the screen");
    open();
    check(api.pairingCancel(), "Cancel before any phone connects");
    same(409, new Fakes.Phone().start(wire, "Late").status, "closes the window");
    same(404, dismissed.result(wire).status, "a new window forgets the session before it");

    Fakes.Phone slow = revealed("Slow");
    uptime.now += Pairing.WINDOW - 1;
    clock.now += 30 * DAY;
    same(202, slow.result(wire).status, "a wall clock jumping forward does not close the window");
    clock.now -= 90 * DAY;
    same(202, slow.result(wire).status, "nor does one jumping back");
    same(1L, Json.map(Json.map(Json.parse(api.pairingStatus(8765, true, ""))).get("pairing")).get("remaining"), "one millisecond is left");
    uptime.now += 1;
    Fakes.Reply expired = slow.result(wire);
    same(410, expired.status, "result after expiry");
    same("gone", expired.error(), "410 slug");
    same("cancelled", events.pairing.get("phase"), "the frame leaves the code screen at expiry");
    same("expired", events.pairing.get("reason"), "and says it ran out");
    same(410, slow.cancel(wire).status == 204 ? slow.result(wire).status : 0, "cancel after expiry leaves it expired");
    check(!api.pairingTap(slow.pick), "the number no longer works after expiry");
    clock.now = START;
    open();
    clock.now -= 365 * DAY;
    uptime.now += Pairing.WINDOW;
    same(409, new Fakes.Phone().start(wire, "Phone").status, "turning the wall clock back does not keep a window open");
    same("conflict", new Fakes.Phone().start(wire, "Phone").error(), "a window that only timed out is not reported as busy");
    same("expired", events.pairing.get("reason"), "an unused window expires too");
    clock.now = START;
    Fakes.Phone unrevealed = new Fakes.Phone();
    open();
    unrevealed.start(wire, "Unrevealed");
    uptime.now += Pairing.WINDOW;
    same(410, unrevealed.reveal(wire, api.identity().fpRaw).status, "reveal after expiry");

    Fakes.Phone welcome = revealed("Maya's iPhone");
    check(api.pairingTap(welcome.pick), "tapping the phone's number approves");
    same("paired", events.pairing.get("phase"), "the frame shows success");
    same("Maya's iPhone", events.pairing.get("name"), "with the device name");
    Fakes.Reply approved = welcome.result(wire);
    same(200, approved.status, "result after approval");
    same(api.frameId(), approved.object().get("frameId"), "result frame id");
    same("Skylit", approved.object().get("name"), "result name");
    check(((String) approved.object().get("deviceId")).matches("[0-9a-f]{16}") && approved.object().size() == 3, "result carries deviceId, frameId and name only");
    same(200, welcome.result(wire).status, "the result can be read again");
    same(200, send("GET", "/v1/state", welcome.bearer(), null).status, "the phone's own token now works");
    check(!api.pairingTap(welcome.pick), "an approved session cannot be approved twice");
    same(2, call("GET", "/v1/devices", null).list().size(), "exactly one device was added");
    same(409, welcome.reveal(wire, api.identity().fpRaw).status, "reveal after approval");
    same(204, welcome.cancel(wire).status, "cancel after approval is accepted");
    same(200, send("GET", "/v1/state", welcome.bearer(), null).status, "but does not unpair");
    check(api.pairingCancel() && !api.pairingCancel(), "closing the success screen once");

    for (int round = 0; round < 40; round++) {
      Fakes.Phone sampled = revealed("Sampled");
      List<Object> shown = Json.list(events.pairing.get("numbers"));
      check(new java.util.HashSet<>(shown).size() == 3 && shown.contains(sampled.pick), "decoys differ from the pick and each other");
      for (Object number : shown) check(((String) number).matches("[0-9]{2}"), "numbers have two digits");
      api.pairingCancel();
    }

    storage = new Fakes.Storage();
    events = new Fakes.Recorder();
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), events);
    for (int paired = 0; paired < Pairing.MAX_DEVICES; paired++) pair("Phone " + paired);
    Map<String, Object> full = Json.map(Json.parse(api.pairingOpen()));
    same(Boolean.FALSE, full.get("ok"), "the frame will not open a window for a 21st device");
    check(full.get("error") instanceof String, "and says why");
    Fakes.Reply extra = new Fakes.Phone().start(wire, "Phone 21");
    same(409, extra.status, "device limit");
    same("conflict", extra.error(), "device limit slug");
  }

  static void tokens() throws Exception {
    fresh();
    Fakes.Phone twice = new Fakes.Phone();
    for (String name : new String[] {"First pairing", "Second pairing"}) {
      open();
      twice.start(wire, name);
      twice.reveal(wire, api.identity().fpRaw);
      check(api.pairingTap(twice.pick), name + " approved");
      api.pairingCancel();
    }
    List<Object> listed = send("GET", "/v1/devices", twice.bearer(), null).list();
    same(2, listed.size(), "pairing again with the same token replaces the earlier entry");
    Map<String, Object> repaired = Json.map(listed.get(1));
    check("Second pairing".equals(repaired.get("name")) && Boolean.TRUE.equals(repaired.get("self")), "and keeps the newer name");
    same(204, send("DELETE", "/v1/devices/" + repaired.get("id"), twice.bearer(), null).status, "that phone removes itself");
    same(401, send("GET", "/v1/state", twice.bearer(), null).status, "and its token stops working");
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

    String second = pair("Second phone");
    List<Object> devices = call("GET", "/v1/devices", null).list();
    same(2, devices.size(), "two devices");
    String firstId = null;
    String secondId = null;
    for (Object device : devices) {
      boolean mine = Json.map(device).get("name").equals("Test phone");
      same(mine, Json.map(device).get("self"), "only the caller's device is self");
      if (mine) firstId = (String) Json.map(device).get("id");
      else secondId = (String) Json.map(device).get("id");
    }
    Fakes.Reply stranger = call("DELETE", "/v1/devices/unknown", null);
    same(403, stranger.status, "unknown device");
    same("forbidden", stranger.error(), "403 slug");
    same(403, call("DELETE", "/v1/devices/" + secondId, null).status, "a phone cannot remove another phone");
    same(200, send("GET", "/v1/state", second, null).status, "the other phone keeps working");
    same(401, send("DELETE", "/v1/devices/" + secondId, null, null).status, "removing needs a token");
    same(204, send("DELETE", "/v1/devices/" + secondId, second, null).status, "a phone removes itself");
    same(401, send("GET", "/v1/state", second, null).status, "its token stops working");
    same(200, call("GET", "/v1/state", null).status, "other tokens keep working");
    same(401, send("DELETE", "/v1/devices/" + secondId, second, null).status, "removing twice");

    String unit = storage.values.get(Identity.KEY);
    clock.now += DAY - 1;
    same(200, call("GET", "/v1/state", null).status, "a request within a day of the last one seen");
    same(unit, storage.values.get(Identity.KEY), "writes nothing");
    clock.now += 1;
    call("GET", "/v1/state", null);
    same(FrameTime.iso(START + DAY), Json.map(call("GET", "/v1/devices", null).list().get(0)).get("lastSeen"), "lastSeen moves after a day");
    clock.now -= 5 * DAY;
    call("GET", "/v1/state", null);
    same(FrameTime.iso(START + DAY), Json.map(call("GET", "/v1/devices", null).list().get(0)).get("lastSeen"), "lastSeen never moves backwards");
    clock.now = START + 800 * DAY;
    same(200, call("GET", "/v1/state", null).status, "tokens do not expire");
    same(FrameTime.iso(START + 800 * DAY), Json.map(call("GET", "/v1/devices", null).list().get(0)).get("lastSeen"), "and lastSeen follows");
    clock.now = START;

    Map<String, Object> status = Json.map(Json.parse(api.pairingStatus(8765, true, "192.168.1.20")));
    same(8765L, status.get("port"), "status port");
    same(Boolean.TRUE, status.get("advertised"), "status advertised");
    same("192.168.1.20", status.get("address"), "status address");
    same("idle", Json.map(status.get("pairing")).get("phase"), "status pairing phase");
    same(1, Json.list(status.get("devices")).size(), "status devices");
    same("[id, name, pairedAt, lastSeen]", Json.map(Json.list(status.get("devices")).get(0)).keySet().toString(), "status device fields");
    check(!api.pairingRevoke("unknown"), "bridge revoke of an unknown device");
    String third = pair("Third phone");
    String thirdId = null;
    for (Object device : call("GET", "/v1/devices", null).list()) {
      if (Json.map(device).get("name").equals("Third phone")) thirdId = (String) Json.map(device).get("id");
    }
    check(api.pairingRevoke(thirdId), "bridge revoke");
    same(401, send("GET", "/v1/state", third, null).status, "bridge revoked token stops working");
    check(api.pairingRevokeAll(), "bridge revoke all");
    same(401, call("GET", "/v1/state", null).status, "revoke all removes every token");
    same("[]", Json.write(Json.map(Json.parse(api.pairingStatus(0, false, ""))).get("devices")), "no devices remain");
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

  static void blanks() throws Exception {
    fresh();
    for (String blank : new String[] {"\u00a0", "\u00a0 \u2003", "\u3000\u3000", "\ufeff", "\u2028"}) {
      same(400, call("POST", "/v1/people", Json.write(Json.object("name", blank, "color", "#00A36C"))).status, "a name of only spaces is refused " + Json.write(blank));
      same(400, call("POST", "/v1/shopping", Json.write(Json.object("name", blank))).status, "an item of only spaces is refused " + Json.write(blank));
    }
    same("Maya", row(call("POST", "/v1/people", Json.write(Json.object("name", "\u00a0Maya\u3000", "color", "#00A36C"))), "person").get("name"), "every kind of space is trimmed");
  }

  static void invisible() throws Exception {
    fresh();
    for (String hidden : new String[] {"\u200b", "\u200b\u200d\u2060", "\u200d\ufe0f", "\u3164", "\u00ad\u034f", "\u2800", "\udb40\udc41"}) {
      same(400, call("POST", "/v1/people", Json.write(Json.object("name", hidden, "color", "#00A36C"))).status, "a name nobody can see is refused " + Json.write(hidden));
      same(400, call("POST", "/v1/chores", Json.write(Json.object("title", hidden))).status, "a title nobody can see is refused " + Json.write(hidden));
      same(400, call("POST", "/v1/shopping", Json.write(Json.object("name", hidden))).status, "an item nobody can see is refused " + Json.write(hidden));
      same(400, call("PUT", "/v1/settings/location", Json.write(Json.object("name", hidden, "latitude", 1, "longitude", 1))).status, "a place nobody can see is refused " + Json.write(hidden));
    }
    String family = "\ud83d\udc68\u200d\ud83d\udc69\u200d\ud83d\udc67";
    same(family, row(call("POST", "/v1/people", Json.write(Json.object("name", family, "color", "#00A36C"))), "person").get("name"), "an emoji joined with zero-width joiners is a name");
    String persian = "\u0645\u06cc\u200c\u062e\u0648\u0627\u0647\u0645";
    same(persian, row(call("POST", "/v1/shopping", Json.write(Json.object("name", persian))), "item").get("name"), "a zero-width non-joiner inside a word is kept");
    same("a\u200b", row(call("POST", "/v1/shopping", Json.write(Json.object("name", "a\u200b"))), "item").get("name"), "one visible character is enough");
    same(200, call("POST", "/v1/chores", Json.write(Json.object("title", "Bins", "emoji", ""))).status, "an empty emoji is still allowed");
    same(200, call("POST", "/v1/shopping", Json.write(Json.object("name", "Tea", "note", "\u200b"))).status, "an optional note is not held to this");
    for (String name : new String[] {"\u0645\u062d\u0645\u062f", "\u0641\u0627\u0637\u0645\u0629 \u0627\u0644\u0632\u0647\u0631\u0627\u0621", "\u05d3\u05b8\u05bc\u05d5\u05b4\u05d3", "\u0936\u093f\u0935", "\u092a\u094d\u0930\u093f\u092f\u093e", "\u0e2a\u0e21\u0e0a\u0e32\u0e22", "\u0e19\u0e49\u0e33", "\uae40\ubbfc\uc900", "\u1100", "\u5c71\u7530\u592a\u90ce", "\u738b\u82b3", "Zo\u00eb", "Zoe\u0308", "Nguy\u1ec5n", "e\u0301", "\u0301", "\ud83d\ude00", "\ud83d\udc4d\ud83c\udffd", "\ud83e\uddd1\ud83c\udfff\u200d\ud83e\uddb1", "\ud83c\udde8\ud83c\udde6", "\ud83c\udff4\udb40\udc67\udb40\udc62\udb40\udc65\udb40\udc6e\udb40\udc67\udb40\udc7f", "1\ufe0f\u20e3", "\u2665", "\u200f\u05e2\u05d1\u05e8\u05d9\u05ea\u200f", "O\u2019Brien", "\u03a9mega", "\u2d30\u2d4e\u2d30\u2d63\u2d49\u2d56", "\u1403\u14c4\u1483\u144e\u1450\u1466", "\ud835\udc9c", ".", "-"}) {
      same(name, row(call("POST", "/v1/shopping", Json.write(Json.object("name", name))), "item").get("name"), "a real name is kept as typed " + Json.write(name));
      same(200, call("POST", "/v1/chores", Json.write(Json.object("title", name))).status, "and is a title " + Json.write(name));
      api.pairingOpen();
      same(200, new Fakes.Phone().start(wire, name).status, "and a device name " + Json.write(name));
    }
    api.pairingOpen();
    same(400, new Fakes.Phone().start(wire, "\u200b\u2060").status, "a device name nobody can see is refused");
    same(true, Json.map(Json.parse(call("GET", "/v2/info", null).text())).get("pairing"), "and does not use up the window");
  }

  static void damaged() throws Exception {
    fresh();
    call("PUT", "/v1/settings/appearance", "{\"palette\":\"sage\",\"mode\":\"dark\"}");
    storage.values.put("household", "{\"rev\":9,\"sequence\":12,\"people\":[{\"id\":\"p1\",\"name\":\"Maya\",\"color\":\"#00A36C\"},{\"id\":\"p2\",\"name\":7,\"color\":\"#00A36C\"},{\"name\":\"Nobody\",\"color\":\"#00A36C\"}],"
        + "\"chores\":[{\"id\":\"c3\",\"title\":\"Make bed\",\"emoji\":\"\",\"personId\":\"p1\",\"days\":[1],\"done\":[\"2026-10-11\"]},{\"id\":\"c4\",\"title\":\"Bins\",\"emoji\":\"\",\"personId\":null,\"days\":[],\"done\":\"yes\"},"
        + "{\"id\":\"c5\",\"title\":\"Dog\",\"emoji\":\"\",\"personId\":null,\"days\":[],\"done\":[20261011]},{\"id\":\"c6\",\"title\":\"Plants\",\"emoji\":\"\",\"personId\":null,\"days\":\"daily\",\"done\":[]},{\"title\":\"Lost\"},"
        + "{\"id\":\"c7\",\"title\":\"Dishes\",\"emoji\":\"\",\"personId\":\"p2\",\"days\":[],\"done\":[]}],"
        + "\"shopping\":[{\"id\":\"s8\",\"name\":\"Milk\",\"qty\":2,\"note\":\"\",\"done\":false},{\"id\":\"s9\",\"name\":\"Tea\",\"qty\":\"lots\",\"note\":\"\",\"done\":false},{\"id\":\"s10\",\"name\":\"Jam\",\"qty\":1,\"note\":\"\",\"done\":\"no\"},{\"id\":11}]}");
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    Map<String, Object> kept = state();
    same("[{\"id\":\"p1\",\"name\":\"Maya\",\"color\":\"#00A36C\"}]", Json.write(kept.get("people")), "a damaged person is dropped and the others stay");
    same("[{\"id\":\"c3\",\"title\":\"Make bed\",\"emoji\":\"\",\"personId\":\"p1\",\"days\":[1],\"done\":[\"2026-10-11\"]},{\"id\":\"c7\",\"title\":\"Dishes\",\"emoji\":\"\",\"personId\":null,\"days\":[],\"done\":[]}]",
        Json.write(kept.get("chores")), "damaged chores are dropped, and a chore whose person is gone becomes anyone's");
    same("[{\"id\":\"s8\",\"name\":\"Milk\",\"qty\":2,\"note\":\"\",\"done\":false}]", Json.write(kept.get("shopping")), "damaged items are dropped");
    same(9L, kept.get("rev"), "the revision is kept");
    same("sage", Json.map(Json.map(kept.get("settings")).get("appearance")).get("palette"), "unrelated settings are untouched");
    same(200, call("GET", "/v1/devices", null).status, "paired phones are untouched");
    same("p13", row(call("POST", "/v1/people", "{\"name\":\"Noor\",\"color\":\"#123456\"}"), "person").get("id"), "new ids continue after the damage");
    same(200, call("PUT", "/v1/chores/c3/done", "{\"date\":\"2026-10-10\",\"done\":true}").status, "the surviving chore still works");
    same(9, api.householdDropped(), "the dropped rows are counted for the log");
    check(storage.values.get("household-damaged").contains("\"Nobody\"") && storage.values.get("household-damaged").contains("\"lots\""), "and the unreadable original is set aside, not lost");
    check(Json.map(Json.parse(api.householdMutate("{\"op\":\"chore.remove\",\"id\":\"c7\"}"))).get("ok").equals(true), "the dashboard can still change the list");
    check(storage.values.get("household-damaged").contains("\"Nobody\""), "a later save leaves the copy alone");
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same(0, api.householdDropped(), "a sound store drops nothing");

    storage.values.put("household", "{\"rev\":3,\"sequence\":4,\"people\":{},\"chores\":[[]],\"shopping\":null}");
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    kept = state();
    same("[][][]", Json.write(kept.get("people")) + Json.write(kept.get("chores")) + Json.write(kept.get("shopping")), "lists of the wrong kind start empty");
    same(3L, kept.get("rev"), "without losing the revision");

    StringBuilder big = new StringBuilder("{\"rev\":1,\"sequence\":400,\"people\":[],\"chores\":[");
    String title = new String(new char[80]).replace("\0", "\ud83d\ude00");
    for (int i = 0; i < 100; i++) {
      big.append(i == 0 ? "" : ",").append("{\"id\":\"c").append(i).append("\",\"title\":\"").append(title).append("\",\"emoji\":\"\",\"personId\":null,\"days\":[],\"done\":[");
      for (int day = 0; day < 14; day++) big.append(day == 0 ? "" : ",").append('"').append(FrameTime.shift("2026-10-11", -day)).append('"');
      big.append("]}");
    }
    big.append("],\"shopping\":[");
    String note = new String(new char[200]).replace("\0", "\ud83d\ude00");
    for (int i = 0; i < 200; i++) big.append(i == 0 ? "" : ",").append("{\"id\":\"s").append(100 + i).append("\",\"name\":\"").append(title).append("\",\"qty\":99,\"note\":\"").append(note).append("\",\"done\":false}");
    storage.values.put("household", big.append("]}").toString());
    long began = System.nanoTime();
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    String full = api.householdSnapshot();
    same(200, call("PATCH", "/v1/shopping/s150", "{\"done\":true}").status, "the fullest list can still be changed");
    long millis = (System.nanoTime() - began) / 1000000L;
    check(millis < 1500, "the fullest household loads, lists and saves quickly, took " + millis + " ms");
    check(storage.values.get("household").getBytes(StandardCharsets.UTF_8).length < 400 * 1024, "and stays far below what private storage holds comfortably: " + storage.values.get("household").length());
    check(full.length() > 100000, "with everything in it");
  }

  static void unsaved() throws Exception {
    fresh();
    same(200, call("POST", "/v1/people", "{\"name\":\"Maya\",\"color\":\"#00A36C\"}").status, "a person while storage works");
    same(200, call("POST", "/v1/shopping", "{\"name\":\"Milk\"}").status, "an item while storage works");
    String before = call("GET", "/v1/state", null).text();
    String disk = storage.values.get("household");
    int announced = events.count("household");
    storage.full = true;
    String[][] changes = {{"POST", "/v1/people", "{\"name\":\"Noor\",\"color\":\"#123456\"}"}, {"PATCH", "/v1/people/p1", "{\"name\":\"May\"}"}, {"DELETE", "/v1/people/p1", null},
        {"POST", "/v1/chores", "{\"title\":\"Bins\"}"}, {"POST", "/v1/shopping", "{\"name\":\"Tea\"}"}, {"PATCH", "/v1/shopping/s2", "{\"done\":true}"},
        {"DELETE", "/v1/shopping/s2", null}, {"PUT", "/v1/settings/appearance", "{\"palette\":\"sage\",\"mode\":\"dark\"}"},
        {"PUT", "/v1/settings/location", "{\"name\":\"Denver\",\"latitude\":39.74,\"longitude\":-104.99}"},
        {"PUT", "/v1/settings/icloud-album", "{\"url\":\"https://www.icloud.com/sharedalbum/#B0aGWZuqDGWZuqD\"}"}};
    for (String[] change : changes) {
      Fakes.Reply refused = call(change[0], change[1], change[2]);
      same(500, refused.status, "a change that cannot be saved is not acknowledged: " + change[0] + " " + change[1]);
      same("internal", refused.error(), "with the internal slug: " + change[1]);
    }
    same(before, call("GET", "/v1/state", null).text(), "and the frame keeps showing what is really saved");
    same(announced, events.count("household"), "the dashboard is not told of a change that did not happen");
    same(0, events.count("settings"), "nor asked to apply a setting that was not kept");
    Map<String, Object> bridged = mutate("{\"op\":\"item.add\",\"name\":\"Jam\"}");
    same(Boolean.FALSE, bridged.get("ok"), "the dashboard is told its own change was not saved");
    check(((String) bridged.get("error")).contains("could not save"), "in words it can show: " + bridged.get("error"));
    check(!api.reportSettings("{\"appearance\":{\"palette\":\"plum\",\"mode\":\"dark\"}}"), "a reported setting that cannot be kept says so");
    same(disk, storage.values.get("household"), "nothing half-written reaches storage");
    same(200, call("PATCH", "/v1/people/p1", "{\"name\":\"Maya\"}").status, "a request that changes nothing still succeeds");
    same(200, call("GET", "/v1/photos", null).status, "reading still works");

    api.pairingOpen();
    Fakes.Phone late = new Fakes.Phone();
    same(200, late.start(wire, "Late phone").status, "pairing can start");
    same(204, late.reveal(wire, api.identity().fpRaw).status, "and reveal");
    check(!api.pairingTap(late.pick), "the right number does not pair a phone that cannot be saved");
    same("cancelled", events.pairing.get("phase"), "the frame shows it ended");
    same("storage", events.pairing.get("reason"), "and why");
    same(403, late.result(wire).status, "the phone is told it is not paired");
    same(401, send("GET", "/v1/state", late.bearer(), null).status, "and its token does not work");
    same(1, Json.list(Json.map(Json.parse(api.pairingStatus(0, false, ""))).get("devices")).size(), "only the first phone is listed");
    check(!api.pairingRevoke((String) Json.map(Json.list(Json.map(Json.parse(api.pairingStatus(0, false, ""))).get("devices")).get(0)).get("id")), "a removal that cannot be saved is reported");
    same(401, call("GET", "/v1/state", null).status, "though the phone is refused from now on");

    storage.full = false;
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same(before, call("GET", "/v1/state", null).text(), "after a restart the frame holds exactly what it acknowledged");
    same("p3", row(call("POST", "/v1/people", "{\"name\":\"Noor\",\"color\":\"#123456\"}"), "person").get("id"), "ids refused during the failure are not skipped");
    storage.full = true;
    String own = (String) Json.map(call("GET", "/v1/devices", null).list().get(0)).get("id");
    same(500, call("DELETE", "/v1/devices/" + own, null).status, "a phone's own removal that cannot be saved is an error");
    same(401, call("GET", "/v1/state", null).status, "and the phone is refused until the frame restarts");
    storage.full = false;
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same(200, call("GET", "/v1/state", null).status, "when it is paired again, as storage says");
  }

  static void clockless() throws Exception {
    fresh();
    clock.jumped = -START + 86400000L * 400;
    String early = pair("Early phone");
    Map<String, Object> listed = Json.map(send("GET", "/v1/devices", early, null).list().get(1));
    check(listed.get("pairedAt") == null && listed.get("lastSeen") == null, "a phone paired before the clock is set has no dates yet: " + Json.write(listed));
    check(!storage.values.get(Identity.KEY).contains("1971"), "no date from an unset clock is stored");
    clock.jumped = 0;
    same(200, send("GET", "/v1/state", early, null).status, "its token works");
    listed = Json.map(send("GET", "/v1/devices", early, null).list().get(1));
    same("2026-10-11T00:00:00Z", listed.get("pairedAt"), "the date is recorded once the clock is right");
    same("2026-10-11T00:00:00Z", listed.get("lastSeen"), "with when it was last seen");
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same("2026-10-11T00:00:00Z", Json.map(send("GET", "/v1/devices", early, null).list().get(1)).get("pairedAt"), "and kept over a restart");
    clock.jumped = -START + 86400000L * 400;
    clock.now += 3 * 86400000L;
    same(200, call("GET", "/v1/state", null).status, "a request while the clock is unset");
    same("2026-10-11T00:00:00Z", Json.map(call("GET", "/v1/devices", null).list().get(0)).get("lastSeen"), "does not replace a real date with one from 1971");
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
    Fakes.Reply located = call("PUT", "/v1/settings/location", "{\"name\":\"Denver\",\"latitude\":39.74,\"longitude\":-104.99,\"timezone\":\"America/Denver\"}");
    same("{\"rev\":1}", located.text(), "location saved");
    same("{\"location\":{\"name\":\"Denver\",\"latitude\":39.74,\"longitude\":-104.99,\"timezone\":\"America/Denver\"}}", events.settings, "dashboard asked to apply the location");
    same("{\"name\":\"Denver\",\"latitude\":39.74,\"longitude\":-104.99,\"timezone\":\"America/Denver\"}",
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

  static void settingsTogether() throws Exception {
    fresh();
    int lost = 0;
    for (int round = 0; round < 3000 && lost == 0; round++) {
      final String city = "City " + round;
      final String palette = round % 2 == 0 ? "ocean" : "stone";
      final java.util.concurrent.CountDownLatch together = new java.util.concurrent.CountDownLatch(1);
      Thread phone = new Thread(new Runnable() {
        @Override public void run() {
          try {
            together.await();
            call("PUT", "/v1/settings/location", "{\"name\":\"" + city + "\",\"latitude\":1,\"longitude\":1}");
          } catch (Exception failed) {
            throw new IllegalStateException(failed);
          }
        }
      });
      Thread frame = new Thread(new Runnable() {
        @Override public void run() {
          try {
            together.await();
            api.reportSettings("{\"appearance\":{\"palette\":\"" + palette + "\",\"mode\":\"dark\"}}");
          } catch (InterruptedException failed) {
            throw new IllegalStateException(failed);
          }
        }
      });
      phone.start();
      frame.start();
      together.countDown();
      phone.join();
      frame.join();
      Map<String, Object> kept = Json.map(state().get("settings"));
      if (!city.equals(Json.map(kept.get("location")).get("name")) || !palette.equals(Json.map(kept.get("appearance")).get("palette"))) lost++;
    }
    same(0, lost, "a city from a phone and a palette from the dashboard saved at the same moment are both kept");
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
    String sixty = new String(new char[60]).replace("\0", "n");
    same(400, call("POST", "/v1/calendars", "{\"name\":\"" + sixty + "n\",\"color\":\"#2D5BFF\",\"url\":\"" + FEED.replace("private-test", "private-long") + "\"}").status,
        "a calendar name longer than the frame stores is refused, not cut");
    same(400, call("POST", "/v1/calendars", "{\"name\":\"" + new String(new char[31]).replace("\0", "\ud83d\udcc5") + "\",\"color\":\"#2D5BFF\",\"url\":\"" + FEED.replace("private-test", "private-emoji") + "\"}").status,
        "nor is one the frame would cut in the middle of an emoji");
    same(1, Json.list(state().get("calendars")).size(), "neither was added");
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

  static void identity() throws Exception {
    fresh();
    String fp = api.identity().fp;
    check(fp.matches("[0-9a-f]{64}") && api.frameId().equals(fp.substring(0, 32)), "frameId is the first 32 hex characters of fp");
    same(api.frameId(), send("GET", "/v2/info", null, null).object().get("frameId"), "info carries it");
    Map<String, Object> unit = Json.map(Json.parse(storage.values.get(Identity.KEY)));
    same("[key, certificate, devices]", unit.keySet().toString(), "key, certificate and devices are stored as one unit");
    byte[] der = Digests.bytes(unit.get("certificate"));
    same(fp, Digests.sha256(der), "fp is the SHA-256 of the certificate DER");
    java.security.cert.X509Certificate certificate = (java.security.cert.X509Certificate)
        java.security.cert.CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(der));
    same(Digests.hex(der), Digests.hex(certificate.getEncoded()), "the hand-built DER is canonical");
    same(3, certificate.getVersion(), "X.509 v3");
    check(certificate.getCriticalExtensionOIDs() == null && certificate.getNonCriticalExtensionOIDs() == null, "no extensions");
    check(certificate.getSerialNumber().signum() > 0 && certificate.getSerialNumber().toByteArray().length == 8, "a positive 8-byte serial");
    same("CN=Skylit", certificate.getSubjectX500Principal().getName(), "subject");
    same(certificate.getSubjectX500Principal(), certificate.getIssuerX500Principal(), "issuer equals subject");
    same("2020-01-01T00:00:00Z", FrameTime.iso(certificate.getNotBefore().getTime()), "notBefore");
    same("2049-12-31T23:59:59Z", FrameTime.iso(certificate.getNotAfter().getTime()), "notAfter");
    check(Digests.hex(der).contains("170d3230303130313030303030305a170d3439313233313233353935395a"), "validity is two UTCTime values");
    same("1.2.840.10045.4.3.2", certificate.getSigAlgOID(), "ecdsa-with-SHA256");
    check(certificate.getSigAlgParams() == null, "no algorithm parameters");
    same(3, Digests.hex(der).split("300a06082a8648ce3d040302", -1).length, "the algorithm appears twice with no NULL");
    same(256, ((java.security.interfaces.ECPublicKey) certificate.getPublicKey()).getParams().getCurve().getField().getFieldSize(), "a P-256 key");
    certificate.verify(certificate.getPublicKey());
    java.security.KeyFactory.getInstance("EC").generatePrivate(new java.security.spec.PKCS8EncodedKeySpec(Digests.bytes(unit.get("key"))));
    check(api.identity().tls() != null, "the stored identity makes a TLS context");
    check(!Identity.open(new Fakes.Storage()).fp.equals(fp), "every frame makes its own identity");

    String stored = storage.values.get(Identity.KEY);
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same(fp, api.identity().fp, "the identity survives a restart");
    same(stored, storage.values.get(Identity.KEY), "a restart rewrites nothing");
    same(200, call("GET", "/v1/state", null).status, "and so does the paired phone");

    String key = (String) unit.get("key");
    String cert = (String) unit.get("certificate");
    Fakes.Storage spare = new Fakes.Storage();
    Identity.open(spare);
    Map<String, Object> other = Json.map(Json.parse(spare.values.get(Identity.KEY)));
    String[] losses = {"{broken", "[]", Json.write(Json.object("certificate", cert, "devices", unit.get("devices"))),
        Json.write(Json.object("key", key, "devices", unit.get("devices"))),
        Json.write(Json.object("key", key, "certificate", cert.substring(0, cert.length() - 8), "devices", unit.get("devices"))),
        Json.write(Json.object("key", key.substring(0, 40), "certificate", cert, "devices", unit.get("devices"))),
        Json.write(Json.object("key", key.toUpperCase(), "certificate", cert, "devices", unit.get("devices"))),
        Json.write(Json.object("key", other.get("key"), "certificate", cert, "devices", unit.get("devices"))),
        Json.write(Json.object("key", key, "certificate", other.get("certificate"), "devices", unit.get("devices")))};
    for (String loss : losses) {
      storage.values.put(Identity.KEY, loss);
      api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
      check(!api.identity().fp.equals(fp) && api.identity().fp.matches("[0-9a-f]{64}"), "a lost key or certificate means a new identity");
      same(401, call("GET", "/v1/state", null).status, "and an empty device list");
      same("[]", Json.write(Json.map(Json.parse(storage.values.get(Identity.KEY))).get("devices")), "which is stored empty");
    }

    storage.values.put(Identity.KEY, Json.write(Json.object("key", key, "certificate", cert, "devices", "nonsense")));
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same(fp, api.identity().fp, "an unreadable device list alone keeps the identity");
    same(401, call("GET", "/v1/state", null).status, "but pairs nobody");
    storage.values.put(Identity.KEY, Json.write(Json.object("key", key, "certificate", cert, "devices",
        java.util.Arrays.asList(Json.object("id", "d1", "name", "Old", "hash", "not a hash")))));
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same("[]", Json.write(Json.map(Json.parse(api.pairingStatus(0, false, ""))).get("devices")), "a device row without a hash is dropped");
    List<Object> mixed = new ArrayList<>(Json.list(unit.get("devices")));
    mixed.add(0, Json.object("id", "d1", "name", "Old", "hash", "not a hash"));
    mixed.add("nonsense");
    mixed.add(Json.object("name", "No id", "hash", repeat("ab", 32)));
    storage.values.put(Identity.KEY, Json.write(Json.object("key", key, "certificate", cert, "devices", mixed)));
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same(200, call("GET", "/v1/state", null).status, "a damaged device row does not unpair the sound ones");
    same(1, Json.list(Json.map(Json.parse(api.pairingStatus(0, false, ""))).get("devices")).size(), "only the sound device is listed");

    Fakes.Storage upgraded = new Fakes.Storage();
    String oldToken = repeat("ab", 32);
    upgraded.values.put("frameId", "0b4f8a52-7f7e-4c44-9d0b-3f1f0a0c1d2e");
    upgraded.values.put("devices", Json.write(java.util.Arrays.asList(Json.object("id", "d1", "name", "Old phone", "pairedAt", "2026-10-01T00:00:00Z",
        "hash", Digests.sha256(oldToken.getBytes(StandardCharsets.US_ASCII))))));
    upgraded.values.put("household", storage.values.get("household"));
    LocalApi after = new LocalApi(upgraded, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    check(upgraded.values.get("devices") == null && upgraded.values.get("frameId") == null, "an upgrade erases the first version's devices and id");
    same(401, Fakes.inMemory(after, Fakes.json("GET", "/v1/state", oldToken, null)).status, "a first-version token no longer works");
    same("[]", Json.write(Json.map(Json.parse(after.pairingStatus(0, false, ""))).get("devices")), "the upgraded frame lists no devices");
    check(after.frameId().matches("[0-9a-f]{32}"), "and takes its id from the certificate");
    same(storage.values.get("household"), upgraded.values.get("household"), "household data is untouched by the upgrade");
  }

  static void persistence() throws Exception {
    fresh();
    call("POST", "/v1/people", "{\"name\":\"Maya\",\"color\":\"#00A36C\"}");
    call("POST", "/v1/chores", "{\"title\":\"Make bed\",\"emoji\":\"\ud83d\udecf\ufe0f\",\"personId\":\"p1\",\"days\":[1,2]}");
    call("PUT", "/v1/chores/c2/done", "{\"date\":\"2026-10-11\",\"done\":true}");
    call("POST", "/v1/shopping", "{\"name\":\"Milk \\\"2%\\\"\",\"qty\":2,\"note\":\"caf\u00e9\"}");
    call("PUT", "/v1/settings/location", "{\"name\":\"Denver\",\"latitude\":39.74,\"longitude\":-104.99,\"timezone\":\"America/Denver\"}");
    call("PUT", "/v1/settings/appearance", "{\"palette\":\"sage\",\"mode\":\"dark\"}");
    String before = call("GET", "/v1/state", null).text();
    String frameId = api.frameId();
    String devices = call("GET", "/v1/devices", null).text();

    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same(before, call("GET", "/v1/state", null).text(), "state survives a restart byte for byte");
    same(frameId, api.frameId(), "frame id survives a restart");
    same(devices, call("GET", "/v1/devices", null).text(), "paired devices survive a restart");
    Map<String, Object> next = row(call("POST", "/v1/people", "{\"name\":\"Noor\",\"color\":\"#123456\"}"), "person");
    same("p4", next.get("id"), "ids are never reused after a restart");
    same(7L, rev(), "rev continues after a restart");

    storage.values.put("household", "{broken");
    storage.values.put(Identity.KEY, "{broken");
    storage.values.put("settings", "[]");
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same(401, call("GET", "/v1/state", null).status, "unreadable device storage pairs nobody");
    token = null;
    events = new Fakes.Recorder();
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), events);
    token = pair("Recovered");
    Map<String, Object> recovered = state();
    same(0L, recovered.get("rev"), "unreadable household storage starts empty");
    same("{\"location\":null,\"appearance\":{\"palette\":\"linen\",\"mode\":\"auto\"},\"icloudAlbum\":null}", Json.write(recovered.get("settings")), "unreadable settings fall back to defaults");
    check(api.frameId().matches("[0-9a-f]{32}") && !api.frameId().equals(frameId), "an unreadable identity is replaced");

    HouseholdStore store = new HouseholdStore(new Fakes.Storage());
    same(1L, store.touch(), "touch is one revision");
    same("2026-10-11", FrameTime.day(START, TimeZone.getTimeZone("UTC")), "day in UTC");
    same("2026-10-10", FrameTime.day(START, TimeZone.getTimeZone("America/Denver")), "day in the frame zone");
    same("2026-03-01", FrameTime.shift("2026-02-28", 1), "shift over a month end");
    same("2025-12-31", FrameTime.shift("2026-01-13", -13), "shift over a year end");
    check(FrameTime.validDay("2028-02-29") && !FrameTime.validDay("2026-02-29") && !FrameTime.validDay("2026-13-01") && !FrameTime.validDay(null), "calendar days are validated");
    check(Digests.same("abc", "abc") && !Digests.same("abc", "abd") && !Digests.same("abc", "abcd") && !Digests.same("", "a"), "constant time comparison");
    same("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Digests.sha256(new byte[0]), "sha-256 of nothing");
  }

  static int statusFor(String host) throws Exception {
    String line = host == null ? "" : "Host: " + host + "\r\n";
    return Fakes.inMemory(api, ("GET /v2/info HTTP/1.1\r\n" + line + "\r\n").getBytes(StandardCharsets.ISO_8859_1)).status;
  }

  static void changedWhileUnobserved() throws Exception {
    fresh();
    long seen = rev();
    calendars.add("Family", "#2D5BFF", FEED);
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    Fakes.Reply polled = call("GET", "/v1/state?since=" + seen, null);
    same(200, polled.status, "a calendar added on the frame just before a restart is not hidden behind 304");
    same(1, Json.list(polled.object().get("calendars")).size(), "and the phone receives it");
    same(304, call("GET", "/v1/state?since=" + rev(), null).status, "after which nothing is new");
    api = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same(304, call("GET", "/v1/state?since=" + polled.object().get("rev"), null).status, "and a restart with nothing new changes nothing");
  }

  static void hardening() throws Exception {
    fresh();
    for (String host : new String[] {"192.168.1.20", "192.168.1.20:8765", "10.0.0.7:1", "[fe80::1]:8765", "[fd00::2]", "[fe80::1%25wlan0]:8765",
        "skylit.local", "Skylit-Frame.local:8765", "android-2.local.", "frame.home.local"}) {
      same(200, statusFor(host), "addressed as " + host);
    }
    for (String host : new String[] {null, "", "frame", "localhost", "localhost:8765", "evil.test", "evil.test:8765", "192.168.1.20.evil.test",
        "skylit.local.evil.test", "192.168.1.20:8765@evil.test", "evil.test@192.168.1.20", "http://192.168.1.20", "skylit.local/x", "[::1",
        "192.168.1.20:", "192.168.1.20:123456", "[evil.test]", ".local", "a b.local", "192.168.1", "local"}) {
      same(400, statusFor(host), "refused host " + host);
    }
    same("bad_request", Fakes.inMemory(api, "GET /v2/info HTTP/1.1\r\nHost: evil.test\r\n\r\n".getBytes(StandardCharsets.ISO_8859_1)).error(), "host refusal slug");
    same(400, Fakes.inMemory(api, ("GET /v1/state HTTP/1.1\r\nHost: evil.test\r\nAuthorization: Bearer " + token + "\r\n\r\n").getBytes(StandardCharsets.ISO_8859_1)).status,
        "a valid token does not excuse a rebound host");

    token = pair("Clean phone");
    String[] unsafe = {"\\ud83d", "\\ude00", "\\ude00\\ud83d", "a\\ud83db", "\\ufffe", "\\uffff", "\\u202e", "\\u202a", "\\u202b", "\\u202c", "\\u202d",
        "\\u2066", "\\u2067", "\\u2068", "\\u2069", "\\u0000", "\\u001b", "\\u007f", "\\u0085"};
    for (String text : unsafe) {
      String value = "Ma" + text + "ya";
      same(400, call("POST", "/v1/people", "{\"name\":\"" + value + "\",\"color\":\"#00A36C\"}").status, "person name with " + text);
      same(400, call("POST", "/v1/chores", "{\"title\":\"" + value + "\"}").status, "chore title with " + text);
      same(400, call("POST", "/v1/chores", "{\"title\":\"Bed\",\"emoji\":\"x" + text + "y\"}").status, "chore emoji with " + text);
      same(400, call("POST", "/v1/shopping", "{\"name\":\"" + value + "\"}").status, "item name with " + text);
      same(400, call("POST", "/v1/shopping", "{\"name\":\"Milk\",\"note\":\"" + value + "\"}").status, "item note with " + text);
      same(400, call("PUT", "/v1/settings/location", "{\"name\":\"" + value + "\",\"latitude\":1,\"longitude\":1}").status, "city with " + text);
      same(400, call("POST", "/v1/calendars", "{\"name\":\"" + value + "\",\"color\":\"#2D5BFF\",\"url\":\"" + FEED + "\"}").status, "calendar name with " + text);
      same(Boolean.FALSE, mutate("{\"op\":\"item.add\",\"name\":\"" + value + "\"}").get("ok"), "bridge item with " + text);
      check(!api.reportSettings("{\"location\":{\"name\":\"" + value + "\",\"latitude\":1,\"longitude\":1}}"), "reported city with " + text);
    }
    same(400, Fakes.inMemory(api, Fakes.request("POST", "/v1/people", token, "application/json",
        new byte[] {'{', '"', 'n', 'a', 'm', 'e', '"', ':', '"', (byte) 0xED, (byte) 0xA0, (byte) 0x80, '"', ',', '"', 'c', 'o', 'l', 'o', 'r', '"', ':', '"', '#', '0', '0', 'A', '3', '6', 'C', '"', '}'})).status,
        "a raw encoded surrogate is not stored either");
    same(0L, rev(), "nothing unsafe was stored");
    same(200, call("POST", "/v1/people", "{\"name\":\"Ma\\ud83d\\ude00ya שלום\",\"color\":\"#00A36C\"}").status, "paired surrogates and right-to-left letters are fine");
    same("ab", Fields.tidy("a\ud83d‮b￿", 80), "tidy drops what cannot be shown");
    String cut = Fields.tidy(repeat("a", 79) + "😀😀", 80);
    check(cut.length() == 81 && cut.endsWith("😀"), "tidy cuts between code points");
    same("x", Fields.tidy("  x  ", 80), "tidy trims");

    String separators = "f(\"a" + (char) 0x2028 + "b" + (char) 0x2029 + "c\")";
    same("f(\"a\\u2028b\\u2029c\")", Json.scriptSafe(separators), "line separators are escaped before a script is evaluated");
    same("window.X&&window.X.receive({\"a\":1})", Json.scriptSafe("window.X&&window.X.receive({\"a\":1})"), "ordinary scripts are unchanged");
    same("a" + (char) 0x2028 + "b", Json.parse(Json.scriptSafe("\"a" + (char) 0x2028 + "b\"")), "an escaped script still carries the same text");
    try {
      Json.parse("[" + repeat("0,", Json.MAX_VALUES) + "0]");
      throw new AssertionError("an enormous value count was parsed");
    } catch (Json.Malformed expected) {
      checks++;
    }
    same(100001, Json.list(Json.parse("[" + repeat("0,", 100000) + "0]")).size(), "ordinary large lists still parse");

    check(PhotoPolicy.imageSize(8000, 6000) && PhotoPolicy.imageSize(4032, 3024) && PhotoPolicy.imageSize(320, 240), "pictures up to fifty megapixels decode");
    check(!PhotoPolicy.imageSize(10000, 6000) && !PhotoPolicy.imageSize(20000, 20000) && !PhotoPolicy.imageSize(7072, 7072), "larger pictures are refused before decoding");
    check(!PhotoPolicy.imageSize(46341, 46341) && !PhotoPolicy.imageSize(0, 0) && !PhotoPolicy.imageSize(-1, 5000), "overflowing and empty sizes are refused");
    check(PhotoPolicy.jpeg(Fakes.jpeg(1, 100)) && PhotoPolicy.jpeg(Fakes.picture(1)), "jpeg magic accepted");
    byte[][] others = {null, {}, {(byte) 0xFF, (byte) 0xD8}, {(byte) 0x89, 'P', 'N', 'G', 13, 10, 26, 10}, {'G', 'I', 'F', '8', '9', 'a'},
        {'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'E', 'B', 'P'}, {'B', 'M', 0, 0}, {0, 0, 0, 24, 'f', 't', 'y', 'p', 'h', 'e', 'i', 'c'}, {'<', 's', 'v', 'g', '>'}};
    for (byte[] other : others) check(!PhotoPolicy.jpeg(other), "non-jpeg magic refused");
  }

  static void manyDevices() throws Exception {
    fresh();
    api.pairingRevokeAll();
    final List<String> tokens = new java.util.ArrayList<>();
    for (int device = 0; device < Pairing.MAX_DEVICES; device++) tokens.add(pair("Family phone " + device));
    same(Pairing.MAX_DEVICES, new java.util.HashSet<>(tokens).size(), "twenty devices hold twenty different tokens");
    same(Pairing.MAX_DEVICES, send("GET", "/v1/devices", tokens.get(0), null).list().size(), "twenty devices are listed");
    check(api.pairingOpen().contains("\"ok\":false"), "the frame opens no window for a twenty-first device");
    Fakes.Reply full = new Fakes.Phone().start(wire, "Phone 21");
    same(409, full.status, "and the twenty-first pairing is refused");
    same("conflict", full.error(), "with the conflict slug");
    for (String each : tokens) same(200, send("GET", "/v1/state", each, null).status, "every paired device still works after the refusal");

    long rev = 0;
    for (int writer = 0; writer < tokens.size(); writer++) {
      Fakes.Reply written = send("POST", "/v1/shopping", tokens.get(writer), "{\"name\":\"From device " + writer + "\"}");
      same(rev + 1, written.object().get("rev"), "a change by device " + writer + " is exactly one revision");
      for (int reader = 0; reader < tokens.size(); reader++) {
        Fakes.Reply seen = send("GET", "/v1/state?since=" + rev, tokens.get(reader), null);
        check(seen.status == 200 && seen.object().get("rev").equals(rev + 1) && seen.text().contains("From device " + writer + "\""),
            "device " + reader + " sees the change by device " + writer);
        same(304, send("GET", "/v1/state?since=" + (rev + 1), tokens.get(reader), null).status, "and nothing more");
      }
      rev++;
    }
    same(200, send("PATCH", "/v1/shopping/s1", tokens.get(5), "{\"done\":true}").status, "one device edits another device's item");
    same(Boolean.TRUE, Json.map(Json.list(send("GET", "/v1/state", tokens.get(9), null).object().get("shopping")).get(0)).get("done"), "and a third sees the edit");
    rev++;

    final long before = rev;
    final int devices = 6;
    final int each = 20;
    final java.util.Set<Object> ids = java.util.Collections.synchronizedSet(new java.util.HashSet<Object>());
    final java.util.Set<Object> revisions = java.util.Collections.synchronizedSet(new java.util.TreeSet<Object>());
    final List<Throwable> failures = java.util.Collections.synchronizedList(new java.util.ArrayList<Throwable>());
    List<Thread> phones = new java.util.ArrayList<>();
    for (int device = 0; device < devices; device++) {
      final String bearer = tokens.get(device);
      final int number = device;
      Thread phone = new Thread(new Runnable() {
        @Override public void run() {
          try {
            for (int write = 0; write < each; write++) {
              String body = write % 2 == 0 ? "{\"name\":\"Racing " + number + "-" + write + "\"}" : "{\"title\":\"Racing " + number + "-" + write + "\"}";
              Fakes.Reply reply = send("POST", write % 2 == 0 ? "/v1/shopping" : "/v1/chores", bearer, body);
              if (reply.status != 200) throw new AssertionError("racing write returned " + reply.status);
              ids.add(Json.map(reply.object().get(write % 2 == 0 ? "item" : "chore")).get("id"));
              revisions.add(reply.object().get("rev"));
            }
          } catch (Throwable failed) {
            failures.add(failed);
          }
        }
      });
      phones.add(phone);
      phone.start();
    }
    for (Thread phone : phones) phone.join();
    same(0, failures.size(), "no racing write fails " + failures);
    same(devices * each, ids.size(), "racing writes never share an id");
    same(devices * each, revisions.size(), "racing writes never share a revision");
    same(before + 1, ((java.util.TreeSet<Object>) new java.util.TreeSet<>(revisions)).first(), "racing revisions start right after the last one");
    same(before + devices * each, ((java.util.TreeSet<Object>) new java.util.TreeSet<>(revisions)).last(), "and leave no gap");
    Map<String, Object> settled = send("GET", "/v1/state", tokens.get(0), null).object();
    same(before + devices * each, settled.get("rev"), "the frame ends on the last revision");
    same(20 + devices * each / 2, Json.list(settled.get("shopping")).size(), "no shopping write is lost");
    same(devices * each / 2, Json.list(settled.get("chores")).size(), "no chore write is lost");
    same(settled, send("GET", "/v1/state", tokens.get(19), null).object(), "every device reads the same state");
    LocalApi reopened = new LocalApi(storage, clock, uptime, calendars, photos, sync(events), new Fakes.Recorder());
    same(Json.write(settled), Fakes.inMemory(reopened, Fakes.json("GET", "/v1/state", tokens.get(3), null)).text(), "and it is what was saved");

    String victim = tokens.get(7);
    String victimId = null;
    int position = 0;
    for (Object device : send("GET", "/v1/devices", tokens.get(0), null).list()) {
      if (position++ == 7) victimId = (String) Json.map(device).get("id");
    }
    same(403, send("DELETE", "/v1/devices/" + victimId, tokens.get(0), null).status, "one device cannot revoke another");
    same(200, send("GET", "/v1/state", victim, null).status, "which keeps working");
    check(api.pairingRevoke(victimId), "the frame revokes it");
    same(401, send("GET", "/v1/state", victim, null).status, "the revoked token stops");
    for (int device = 0; device < tokens.size(); device++) {
      if (device != 7) same(200, send("GET", "/v1/state", tokens.get(device), null).status, "device " + device + " is unaffected by the revocation");
    }
    String renewed = pair("Family phone 7");
    check(renewed.matches("[0-9a-f]{64}") && !tokens.contains(renewed), "re-pairing issues a token nobody held before");
    same(200, send("GET", "/v1/state", renewed, null).status, "the new token works");
    same(401, send("GET", "/v1/state", victim, null).status, "the old token stays dead");
    same(Pairing.MAX_DEVICES, send("GET", "/v1/devices", renewed, null).list().size(), "the household is back to twenty devices");
  }

  public static void main(String[] args) throws Exception {
    TimeZone.setDefault(TimeZone.getTimeZone("UTC"));
    json();
    http();
    pairing();
    tokens();
    household();
    limits();
    unsaved();
    clockless();
    blanks();
    invisible();
    damaged();
    bridge();
    settings();
    settingsTogether();
    calendarsOverHttp();
    photosOverHttp();
    identity();
    persistence();
    changedWhileUnobserved();
    hardening();
    manyDevices();
    System.out.println("LocalApi: " + checks + " checks passed");
  }
}
