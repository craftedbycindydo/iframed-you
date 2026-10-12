package com.wesbos.homehq;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

public final class TccTest {
  static final long START = 1791741600000L;
  static final String USER = "frame@example.com";
  static final String PASS = "frame-password";
  static int checks;

  static final class Clock implements FrameTime.Clock, FrameTime.Uptime {
    long now = START;
    long jumped;

    @Override public long now() {
      return now + jumped;
    }

    @Override public long millis() {
      return now - START + 5000L;
    }
  }

  static final class Storage implements KeyValue {
    final Map<String, String> values = new HashMap<>();

    @Override public String get(String key) {
      return values.get(key);
    }

    @Override public boolean put(String key, String value) {
      values.put(key, value);
      return true;
    }
  }

  static final class Vault implements TccSync.Secrets {
    String[] saved;

    @Override public String[] load() {
      return saved;
    }

    @Override public void save(String username, String password) {
      saved = new String[] {username, password};
    }

    @Override public void clear() {
      saved = null;
    }
  }

  static final class Call {
    final String method;
    final String path;
    final Map<String, String> headers;
    final String body;

    Call(String method, String path, Map<String, String> headers, String body) {
      this.method = method;
      this.path = path;
      this.headers = new LinkedHashMap<>(headers);
      this.body = body;
    }
  }

  static final class FakeTcc implements TccClient.Transport {
    final List<Call> calls = new ArrayList<>();
    final List<Long> order = new ArrayList<>();
    final Map<Long, String> names = new HashMap<>();
    final Map<Long, Map<String, Object>> payloads = new HashMap<>();
    final Set<String> sessions = new HashSet<>();
    final List<Object> glitches = new ArrayList<>();
    String password = PASS;
    String login = "normal";
    String redirect;
    boolean unreachable;
    boolean rejects;
    int issued;

    void add(long id, String name, Map<String, Object> ui, boolean fanRunning) {
      order.add(id);
      names.put(id, name);
      payloads.put(id, Json.object("success", true, "deviceLive", true, "communicationLost", false, "latestData",
          Json.object("uiData", ui, "hasFan", true, "fanData", Json.object("fanMode", 0L, "fanIsRunning", fanRunning), "drData", Json.object())));
    }

    Map<String, Object> ui(long id) {
      return Json.map(Json.map(payloads.get(id).get("latestData")).get("uiData"));
    }

    int count(String method, String prefix) {
      int count = 0;
      for (Call call : calls) if (call.method.equals(method) && call.path.startsWith(prefix)) count++;
      return count;
    }

    int logins() {
      int count = 0;
      for (Call call : calls) if (call.method.equals("POST") && call.path.equals("/portal")) count++;
      return count;
    }

    Call last() {
      return calls.get(calls.size() - 1);
    }

    boolean signedIn(Call call) {
      String header = call.headers.get("Cookie");
      if (header == null) return false;
      for (String pair : header.split("; ")) {
        if (pair.startsWith(TccClient.AUTH_COOKIE + "=") && sessions.contains(pair.substring(TccClient.AUTH_COOKIE.length() + 1))) return true;
      }
      return false;
    }

    static TccClient.Reply html(int status, String text, String location, String... cookies) {
      return new TccClient.Reply(status, "text/html; charset=utf-8", location, Arrays.asList(cookies), text);
    }

    static TccClient.Reply json(Object value) {
      return new TccClient.Reply(200, "application/json; charset=utf-8", null, null, Json.write(value));
    }

    @Override public synchronized TccClient.Reply send(String method, String path, Map<String, String> headers, String body) throws IOException {
      Call call = new Call(method, path, headers, body);
      calls.add(call);
      if (unreachable) throw new IOException("offline");
      String bare = path.split("\\?", 2)[0];
      if (method.equals("POST") && bare.equals("/portal")) return login(call);
      if (method.equals("GET") && "redirect".equals(login) && redirect.startsWith("/portal/") && redirect.startsWith(bare)) return html(302, "", redirect);
      if (method.equals("GET") && (bare.equals("/portal") || bare.equals("/portal/"))) {
        if (call.headers.get("Cookie") == null) {
          return html(200, "<html>Sign in</html>", null, TccClient.AUTH_COOKIE + "=; expires=Mon, 11-Oct-1999 22:00:00 GMT; path=/",
              "ASP.NET_SessionId=visit; path=/; secure; HttpOnly", "TrueHomeCheckCookie=; path=/; secure; HttpOnly");
        }
        if ("emptyCookie".equals(login)) return html(200, "<html>Sign in</html>", null, TccClient.AUTH_COOKIE + "=; expires=Mon, 11-Oct-1999 22:00:00 GMT; path=/");
        return signedIn(call) ? html(302, "", "/portal/4242/Zones") : html(401, "", null);
      }
      if (method.equals("GET") && bare.equals("/portal/4242/Zones")) return signedIn(call) ? html(200, "<html>Zones</html>", null) : html(401, "", null);
      if (method.equals("POST") && bare.equals("/portal/Account/LogOff")) {
        sessions.clear();
        return html(200, "", null);
      }
      if (!glitches.isEmpty()) {
        Object glitch = glitches.remove(0);
        if (glitch instanceof Integer) return html((Integer) glitch, "<html>Error</html>", null);
        if ("html".equals(glitch)) return html(200, "<html>Maintenance</html>", null);
        if ("badjson".equals(glitch)) return new TccClient.Reply(200, "application/json", null, null, "{nope");
        return html(302, "", (String) glitch);
      }
      if (!signedIn(call)) return html(401, "", null);
      if (method.equals("POST") && bare.equals("/portal/Location/GetLocationListData/")) {
        List<Object> devices = new ArrayList<>();
        for (Long id : order) devices.add(Json.object("DeviceID", id, "Name", names.get(id), "MacID", "00D02D" + id));
        List<Object> page = new ArrayList<>();
        if (path.contains("page=1&")) page.add(Json.object("LocationID", 4242L, "Devices", devices));
        return json(page);
      }
      if (method.equals("GET") && bare.startsWith("/portal/Device/CheckDataSession/")) {
        Map<String, Object> payload = payloads.get(Long.valueOf(bare.substring(bare.lastIndexOf('/') + 1)));
        if (payload == null) return html(404, "", null);
        return new TccClient.Reply(200, "application/json; charset=utf-8", null,
            Arrays.asList(TccClient.AUTH_COOKIE + "=" + sessions.iterator().next() + "; expires=Sun, 11-Oct-2026 25:61:00 GMT; path=/; secure; HttpOnly"),
            Json.write(payload));
      }
      if (method.equals("POST") && bare.equals("/portal/Device/SubmitControlScreenChanges")) {
        if (rejects) return json(Json.object("success", 0L));
        try {
          Map<String, Object> change = Json.map(Json.parse(body));
          Map<String, Object> ui = ui(((Number) change.get("DeviceID")).longValue());
          for (String key : new String[] {"HeatSetpoint", "CoolSetpoint", "StatusHeat", "StatusCool", "HeatNextPeriod", "CoolNextPeriod"}) {
            if (change.get(key) != null) ui.put(key, change.get(key));
          }
          if (change.get("SystemSwitch") != null) ui.put("SystemSwitchPosition", change.get("SystemSwitch"));
          return json(Json.object("success", 1L));
        } catch (Json.Malformed | RuntimeException bad) {
          return html(500, "", null);
        }
      }
      return html(404, "", null);
    }

    private TccClient.Reply login(Call call) throws IOException {
      Map<String, String> fields = new HashMap<>();
      for (String pair : call.body.split("&")) {
        String[] parts = pair.split("=", 2);
        fields.put(parts[0], URLDecoder.decode(parts[1], "UTF-8"));
      }
      if ("tooMany".equals(login)) return html(302, "", "/portal/Account/TooManyAttempts");
      if ("unauthorized".equals(login)) return html(401, "", null);
      if ("redirect".equals(login)) return html(302, "", redirect);
      if ("emptyCookie".equals(login)) return html(200, "<html>Sign in</html>", null);
      String jar = call.headers.get("Cookie");
      if (jar == null || !jar.contains("ASP.NET_SessionId=") || !jar.contains("TrueHomeCheckCookie=")) {
        return html(200, "<html>This site will not operate without Cookies enabled.</html>", null);
      }
      if (!USER.equals(fields.get("UserName")) || !password.equals(fields.get("Password"))) {
        return html(200, "<html><div>The email or password provided is incorrect.</div></html>", null);
      }
      String token = "SESSION" + (++issued);
      sessions.clear();
      sessions.add(token);
      return html(302, "", "/portal/", TccClient.AUTH_COOKIE + "=" + token + "; expires=Sun, 11-Oct-2026 25:61:00 GMT; path=/; secure; HttpOnly",
          "ASP.NET_SessionId=abc" + issued + "; path=/; HttpOnly");
    }
  }

  static FakeTcc server;
  static Clock clock;
  static Storage storage;
  static TccClient client;

  static void check(boolean value, String message) {
    if (!value) throw new AssertionError(message);
    checks++;
  }

  static void same(Object expected, Object actual, String message) {
    check(expected == null ? actual == null : expected.equals(actual), message + ": expected " + expected + " but was " + actual);
  }

  interface Action {
    void run() throws Exception;
  }

  static TccClient.Problem fails(String code, Action action, String message) throws Exception {
    try {
      action.run();
    } catch (TccClient.Problem problem) {
      same(code, problem.code, message);
      return problem;
    }
    throw new AssertionError(message + ": nothing was thrown");
  }

  static Map<String, Object> ui(long mode, double indoor, double heat, double cool, long status, String units) {
    boolean celsius = "C".equals(units);
    return Json.object("DispTemperature", indoor, "DisplayUnits", units, "HeatSetpoint", heat, "CoolSetpoint", cool,
        "HeatLowerSetptLimit", celsius ? 4.5 : 40.0, "HeatUpperSetptLimit", celsius ? 32.0 : 90.0,
        "CoolLowerSetptLimit", celsius ? 10.0 : 50.0, "CoolUpperSetptLimit", celsius ? 37.0 : 99.0, "Deadband", 0.0,
        "SystemSwitchPosition", mode, "SwitchHeatAllowed", true, "SwitchCoolAllowed", true, "SwitchOffAllowed", true, "SwitchAutoAllowed", false,
        "SwitchEmergencyHeatAllowed", false, "StatusHeat", status, "StatusCool", status, "HeatNextPeriod", 72L, "CoolNextPeriod", 72L,
        "EquipmentOutputStatus", mode == 1 ? 1L : 0L, "IndoorHumidity", 41L, "IndoorHumiditySensorAvailable", true, "IndoorHumiditySensorNotFault", true,
        "OutdoorTemperature", 58L, "OutdoorTemperatureAvailable", true, "OutdoorHumidity", 62L, "OutdoorHumidityAvailable", true);
  }

  static void fresh() {
    server = new FakeTcc();
    server.add(1001, "Level-0", ui(1, 69, 70, 78, 2, "F"), true);
    server.add(1002, "level-1", ui(3, 74, 62, 76, 1, "F"), false);
    clock = new Clock();
    storage = new Storage();
    client = new TccClient(server, storage, clock, clock);
  }

  static TccClient.Device device(long id) {
    return new TccClient.Device(id, 4242, id == 1001 ? "Level-0" : "level-1", null);
  }

  static void login() throws Exception {
    fresh();
    client.signIn(USER, PASS);
    same("GET", server.calls.get(0).method, "the sign-in page is loaded first");
    check(server.calls.get(0).headers.get("Cookie") == null, "no cookie before the first visit");
    Call post = server.calls.get(1);
    same("POST", post.method, "login is a POST");
    same("/portal", post.path, "login path carries no query");
    same("application/x-www-form-urlencoded", post.headers.get("Content-Type"), "form content type");
    same("XMLHttpRequest", post.headers.get("X-Requested-With"), "ajax header");
    same("ASP.NET_SessionId=visit; TrueHomeCheckCookie=", post.headers.get("Cookie"), "visit cookies sent with login");
    check(post.body.contains("UserName=frame%40example.com") && post.body.contains("Password=frame-password") && post.body.contains("RememberMe=false")
        && post.body.startsWith("timeOffset="), "form fields");
    same(6, server.calls.size(), "login follows its own redirects and confirms");
    same("GET", server.calls.get(2).method, "redirect followed with GET");
    same("ASP.NET_SessionId=abc1; TrueHomeCheckCookie=; .ASPXAUTH_TRUEHOME=SESSION1", server.calls.get(2).headers.get("Cookie"), "cookies with malformed expiry are kept");
    check(client.hasSession(), "session held");
    client.read(device(1001));
    same(1, server.logins(), "one login for many calls");
    same("ASP.NET_SessionId=abc1; TrueHomeCheckCookie=; .ASPXAUTH_TRUEHOME=SESSION1", server.last().headers.get("Cookie"), "cookie sent on data calls");

    fresh();
    for (int attempt = 1; attempt <= 3; attempt++) {
      fails("bad_credentials", new Action() {
        @Override public void run() throws Exception {
          client.signIn(USER, "nope");
        }
      }, "wrong password " + attempt);
    }
    same(3, client.failures(), "three failures counted");
    same(START + 600000L, client.lockedUntil(), "locked for ten minutes");
    final int before = server.calls.size();
    TccClient.Problem locked = fails("locked", new Action() {
      @Override public void run() throws Exception {
        client.signIn(USER, PASS);
      }
    }, "fourth attempt is refused locally");
    same(START + 600000L, locked.until, "lock end is reported");
    same(before, server.calls.size(), "nothing is sent while locked");
    check(!storage.get("tcc.guard").contains("nope") && !storage.get("tcc.guard").contains(USER), "guard record holds no secrets");

    final TccClient relaunched = new TccClient(server, storage, clock, clock);
    fails("locked", new Action() {
      @Override public void run() throws Exception {
        relaunched.signIn(USER, PASS);
      }
    }, "lock survives a restart");
    same(before, server.calls.size(), "still nothing sent");
    clock.now += 600001L;
    fails("bad_credentials", new Action() {
      @Override public void run() throws Exception {
        relaunched.signIn(USER, "nope");
      }
    }, "one more failure after the lock");
    same(clock.now + 1200000L, relaunched.lockedUntil(), "lock doubles");
    clock.now += 1200001L;
    relaunched.signIn(USER, PASS);
    same(0, relaunched.failures(), "success clears the count");
    same(0L, new TccClient(server, storage, clock, clock).lockedUntil(), "cleared state is persisted");

    fresh();
    server.login = "tooMany";
    fails("locked", new Action() {
      @Override public void run() throws Exception {
        client.signIn(USER, PASS);
      }
    }, "throttle redirect locks at once");
    same(2, server.calls.size(), "throttle page is not fetched");
    same(START + 600000L, client.lockedUntil(), "throttle lock length");

    fresh();
    server.login = "emptyCookie";
    fails("login_failed", new Action() {
      @Override public void run() throws Exception {
        client.signIn(USER, PASS);
      }
    }, "empty auth cookie");
    server.login = "unauthorized";
    fails("bad_credentials", new Action() {
      @Override public void run() throws Exception {
        client.signIn(USER, PASS);
      }
    }, "401 on login");
    same(2, client.failures(), "both count as failures");

    fresh();
    fails("signed_out", new Action() {
      @Override public void run() throws Exception {
        client.devices();
      }
    }, "no credentials");
    same(0, server.calls.size(), "nothing sent without credentials");
  }

  static void redirects() throws Exception {
    fresh();
    server.login = "redirect";
    String[] foreign = {"https://evil.example/portal", "http://mytotalconnectcomfort.com/portal", "https://mytotalconnectcomfort.com.evil.example/",
        "https://user@mytotalconnectcomfort.com/portal", "https://mytotalconnectcomfort.com:8443/portal", "//evil.example/x", "https://evil.example\\@mytotalconnectcomfort.com/",
        "javascript:alert(1)"};
    for (String target : foreign) {
      server.redirect = target;
      fails("foreign_host", new Action() {
        @Override public void run() throws Exception {
          client.signIn(USER, PASS);
        }
      }, "refused redirect to " + target);
    }
    same(foreign.length * 2, server.calls.size(), "refused redirects are never followed");
    same(0, client.failures(), "a refused redirect is not a login failure");
    same("/portal/1/Zones?x=1", TccClient.sameOrigin("/portal/1/Zones?x=1", "/portal"), "relative redirect");
    same("/portal/Home", TccClient.sameOrigin("https://mytotalconnectcomfort.com/portal/Home", "/portal"), "absolute same-host redirect");
    same("/portal/Zones", TccClient.sameOrigin("Zones", "/portal/"), "document-relative redirect");

    server.redirect = "/portal/Loop";
    fails("unavailable", new Action() {
      @Override public void run() throws Exception {
        client.signIn(USER, PASS);
      }
    }, "redirect loop ends");
    same(foreign.length * 2 + 6, server.calls.size(), "loop is bounded");
    server.redirect = "/portal/Error?aspxerrorpath=/portal";
    fails("unavailable", new Action() {
      @Override public void run() throws Exception {
        client.signIn(USER, PASS);
      }
    }, "error page redirect");
  }

  static void sessions() throws Exception {
    fresh();
    client.signIn(USER, PASS);
    clock.now += 601000L;
    server.sessions.clear();
    same("Level-0", client.read(device(1001)).name, "read after re-login");
    same(2, server.logins(), "one re-login");
    same("ASP.NET_SessionId=abc2; TrueHomeCheckCookie=; .ASPXAUTH_TRUEHOME=SESSION2", server.last().headers.get("Cookie"), "new cookie replaces the old");

    fresh();
    client.signIn(USER, PASS);
    clock.now += 120000L;
    server.sessions.clear();
    for (int i = 0; i < 4; i++) {
      fails("session_expired", new Action() {
        @Override public void run() throws Exception {
          client.read(device(1001));
        }
      }, "re-login throttled " + i);
      clock.now += 60000L;
    }
    same(1, server.logins(), "no login inside ten minutes");
    clock.now += 300000L;
    client.read(device(1001));
    same(2, server.logins(), "login allowed after ten minutes");

    fresh();
    client.credentials(USER, PASS);
    same(2, client.devices().size(), "first use logs in by itself");
    same(1, server.logins(), "exactly once");
    client.signOut();
    same("/portal/Account/LogOff", server.last().path, "log off is posted");
    check(!client.hasSession() && !client.hasCredentials(), "signed out");
  }

  static void reading() throws Exception {
    fresh();
    client.signIn(USER, PASS);
    List<TccClient.Device> devices = client.devices();
    same(2, devices.size(), "two thermostats");
    same(1001L, devices.get(0).id, "device id");
    same("Level-0", devices.get(0).name, "device name");
    same(4242L, devices.get(0).location, "location id");
    same("00D02D1002", devices.get(1).mac, "mac id");
    same(2, server.count("POST", "/portal/Location/GetLocationListData/?page="), "paging stops at the first empty page");
    check(server.calls.get(6).path.equals("/portal/Location/GetLocationListData/?page=1&filter=") && server.calls.get(6).body == null, "listing call shape");

    TccClient.State heat = client.read(devices.get(0));
    check(server.last().method.equals("GET") && server.last().path.startsWith("/portal/Device/CheckDataSession/1001?_="), "read call shape");
    long first = Long.parseLong(server.last().path.split("_=")[1]);
    TccClient.State cool = client.read(devices.get(1));
    same(first + 1, Long.parseLong(server.last().path.split("_=")[1]), "cache counter increases");
    check(heat.online, "online");
    same("F", heat.units, "units");
    same(69.0, heat.indoor, "indoor");
    same(41.0, heat.humidity, "humidity");
    same(58.0, heat.outdoorTemperature, "outdoor temperature");
    same(62.0, heat.outdoorHumidity, "outdoor humidity");
    same(70.0, heat.heatSetpoint, "heat setpoint");
    same(78.0, heat.coolSetpoint, "cool setpoint");
    same(40.0, heat.heatMin, "heat min");
    same(90.0, heat.heatMax, "heat max");
    same(50.0, heat.coolMin, "cool min");
    same(99.0, heat.coolMax, "cool max");
    same("heat", heat.mode, "mode");
    same(Arrays.asList("heat", "off", "cool"), heat.modes, "allowed modes");
    same("permanent", heat.hold(), "permanent hold");
    same(null, heat.holdUntil(), "no end for a permanent hold");
    same("auto", heat.fan, "fan mode");
    check(heat.fanRunning, "fan running");
    same("heating", heat.running, "equipment running");
    same("heat", heat.active(), "active setpoint");
    same("cool", cool.mode, "cool mode");
    same("temporary", cool.hold(), "temporary hold");
    same("18:00", cool.holdUntil(), "hold end");
    same("idle", cool.running, "idle");

    TccClient.State bare = TccClient.parse(device(1001), new LinkedHashMap<String, Object>());
    check(!bare.online && bare.indoor == null && bare.mode == null && bare.hold() == null && bare.heatMin == null && bare.fan == null
        && bare.running == null && bare.active() == null && bare.modes.isEmpty() && "F".equals(bare.units), "empty payload parses to unknowns");
    Map<String, Object> odd = ui(9, 70, 68, 75, 7, "F");
    odd.put("EquipmentOutputStatus", null);
    odd.put("DispTemperature", null);
    odd.put("OutdoorTemperatureAvailable", false);
    odd.put("OutdoorHumidityAvailable", null);
    odd.put("IndoorHumiditySensorNotFault", false);
    odd.put("HeatLowerSetptLimit", 95.0);
    odd.put("CoolUpperSetptLimit", "99");
    TccClient.State strange = TccClient.parse(device(1001), Json.object("deviceLive", true, "communicationLost", true,
        "latestData", Json.object("uiData", odd, "hasFan", false, "fanData", Json.object("fanMode", 1L, "fanIsRunning", true))));
    check(!strange.online && strange.indoor == null && strange.running == null && strange.outdoorTemperature == null && strange.outdoorHumidity == null
        && strange.humidity == null && strange.mode == null && strange.hold() == null && strange.heatMin == null && strange.coolMax == null
        && strange.fan == null && !strange.fanRunning, "null, missing and out-of-range fields are unknown");
    String[] modes = {"emheat", "heat", "off", "cool", "auto", "auto"};
    for (int position = 0; position < modes.length; position++) {
      same(modes[position], TccClient.parse(device(1), Json.object("latestData", Json.object("uiData", Json.object("SystemSwitchPosition", (long) position)))).mode,
          "switch position " + position);
    }

    fresh();
    server.add(1003, "Loft", ui(1, 20.5, 21.5, 25, 0, "C"), false);
    client.signIn(USER, PASS);
    TccClient.State loft = client.read(new TccClient.Device(1003, 4242, "Loft", null));
    same("C", loft.units, "celsius");
    same(21.5, loft.heatSetpoint, "half degrees");
    same(4.5, loft.heatMin, "celsius limits");
    client.apply(loft.setpoint("heat", 22.5, false));
    check(server.last().body.contains("\"HeatSetpoint\":22.5"), "half degree is sent as is");
  }

  static void writing() throws Exception {
    fresh();
    server.ui(1001).put("StatusHeat", 0L);
    server.ui(1001).put("StatusCool", 0L);
    server.ui(1001).put("HeatNextPeriod", 88L);
    server.ui(1001).put("CoolNextPeriod", 90L);
    client.signIn(USER, PASS);
    final TccClient.State state = client.read(device(1001));
    client.apply(state.setpoint("heat", 72, false));
    Call call = server.last();
    same("POST", call.method, "write is a POST");
    same("/portal/Device/SubmitControlScreenChanges", call.path, "write path");
    same("application/json", call.headers.get("Content-Type"), "write content type");
    same("{\"DeviceID\":1001,\"SystemSwitch\":null,\"HeatSetpoint\":72,\"CoolSetpoint\":78,\"HeatNextPeriod\":88,\"CoolNextPeriod\":88,"
        + "\"StatusHeat\":1,\"StatusCool\":1,\"FanMode\":null}", call.body, "setpoint on schedule makes a temporary hold to the next period");

    TccClient.State holding = client.read(device(1001));
    Map<String, Object> kept = holding.setpoint("heat", 73, false);
    check(kept.get("StatusHeat") == null && kept.get("StatusCool") == null && kept.get("HeatNextPeriod") == null, "existing hold is left alone");
    same(73L, kept.get("HeatSetpoint"), "new heat setpoint");
    same(78L, kept.get("CoolSetpoint"), "other setpoint is resent unchanged");
    Map<String, Object> permanent = state.setpoint("cool", 75, true);
    same(2, permanent.get("StatusHeat"), "permanent hold heat");
    same(2, permanent.get("StatusCool"), "permanent hold cool");
    same(null, permanent.get("CoolNextPeriod"), "permanent hold has no end");
    same(9, permanent.size(), "all nine keys are always present");

    final int sent = server.calls.size();
    for (final double value : new double[] {39, 91, -5, 1000, Double.NaN}) {
      fails("out_of_range", new Action() {
        @Override public void run() throws Exception {
          client.apply(state.setpoint("heat", value, false));
        }
      }, "heat " + value);
    }
    fails("out_of_range", new Action() {
      @Override public void run() throws Exception {
        client.apply(state.setpoint("cool", 49, false));
      }
    }, "cool below limit");
    fails("not_allowed", new Action() {
      @Override public void run() throws Exception {
        state.setpoint("fan", 70, false);
      }
    }, "unknown setpoint");
    same(sent, server.calls.size(), "nothing outside the limits is sent");
    same(40L, state.setpoint("heat", 40, false).get("HeatSetpoint"), "lower limit itself is allowed");
    same(90L, state.setpoint("heat", 90, false).get("HeatSetpoint"), "upper limit itself is allowed");

    state.deadband = 3;
    same(79L, state.setpoint("heat", 76, false).get("CoolSetpoint"), "deadband pushes cool up");
    same(69L, state.setpoint("cool", 72, false).get("HeatSetpoint"), "deadband pushes heat down");
    state.coolMax = 80.0;
    state.coolSetpoint = 80.0;
    fails("out_of_range", new Action() {
      @Override public void run() throws Exception {
        state.setpoint("heat", 78, false);
      }
    }, "deadband may not push the other setpoint past its limit");
    state.heatMin = null;
    fails("not_allowed", new Action() {
      @Override public void run() throws Exception {
        state.setpoint("heat", 70, false);
      }
    }, "no limits reported means no changes");

    final TccClient.State current = client.read(device(1001));
    client.apply(current.mode("cool"));
    check(server.last().body.contains("\"SystemSwitch\":3") && server.last().body.contains("\"HeatSetpoint\":null"), "mode switch body");
    same(3L, server.ui(1001).get("SystemSwitchPosition"), "mode applied");
    same(1, current.mode("heat").get("SystemSwitch"), "heat switch position");
    for (final String mode : new String[] {"off", "auto", "emheat", "", null}) {
      fails("not_allowed", new Action() {
        @Override public void run() throws Exception {
          current.mode(mode);
        }
      }, "mode " + mode);
    }
    current.modes.remove("cool");
    fails("not_allowed", new Action() {
      @Override public void run() throws Exception {
        current.mode("cool");
      }
    }, "device without cooling");

    client.apply(current.resume());
    check(server.last().body.contains("\"StatusHeat\":0") && server.last().body.contains("\"StatusCool\":0") && server.last().body.contains("\"HeatSetpoint\":null"),
        "resume body");
    same("schedule", client.read(device(1001)).hold(), "schedule resumed");
    server.rejects = true;
    fails("rejected", new Action() {
      @Override public void run() throws Exception {
        client.apply(current.resume());
      }
    }, "refused change");
  }

  static void failures() throws Exception {
    fresh();
    client.signIn(USER, PASS);
    Object[][] cases = {{500, "unavailable"}, {502, "unavailable"}, {503, "unavailable"}, {429, "unavailable"},
        {"/portal/Error?aspxerrorpath=/portal/Device/CheckDataSession/1001", "unavailable"}, {"https://evil.example/", "unavailable"},
        {"html", "unexpected"}, {"badjson", "unexpected"}};
    for (Object[] entry : cases) {
      server.glitches.add(entry[0]);
      int before = server.calls.size();
      fails((String) entry[1], new Action() {
        @Override public void run() throws Exception {
          client.read(device(1001));
        }
      }, "glitch " + entry[0]);
      same(before + 1, server.calls.size(), "no retry and no redirect following for " + entry[0]);
    }
    server.unreachable = true;
    fails("offline", new Action() {
      @Override public void run() throws Exception {
        client.read(device(1001));
      }
    }, "network down");
    server.unreachable = false;
    client.read(device(1001));
    same(1, server.logins(), "service errors never trigger a login");
  }

  static void syncing() throws Exception {
    fresh();
    final Vault vault = new Vault();
    final int[] changes = {0};
    final List<Runnable> queue = new ArrayList<>();
    TccSync.Runner runner = new TccSync.Runner() {
      @Override public void start(Runnable work) {
        queue.add(work);
      }
    };
    TccSync.Listener listener = new TccSync.Listener() {
      @Override public void changed() {
        changes[0]++;
      }
    };
    final List<Runnable> timers = new ArrayList<>();
    final TccSync.Timer timer = new TccSync.Timer() {
      @Override public void after(long millis, Runnable work) {
        same(TccSync.SETTLE, millis, "settle delay");
        timers.add(work);
      }
    };
    final TccSync sync = new TccSync(client, vault, clock, clock, runner, timer, listener);
    Map<String, Object> status = sync.status();
    same(false, status.get("configured"), "starts unconfigured");
    same("unconfigured", status.get("status"), "unconfigured status");
    check(!sync.request(true) && !sync.due() && queue.isEmpty(), "nothing is polled when unconfigured");

    fails("bad_credentials", new Action() {
      @Override public void run() throws Exception {
        sync.configure(USER, "nope");
      }
    }, "wrong password at setup");
    check(vault.saved == null && !client.hasCredentials(), "a refused credential is not kept");
    same("unconfigured", sync.status().get("status"), "still unconfigured");

    sync.configure(USER, PASS);
    check(Arrays.equals(new String[] {USER, PASS}, vault.saved), "credential handed to the vault");
    status = sync.status();
    same(true, status.get("configured"), "configured");
    same("ok", status.get("status"), "ok after setup");
    same(FrameTime.iso(START), status.get("polledAt"), "poll time");
    same("F", status.get("units"), "units");
    same(58.0, Json.map(status.get("outdoor")).get("temperature"), "outdoor temperature");
    same(62.0, Json.map(status.get("outdoor")).get("humidity"), "outdoor humidity");
    List<Object> thermostats = Json.list(status.get("thermostats"));
    same(2, thermostats.size(), "two thermostats in the snapshot");
    Map<String, Object> first = Json.map(thermostats.get(0));
    same("t1", first.get("id"), "local alias");
    same("Level-0", first.get("name"), "name");
    same(true, first.get("online"), "online");
    same(69.0, first.get("indoor"), "indoor");
    same("heat", first.get("mode"), "mode");
    same(true, first.get("heatAllowed"), "heat allowed");
    same(true, first.get("coolAllowed"), "cool allowed");
    same(false, first.get("changing"), "nothing pending");
    same(null, first.get("error"), "no error");
    same("F", first.get("units"), "thermostat units");
    same(true, status.get("controllable"), "controllable when fresh");
    same(70.0, first.get("setpoint"), "active setpoint");
    same(40.0, Json.map(first.get("range")).get("min"), "device minimum");
    same(90.0, Json.map(first.get("range")).get("max"), "device maximum");
    same("permanent", first.get("hold"), "hold");
    same("heating", first.get("running"), "running");
    same("auto", first.get("fan"), "fan");
    Map<String, Object> second = Json.map(thermostats.get(1));
    same(76.0, second.get("setpoint"), "cool setpoint is active for a cooling device");
    same("18:00", second.get("holdUntil"), "hold end");
    String text = Json.write(status);
    for (String secret : new String[] {USER, PASS, "1001", "1002", "4242", "SESSION", "ASPXAUTH", "00D02D"}) {
      check(!text.contains(secret), "snapshot leaks " + secret);
    }
    check(changes[0] > 0, "listener is told");

    check(!sync.due(), "not due straight after a poll");
    clock.now += TccSync.WATCHED;
    check(!sync.due(), "idle cadence is five minutes");
    sync.watch(true);
    check(sync.due(), "watched cadence is one minute");
    sync.watch(false);
    clock.now += TccSync.IDLE;
    check(sync.due(), "due after the idle interval");
    int reads = server.count("GET", "/portal/Device/CheckDataSession/");
    check(sync.request(false) && sync.request(false) && sync.request(true), "requests are accepted");
    same(1, queue.size(), "requests collapse into one queued poll");
    queue.remove(0).run();
    same(reads + 2, server.count("GET", "/portal/Device/CheckDataSession/"), "one read per thermostat per poll");
    same(2, server.logins(), "polling does not log in again after the refused and the accepted setup");

    int writes = server.count("POST", "/portal/Device/SubmitControlScreenChanges");
    int told = changes[0];
    for (int tap = 1; tap <= 5; tap++) same(70.0 + tap, sync.step("t1", 1, false), "tap " + tap);
    Map<String, Object> tapped = Json.map(Json.list(sync.status().get("thermostats")).get(0));
    same(75.0, tapped.get("setpoint"), "pending value shows at once");
    same(true, tapped.get("changing"), "changing flag");
    check(changes[0] >= told + 5, "every tap is pushed to the dashboard");
    same(writes, server.count("POST", "/portal/Device/SubmitControlScreenChanges"), "nothing sent while tapping");
    same(5, timers.size(), "one timer per tap");
    for (Runnable early : new ArrayList<>(timers.subList(0, 4))) early.run();
    check(queue.isEmpty(), "superseded taps do nothing");
    timers.get(4).run();
    timers.clear();
    same(1, queue.size(), "the last tap sends");
    queue.remove(0).run();
    same(writes + 1, server.count("POST", "/portal/Device/SubmitControlScreenChanges"), "five taps make one request");
    same(75.0, server.ui(1001).get("HeatSetpoint") instanceof Long ? ((Long) server.ui(1001).get("HeatSetpoint")).doubleValue() : server.ui(1001).get("HeatSetpoint"), "coalesced value sent");
    tapped = Json.map(Json.list(sync.status().get("thermostats")).get(0));
    same(75.0, tapped.get("setpoint"), "reconciled with the next read");
    same(false, tapped.get("changing"), "no longer changing");
    server.ui(1001).put("HeatSetpoint", 89L);
    sync.poll();
    same(90.0, sync.step("t1", 3, false), "taps stop at the device maximum");
    same(90.0, sync.step("t1", 1, false), "still at the maximum");
    server.rejects = true;
    timers.remove(timers.size() - 1).run();
    timers.clear();
    queue.remove(0).run();
    tapped = Json.map(Json.list(sync.status().get("thermostats")).get(0));
    same(89.0, tapped.get("setpoint"), "a refused change reverts");
    same("rejected", tapped.get("error"), "the failure is reported for the tile");
    same(false, tapped.get("changing"), "not changing after a failure");
    server.rejects = false;
    same(88.0, sync.step("t1", -1, false), "tapping again");
    same(null, Json.map(Json.list(sync.status().get("thermostats")).get(0)).get("error"), "a new tap clears the error");
    timers.remove(0).run();
    queue.remove(0).run();
    server.ui(1001).put("HeatSetpoint", 70L);
    sync.poll();
    same(70.0, sync.step("t1", 0, false), "a step that changes nothing sends nothing");
    check(timers.isEmpty(), "no timer for no change");
    fails("not_found", new Action() {
      @Override public void run() throws Exception {
        sync.step("t7", 1, false);
      }
    }, "unknown thermostat tap");

    sync.setpoint("t1", 72, false);
    check(server.calls.get(server.calls.size() - 3).body.contains("\"HeatSetpoint\":72"), "setpoint sent");
    same(72.0, Json.map(Json.list(sync.status().get("thermostats")).get(0)).get("setpoint"), "snapshot refreshed after a change");
    sync.setpoint("t2", 74, true);
    check(server.calls.get(server.calls.size() - 3).body.contains("\"CoolSetpoint\":74") && server.calls.get(server.calls.size() - 3).body.contains("\"StatusCool\":2"),
        "cooling device changes its cool setpoint");
    final int sent = server.count("POST", "/portal/Device/SubmitControlScreenChanges");
    fails("out_of_range", new Action() {
      @Override public void run() throws Exception {
        sync.setpoint("t1", 91, false);
      }
    }, "above the device limit");
    fails("not_allowed", new Action() {
      @Override public void run() throws Exception {
        sync.mode("t1", "off");
      }
    }, "off is not offered");
    fails("not_found", new Action() {
      @Override public void run() throws Exception {
        sync.resume("t9");
      }
    }, "unknown thermostat");
    fails("not_found", new Action() {
      @Override public void run() throws Exception {
        sync.resume("1001");
      }
    }, "Honeywell ids are not accepted");
    same(sent, server.count("POST", "/portal/Device/SubmitControlScreenChanges"), "refused changes send nothing");
    sync.mode("t1", "cool");
    same("cool", Json.map(Json.list(sync.status().get("thermostats")).get(0)).get("mode"), "mode changed");
    sync.resume("t1");
    same("schedule", Json.map(Json.list(sync.status().get("thermostats")).get(0)).get("hold"), "schedule resumed");

    server.unreachable = true;
    sync.watch(true);
    sync.poll();
    same("ok", sync.status().get("status"), "one failure keeps the last reading");
    check(!sync.due(), "backs off after a failure");
    clock.now += TccSync.WATCHED;
    check(!sync.due(), "first retry waits two minutes");
    clock.now += TccSync.WATCHED;
    check(sync.due(), "retry after two minutes");
    sync.poll();
    sync.poll();
    same("unavailable", sync.status().get("status"), "three failures in a row");
    same(2, Json.list(sync.status().get("thermostats")).size(), "last readings are kept");
    fails("unavailable", new Action() {
      @Override public void run() throws Exception {
        sync.setpoint("t1", 70, false);
      }
    }, "no blind changes");
    clock.now += 8 * 60000L - 1;
    check(!sync.due(), "third retry waits eight minutes");
    for (int i = 0; i < 6; i++) sync.poll();
    clock.now += TccSync.LONGEST_WAIT - 1;
    check(!sync.due(), "wait is capped at ten minutes");
    clock.now += 1;
    check(sync.due(), "capped wait elapses");
    server.unreachable = false;
    sync.poll();
    same("ok", sync.status().get("status"), "recovers");

    clock.now += TccSync.STALE + 1;
    same("stale", sync.status().get("status"), "old readings are stale");
    fails("unavailable", new Action() {
      @Override public void run() throws Exception {
        sync.resume("t1");
      }
    }, "no changes on stale readings");
    sync.poll();
    same("ok", sync.status().get("status"), "fresh again");

    server.payloads.get(1002L).put("communicationLost", true);
    sync.poll();
    same(false, Json.map(Json.list(sync.status().get("thermostats")).get(1)).get("online"), "thermostat offline");
    fails("unavailable", new Action() {
      @Override public void run() throws Exception {
        sync.setpoint("t2", 75, false);
      }
    }, "offline thermostat is not changed");

    clock.now += 601000L;
    server.sessions.clear();
    server.login = "tooMany";
    sync.poll();
    status = sync.status();
    same("locked_out", status.get("status"), "throttled login shows as locked out");
    same(FrameTime.iso(clock.now + 600000L), status.get("retryAt"), "retry time");
    int calls = server.calls.size();
    check(!sync.due(), "waits for the lock");
    sync.poll();
    same(calls, server.calls.size(), "locked polls send nothing");
    check(vault.saved != null, "a lock-out keeps the credential");
    server.login = "normal";
    clock.now += 600001L;
    check(sync.due(), "due when the lock ends");
    sync.poll();
    same("ok", sync.status().get("status"), "unlocked");

    clock.now += 601000L;
    server.sessions.clear();
    server.password = "changed";
    sync.poll();
    same("signed_out", sync.status().get("status"), "rejected password signs out");
    check(vault.saved == null, "rejected credential is erased");
    same(0, Json.list(sync.status().get("thermostats")).size(), "no readings when signed out");
    calls = server.calls.size();
    check(!sync.request(true), "nothing more is polled");
    sync.poll();
    same(calls, server.calls.size(), "signed out polls send nothing");

    server.password = PASS;
    clock.now += 3600000L;
    sync.configure(USER, PASS);
    same("ok", sync.status().get("status"), "set up again");
    sync.forget();
    same("unconfigured", sync.status().get("status"), "forgotten");
    check(vault.saved == null && !client.hasCredentials() && !client.hasSession(), "forget erases everything");

    fresh();
    Vault kept = new Vault();
    kept.save(USER, PASS);
    TccSync restored = new TccSync(client, kept, clock, clock, runner, timer, listener);
    same("loading", restored.status().get("status"), "restored credential starts loading");
    check(restored.due(), "first poll is due at once");
    restored.poll();
    same("ok", restored.status().get("status"), "restored");
  }

  static Map<String, Object> shown(TccSync sync, int index) {
    return Json.map(Json.list(sync.status().get("thermostats")).get(index));
  }

  static void keeping() throws Exception {
    fresh();
    final Vault vault = new Vault();
    final List<Runnable> queue = new ArrayList<>();
    final List<Runnable> timers = new ArrayList<>();
    final TccSync[] made = new TccSync[1];
    final boolean[] interrupt = {false};
    TccClient.Transport wire = new TccClient.Transport() {
      @Override public TccClient.Reply send(String method, String path, Map<String, String> headers, String body) throws IOException {
        if (interrupt[0] && path.equals("/portal/Device/SubmitControlScreenChanges")) {
          interrupt[0] = false;
          try {
            made[0].step("t1", 1, false);
          } catch (TccClient.Problem impossible) {
            throw new IOException(impossible);
          }
        }
        return server.send(method, path, headers, body);
      }
    };
    client = new TccClient(wire, storage, clock, clock);
    final TccSync sync = new TccSync(client, vault, clock, clock, new TccSync.Runner() {
      @Override public void start(Runnable work) {
        queue.add(work);
      }
    }, new TccSync.Timer() {
      @Override public void after(long millis, Runnable work) {
        timers.add(work);
      }
    }, new TccSync.Listener() {
      @Override public void changed() {}
    });
    made[0] = sync;
    sync.configure(USER, PASS);
    same("ok", sync.status().get("status"), "a working account");
    int logins = server.logins();

    fails("bad_credentials", new Action() {
      @Override public void run() throws Exception {
        sync.configure(USER, "typo");
      }
    }, "a wrong password typed later");
    check(Arrays.equals(new String[] {USER, PASS}, vault.saved), "the working credential stays in the vault");
    same("ok", sync.status().get("status"), "the working account stays signed in");
    same(2, Json.list(sync.status().get("thermostats")).size(), "its thermostats stay listed");
    check(client.hasCredentials() && client.hasSession(), "the client keeps its session");
    same(logins + 1, server.logins(), "only the refused attempt reached the login page");
    sync.poll();
    same("ok", sync.status().get("status"), "polling carries on");
    same(logins + 1, server.logins(), "without signing in again");
    same(71.0, sync.step("t1", 1, false), "and the thermostat can still be changed");
    timers.remove(0).run();
    queue.remove(0).run();
    same(71.0, shown(sync, 0).get("setpoint"), "through the kept session");

    fails("bad_credentials", new Action() {
      @Override public void run() throws Exception {
        sync.configure("other@example.com", PASS);
      }
    }, "another account that is refused");
    check(Arrays.equals(new String[] {USER, PASS}, vault.saved), "does not replace the working one");
    server.unreachable = true;
    fails("offline", new Action() {
      @Override public void run() throws Exception {
        sync.configure(USER, PASS);
      }
    }, "a sign-in while offline");
    server.unreachable = false;
    check(Arrays.equals(new String[] {USER, PASS}, vault.saved) && client.hasSession(), "keeps the working account too");
    sync.poll();
    same("ok", sync.status().get("status"), "which still polls afterwards");
    same(2, Json.list(sync.status().get("thermostats")).size(), "with both thermostats");

    sync.resume("t1");
    same("schedule", shown(sync, 0).get("hold"), "following the schedule");
    same(null, shown(sync, 0).get("holdUntil"), "with no hold end");
    sync.step("t1", 1, false);
    same("temporary", shown(sync, 0).get("hold"), "a step on the schedule shows as a temporary hold at once");
    same("18:00", shown(sync, 0).get("holdUntil"), "until the next schedule period");
    timers.remove(0).run();
    queue.remove(0).run();
    String sent = server.calls.get(server.calls.size() - 3).body;
    check(sent.contains("\"StatusHeat\":1") && sent.contains("\"StatusCool\":1") && sent.contains("\"HeatNextPeriod\":72"), "and is sent as one");
    same("temporary", shown(sync, 0).get("hold"), "the read after it agrees");
    same("18:00", shown(sync, 0).get("holdUntil"), "with the same end");
    server.ui(1001).put("HeatNextPeriod", 88L);
    sync.poll();
    sync.step("t1", 1, false);
    same("22:00", shown(sync, 0).get("holdUntil"), "a step during a temporary hold keeps its end on the tile");
    timers.remove(0).run();
    queue.remove(0).run();
    sent = server.calls.get(server.calls.size() - 3).body;
    check(sent.contains("\"StatusHeat\":null") && sent.contains("\"StatusCool\":null") && sent.contains("\"HeatNextPeriod\":null"), "and leaves the hold as it is");
    same(88L, server.ui(1001).get("HeatNextPeriod"), "so its end is unchanged");
    server.ui(1001).put("StatusHeat", 2L);
    server.ui(1001).put("StatusCool", 2L);
    sync.poll();
    sync.step("t1", -1, false);
    same("permanent", shown(sync, 0).get("hold"), "a step during a permanent hold stays permanent on the tile");
    timers.remove(0).run();
    queue.remove(0).run();
    sent = server.calls.get(server.calls.size() - 3).body;
    check(sent.contains("\"StatusHeat\":null") && sent.contains("\"StatusCool\":null"), "and is sent without touching the hold");
    same("permanent", shown(sync, 0).get("hold"), "permanent after the read");

    double before = (Double) shown(sync, 0).get("setpoint");
    sync.step("t1", 1, false);
    timers.remove(0).run();
    server.rejects = true;
    interrupt[0] = true;
    queue.remove(0).run();
    server.rejects = false;
    same(before + 2, shown(sync, 0).get("setpoint"), "a tap during a failing write is still pending");
    same(true, shown(sync, 0).get("changing"), "and still changing");
    timers.remove(0).run();
    queue.remove(0).run();
    same(before + 2, shown(sync, 0).get("setpoint"), "the later tap is written");
    same(false, shown(sync, 0).get("changing"), "and settles");
    same(null, shown(sync, 0).get("error"), "without the earlier write's error left on the tile");
  }

  static byte[] drain(InputStream in) throws IOException {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    byte[] buffer = new byte[8192];
    for (int count; (count = in.read(buffer)) >= 0;) out.write(buffer, 0, count);
    return out.toByteArray();
  }

  static void http() throws Exception {
    TccHttp pinned = new TccHttp();
    same("https://mytotalconnectcomfort.com/portal/Device/CheckDataSession/1?_=2", pinned.allowed("/portal/Device/CheckDataSession/1?_=2").toString(), "pinned origin");
    for (String path : new String[] {null, "", "portal", "@evil.example/", ":8443/portal", ".evil.example/portal", "https://evil.example/"}) {
      try {
        pinned.allowed(path);
        throw new AssertionError("accepted " + path);
      } catch (IOException expected) {
        checks++;
      }
    }
    same("mytotalconnectcomfort.com", pinned.allowed("//evil.example/x").getHost(), "double slash stays on the pinned host");
    same("mytotalconnectcomfort.com", pinned.allowed("/x@evil.example/").getHost(), "at sign in a path stays on the pinned host");

    fresh();
    final int[] oversized = {0};
    HttpServer local = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    local.createContext("/", new HttpHandler() {
      @Override public void handle(HttpExchange exchange) throws IOException {
        Map<String, String> headers = new LinkedHashMap<>();
        for (String name : new String[] {"Cookie", "Content-Type", "X-Requested-With"}) {
          if (exchange.getRequestHeaders().getFirst(name) != null) headers.put(name, exchange.getRequestHeaders().getFirst(name));
        }
        String body = new String(drain(exchange.getRequestBody()), StandardCharsets.UTF_8);
        String path = exchange.getRequestURI().getRawPath() + (exchange.getRequestURI().getRawQuery() == null ? "" : "?" + exchange.getRequestURI().getRawQuery());
        TccClient.Reply reply = server.send(exchange.getRequestMethod(), path, headers, body.isEmpty() ? null : body);
        byte[] content = oversized[0] > 0 ? new byte[TccHttp.MAX_ANSWER + 1] : reply.body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", reply.contentType);
        if (reply.location != null) exchange.getResponseHeaders().set("Location", reply.location);
        for (String cookie : reply.cookies) exchange.getResponseHeaders().add("Set-Cookie", cookie);
        exchange.sendResponseHeaders(reply.status, content.length == 0 ? -1 : content.length);
        if (content.length > 0) exchange.getResponseBody().write(content);
        exchange.close();
      }
    });
    local.start();
    try {
      TccHttp transport = new TccHttp("http://127.0.0.1:" + local.getAddress().getPort());
      TccClient.Reply raw = transport.send("GET", "/portal/4242/Zones", new HashMap<String, String>(), null);
      same(401, raw.status, "status is passed through");
      final TccClient real = new TccClient(transport, new Storage(), clock, clock);
      real.signIn(USER, PASS);
      same(6, server.calls.size() - 1, "redirects are followed by the client, not the connection");
      check(real.hasSession(), "cookies with a malformed expiry survive real HTTP headers");
      List<TccClient.Device> devices = real.devices();
      same(2, devices.size(), "devices over HTTP");
      TccClient.State state = real.read(devices.get(0));
      same(70.0, state.heatSetpoint, "read over HTTP");
      real.apply(state.setpoint("heat", 71, false));
      same(71L, server.ui(1001).get("HeatSetpoint"), "write over HTTP");
      same(1, server.logins(), "one login over HTTP");
      server.glitches.add("https://evil.example/");
      fails("unavailable", new Action() {
        @Override public void run() throws Exception {
          real.read(device(1001));
        }
      }, "a foreign redirect is reported, never followed");
      oversized[0] = 1;
      fails("offline", new Action() {
        @Override public void run() throws Exception {
          real.read(device(1001));
        }
      }, "an oversized answer is cut off");
    } finally {
      local.stop(0);
    }
  }

  static TccClient.State held(long mode, Object heat, Object cool) throws Exception {
    fresh();
    Map<String, Object> ui = ui(mode, 70, 68, 76, 0, "F");
    ui.put("StatusHeat", heat);
    ui.put("StatusCool", cool);
    ui.put("HeatNextPeriod", 72L);
    ui.put("CoolNextPeriod", 88L);
    server.add(1003, "Loft", ui, false);
    client.signIn(USER, PASS);
    return client.read(new TccClient.Device(1003, 4242, "Loft", null));
  }

  static void holds() throws Exception {
    Map<String, Object> change = held(1, 0L, 2L).setpoint("heat", 69, false);
    same(1, change.get("StatusHeat"), "heating on schedule starts a temporary hold whatever the idle cool status says");
    same(1, change.get("StatusCool"), "both statuses move together");
    same(72L, ((Number) change.get("HeatNextPeriod")).longValue(), "the hold ends at the heating schedule's next period");
    same(72L, ((Number) change.get("CoolNextPeriod")).longValue(), "the cool period follows the active one");
    change = held(3, 2L, 0L).setpoint("cool", 75, false);
    same(1, change.get("StatusCool"), "cooling on schedule starts a temporary hold whatever the idle heat status says");
    same(88L, ((Number) change.get("CoolNextPeriod")).longValue(), "the hold ends at the cooling schedule's next period");
    change = held(1, null, null).setpoint("heat", 69, false);
    same(1, change.get("StatusHeat"), "a missing status is treated as following the schedule");
    change = held(1, null, 1L).setpoint("heat", 69, false);
    same(1, change.get("StatusHeat"), "a missing active status is treated as following the schedule");
    change = held(1, 1L, 0L).setpoint("heat", 69, false);
    check(change.get("StatusHeat") == null && change.get("StatusCool") == null && change.get("HeatNextPeriod") == null, "a temporary hold on the active mode is kept as it is");
    change = held(1, 2L, null).setpoint("heat", 69, false);
    check(change.get("StatusHeat") == null && change.get("StatusCool") == null, "a permanent hold on the active mode is kept as it is");
    change = held(3, 0L, 5L).setpoint("cool", 75, false);
    check(change.get("StatusHeat") == null && change.get("StatusCool") == null, "an unknown hold on the active mode is left alone");
    TccClient.State unknown = held(1, null, 2L);
    same(null, unknown.hold(), "a missing status is not reported as a hold");
    check(unknown.following(), "a missing status follows the schedule");
    check(!held(1, 5L, 0L).following(), "an unknown status is not the schedule");
  }

  static final long YEARS = 3L * 365 * 86400000L;

  static void jumps() throws Exception {
    fresh();
    for (int attempt = 1; attempt <= 3; attempt++) {
      fails("bad_credentials", new Action() {
        @Override public void run() throws Exception {
          client.signIn(USER, "nope");
        }
      }, "wrong password before the clock is set " + attempt);
    }
    clock.jumped = YEARS;
    int sent = server.calls.size();
    TccClient.Problem locked = fails("locked", new Action() {
      @Override public void run() throws Exception {
        client.signIn(USER, PASS);
      }
    }, "a lock survives the clock being set forward");
    same(sent, server.calls.size(), "and nothing is sent while it lasts");
    same(clock.now() + 600000L, locked.until, "the retry time moves with the clock");
    same(clock.now() + 600000L, client.lockedUntil(), "and is reported the same way");
    same(clock.now() + 600000L, ((Number) Json.map(Json.parse(storage.get("tcc.guard"))).get("lockedUntil")).longValue(), "and saved for the next start");
    clock.now += 300000L;
    clock.jumped = -YEARS;
    locked = fails("locked", new Action() {
      @Override public void run() throws Exception {
        client.signIn(USER, PASS);
      }
    }, "a lock survives the clock being set back");
    same(clock.now() + 300000L, locked.until, "with the time that is really left");
    clock.now += 300001L;
    client.signIn(USER, PASS);
    check(client.hasSession(), "and ends after its ten minutes whatever the clock says");
    same(0L, client.lockedUntil(), "no lock is left");
    same(0L, ((Number) Json.map(Json.parse(storage.get("tcc.guard"))).get("lockedUntil")).longValue(), "none is saved either");

    fresh();
    client.signIn(USER, PASS);
    clock.jumped = -YEARS;
    clock.now += 601000L;
    server.sessions.clear();
    same("Level-0", client.read(device(1001)).name, "a clock set back does not block the next automatic sign-in");
    same(2, server.logins(), "it happens once");
    clock.jumped = YEARS;
    clock.now += 60000L;
    server.sessions.clear();
    fails("session_expired", new Action() {
      @Override public void run() throws Exception {
        client.read(device(1001));
      }
    }, "a clock set forward does not allow an early automatic sign-in");
    same(2, server.logins(), "no extra sign-in");

    fresh();
    storage.put("tcc.guard", Json.write(Json.object("failures", 3, "lockedUntil", START + 300000L)));
    client = new TccClient(server, storage, clock, clock);
    fails("locked", new Action() {
      @Override public void run() throws Exception {
        client.signIn(USER, PASS);
      }
    }, "a saved lock holds after a restart");
    clock.now += 300001L;
    client.signIn(USER, PASS);
    check(client.hasSession(), "and ends at its saved time");

    for (String saved : new String[] {Json.write(Json.object("failures", 3, "lockedUntil", START + YEARS)), Json.write(Json.object("failures", 3, "lockedUntil", Long.MAX_VALUE)),
        "{broken", "[]", "{\"failures\":\"many\",\"lockedUntil\":true}", ""}) {
      fresh();
      storage.put("tcc.guard", saved);
      client = new TccClient(server, storage, clock, clock);
      same(0L, client.lockedUntil(), "a saved lock that cannot be real is not reported " + saved);
      client.signIn(USER, PASS);
      check(client.hasSession(), "and does not shut the account out " + saved);
      same("{\"failures\":0,\"lockedUntil\":0}", storage.get("tcc.guard"), "a good sign-in replaces it " + saved);
    }

    fresh();
    final Vault vault = new Vault();
    final List<Runnable> queue = new ArrayList<>();
    TccSync.Runner runner = new TccSync.Runner() {
      @Override public void start(Runnable work) {
        queue.add(work);
      }
    };
    TccSync.Timer timer = new TccSync.Timer() {
      @Override public void after(long millis, Runnable work) {}
    };
    TccSync.Listener listener = new TccSync.Listener() {
      @Override public void changed() {}
    };
    final TccSync sync = new TccSync(client, vault, clock, clock, runner, timer, listener);
    sync.configure(USER, PASS);
    sync.watch(true);
    clock.now += 30000L;
    clock.jumped = YEARS;
    Map<String, Object> status = sync.status();
    same("ok", status.get("status"), "a clock set forward does not make fresh readings stale");
    same(true, status.get("controllable"), "they stay controllable");
    same(FrameTime.iso(clock.now() - 30000L), status.get("polledAt"), "the poll time is shown on the corrected clock");
    check(!sync.due(), "and no extra poll fires");
    same(71.0, sync.step("t1", 1, false), "a step still works after the jump");
    clock.now += 30000L;
    check(sync.due(), "the next poll comes at its usual minute");
    sync.poll();
    clock.jumped = -YEARS;
    check(!sync.due(), "a clock set back does not fire a poll early");
    same(FrameTime.iso(clock.now()), sync.status().get("polledAt"), "the poll time follows the clock back");
    clock.now += TccSync.WATCHED;
    check(sync.due(), "nor does it stop the next poll");
    clock.now += TccSync.STALE;
    same("stale", sync.status().get("status"), "readings still go stale after ten real minutes");
    sync.poll();
    same("ok", sync.status().get("status"), "and recover with a poll");

    clock.now += 601000L;
    server.sessions.clear();
    server.login = "tooMany";
    sync.poll();
    same("locked_out", sync.status().get("status"), "locked out before the clock jumps");
    clock.jumped = YEARS;
    same(FrameTime.iso(clock.now() + 600000L), sync.status().get("retryAt"), "the retry time is never left in the past");
    check(!sync.due(), "the lock still holds after a jump forward");
    clock.now += 300000L;
    clock.jumped = -YEARS;
    same(FrameTime.iso(clock.now() + 300000L), sync.status().get("retryAt"), "nor in the far future");
    check(!sync.due(), "the lock still holds after a jump back");
    server.login = "normal";
    clock.now += 300001L;
    check(sync.due(), "and ends after its real ten minutes");
    sync.poll();
    same("ok", sync.status().get("status"), "unlocked on time");
  }

  public static void main(String[] args) throws Exception {
    java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("UTC"));
    login();
    redirects();
    sessions();
    reading();
    writing();
    holds();
    jumps();
    failures();
    syncing();
    keeping();
    http();
    System.out.println("Tcc: " + checks + " checks passed");
  }
}
