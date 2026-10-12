package com.wesbos.homehq;

import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.net.URI;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TimeZone;

final class TccClient {
  interface Transport {
    Reply send(String method, String path, Map<String, String> headers, String body) throws IOException;
  }

  static final class Reply {
    final int status;
    final String contentType;
    final String location;
    final List<String> cookies;
    final String body;

    Reply(int status, String contentType, String location, List<String> cookies, String body) {
      this.status = status;
      this.contentType = contentType;
      this.location = location;
      this.cookies = cookies == null ? new ArrayList<String>() : cookies;
      this.body = body == null ? "" : body;
    }
  }

  static final class Problem extends Exception {
    final String code;
    final long until;

    Problem(String code, long until) {
      super(code);
      this.code = code;
      this.until = until;
    }

    Problem(String code) {
      this(code, 0);
    }
  }

  static final class Device {
    final long id;
    final long location;
    final String name;
    final String mac;

    Device(long id, long location, String name, String mac) {
      this.id = id;
      this.location = location;
      this.name = name;
      this.mac = mac;
    }
  }

  static final class Kept {
    private final String username;
    private final String password;
    private final Map<String, String> cookies;
    private final long lastLogin;

    private Kept(String username, String password, Map<String, String> cookies, long lastLogin) {
      this.username = username;
      this.password = password;
      this.cookies = cookies;
      this.lastLogin = lastLogin;
    }
  }

  static final class State {
    long id;
    String name;
    boolean online;
    String units = "F";
    Double indoor;
    Double humidity;
    Double outdoorTemperature;
    Double outdoorHumidity;
    Double heatSetpoint;
    Double coolSetpoint;
    Double heatMin;
    Double heatMax;
    Double coolMin;
    Double coolMax;
    double deadband;
    String mode;
    List<String> modes = new ArrayList<>();
    Integer statusHeat;
    Integer statusCool;
    Integer heatNextPeriod;
    Integer coolNextPeriod;
    String fan;
    boolean fanRunning;
    String running;

    boolean cooling() {
      return "cool".equals(mode);
    }

    String active() {
      return "heat".equals(mode) || "emheat".equals(mode) ? "heat" : cooling() ? "cool" : null;
    }

    String hold() {
      Integer status = cooling() ? statusCool : statusHeat;
      return status == null || status < 0 || status >= HOLDS.length ? null : HOLDS[status];
    }

    boolean following() {
      Integer status = cooling() ? statusCool : statusHeat;
      return status == null || status == 0;
    }

    String holdUntil() {
      return "temporary".equals(hold()) ? nextPeriod() : null;
    }

    String nextPeriod() {
      Integer period = cooling() ? coolNextPeriod : heatNextPeriod;
      if (period == null || period < 0 || period > 95) return null;
      return String.format(Locale.ROOT, "%02d:%02d", period / 4, period % 4 * 15);
    }

    Map<String, Object> setpoint(String which, double value, boolean permanent) throws Problem {
      boolean heat = "heat".equals(which);
      Double low = heat ? heatMin : coolMin;
      Double high = heat ? heatMax : coolMax;
      if (!heat && !"cool".equals(which) || low == null || high == null || heatSetpoint == null || coolSetpoint == null) throw new Problem("not_allowed");
      if (Double.isNaN(value) || value < low || value > high) throw new Problem("out_of_range");
      double newHeat = heatSetpoint;
      double newCool = coolSetpoint;
      if (heat) {
        newHeat = value;
        if (deadband > 0 && newCool - deadband <= value) newCool = value + deadband;
      } else {
        newCool = value;
        if (deadband > 0 && newHeat + deadband >= value) newHeat = value - deadband;
      }
      if (newCool != coolSetpoint && coolMin != null && coolMax != null && (newCool < coolMin || newCool > coolMax)) throw new Problem("out_of_range");
      if (newHeat != heatSetpoint && heatMin != null && heatMax != null && (newHeat < heatMin || newHeat > heatMax)) throw new Problem("out_of_range");
      Map<String, Object> change = change(id);
      change.put("HeatSetpoint", number(newHeat));
      change.put("CoolSetpoint", number(newCool));
      if (permanent) {
        change.put("StatusHeat", 2);
        change.put("StatusCool", 2);
      } else if (following()) {
        Integer period = heat ? heatNextPeriod : coolNextPeriod;
        change.put("StatusHeat", 1);
        change.put("StatusCool", 1);
        change.put("HeatNextPeriod", period);
        change.put("CoolNextPeriod", period);
      }
      return change;
    }

    Map<String, Object> mode(String target) throws Problem {
      if (!"heat".equals(target) && !"cool".equals(target) || !modes.contains(target)) throw new Problem("not_allowed");
      Map<String, Object> change = change(id);
      change.put("SystemSwitch", "heat".equals(target) ? 1 : 3);
      return change;
    }

    Map<String, Object> resume() {
      Map<String, Object> change = change(id);
      change.put("StatusHeat", 0);
      change.put("StatusCool", 0);
      return change;
    }
  }

  static final String HOST = "mytotalconnectcomfort.com";
  static final String ORIGIN = "https://" + HOST;
  static final String AUTH_COOKIE = ".ASPXAUTH_TRUEHOME";
  static final long RELOGIN_MILLIS = 600000L;
  static final long LOCK_MILLIS = 600000L;
  static final long LONGEST_LOCK_MILLIS = 6 * 3600000L;
  static final int MAX_LOGIN_FAILURES = 3;
  private static final int MAX_REDIRECTS = 5;
  private static final String GUARD = "tcc.guard";
  private static final String[] MODES = {"emheat", "heat", "off", "cool", "auto", "auto"};
  private static final String[] MODE_FLAGS = {"SwitchEmergencyHeatAllowed", "SwitchHeatAllowed", "SwitchOffAllowed", "SwitchCoolAllowed", "SwitchAutoAllowed"};
  private static final String[] HOLDS = {"schedule", "temporary", "permanent"};
  private static final String[] FANS = {"auto", "on", "circulate", "schedule"};
  private static final String[] RUNNING = {"idle", "heating", "cooling"};

  private final Transport transport;
  private final KeyValue storage;
  private final FrameTime.Clock clock;
  private final FrameTime.Uptime uptime;
  private final Map<String, String> cookies = new LinkedHashMap<>();
  private String username;
  private String password;
  private boolean emptyAuthCookie;
  private final List<String> steps = new ArrayList<>();
  private boolean tracing;
  private long lastLogin;
  private long counter;
  private int failures;
  private long lockedUntil;
  private long lockedUp;

  TccClient(Transport transport, KeyValue storage, FrameTime.Clock clock, FrameTime.Uptime uptime) {
    this.transport = transport;
    this.storage = storage;
    this.clock = clock;
    this.uptime = uptime;
    counter = clock.now();
    try {
      Map<String, Object> saved = Json.map(Json.parse(storage.get(GUARD)));
      failures = ((Number) saved.get("failures")).intValue();
      lockedUntil = ((Number) saved.get("lockedUntil")).longValue();
    } catch (Json.Malformed | RuntimeException absent) {
      failures = 0;
      lockedUntil = 0;
    }
  }

  synchronized void credentials(String name, String secret) {
    username = name;
    password = secret;
    cookies.clear();
  }

  synchronized boolean hasCredentials() {
    return username != null && password != null;
  }

  synchronized boolean hasSession() {
    return cookies.containsKey(AUTH_COOKIE);
  }

  synchronized int failures() {
    return failures;
  }

  synchronized long lockedUntil() {
    long left = locked();
    return left > 0 ? clock.now() + left : 0;
  }

  private long locked() {
    long now = clock.now();
    if (lockedUp == 0) return lockedUntil - now > LONGEST_LOCK_MILLIS ? 0 : Math.max(0, lockedUntil - now);
    long left = Math.max(0, lockedUp - uptime.millis());
    long until = left > 0 ? FrameTime.anchored(lockedUntil, now + left) : 0;
    if (until != lockedUntil) save(until);
    return left;
  }

  synchronized Kept keep() {
    return new Kept(username, password, new LinkedHashMap<>(cookies), lastLogin);
  }

  synchronized void restore(Kept kept) {
    username = kept.username;
    password = kept.password;
    lastLogin = kept.lastLogin;
    cookies.clear();
    cookies.putAll(kept.cookies);
  }

  synchronized void signIn(String name, String secret) throws Problem {
    credentials(name, secret);
    login(false);
  }

  synchronized void signOut() {
    if (hasSession()) {
      try {
        exchange("POST", "/portal/Account/LogOff", "application/json", null);
      } catch (Problem ignored) {
        cookies.clear();
      }
    }
    username = null;
    password = null;
    lastLogin = 0;
    cookies.clear();
  }

  synchronized List<Device> devices() throws Problem {
    ensureSession();
    List<Device> found = new ArrayList<>();
    for (int page = 1; page <= 4; page++) {
      Object listed;
      try {
        listed = json("POST", "/portal/Location/GetLocationListData/?page=" + page + "&filter=", null, true);
      } catch (Problem problem) {
        if (page > 1 && "unexpected".equals(problem.code)) break;
        throw problem;
      }
      List<Object> locations = Json.list(listed);
      if (locations == null || locations.isEmpty()) break;
      for (Object entry : locations) {
        Map<String, Object> location = Json.map(entry);
        if (location == null || !(location.get("LocationID") instanceof Number) || Json.list(location.get("Devices")) == null) continue;
        for (Object item : Json.list(location.get("Devices"))) {
          Map<String, Object> device = Json.map(item);
          if (device == null || !(device.get("DeviceID") instanceof Number)) continue;
          Object name = device.get("Name");
          Object mac = device.get("MacID");
          found.add(new Device(((Number) device.get("DeviceID")).longValue(), ((Number) location.get("LocationID")).longValue(),
              name instanceof String ? (String) name : "Thermostat", mac instanceof String ? (String) mac : null));
        }
      }
    }
    return found;
  }

  synchronized State read(Device device) throws Problem {
    ensureSession();
    Map<String, Object> payload = Json.map(json("GET", "/portal/Device/CheckDataSession/" + device.id + "?_=" + (++counter), null, true));
    if (payload == null) throw new Problem("unexpected");
    return parse(device, payload);
  }

  synchronized void apply(Map<String, Object> change) throws Problem {
    ensureSession();
    Map<String, Object> answer = Json.map(json("POST", "/portal/Device/SubmitControlScreenChanges", Json.write(change), true));
    Object success = answer == null ? null : answer.get("success");
    if (!(success instanceof Number) || ((Number) success).intValue() != 1) throw new Problem("rejected");
  }

  static Map<String, Object> change(long deviceId) {
    return Json.object("DeviceID", deviceId, "SystemSwitch", null, "HeatSetpoint", null, "CoolSetpoint", null, "HeatNextPeriod", null,
        "CoolNextPeriod", null, "StatusHeat", null, "StatusCool", null, "FanMode", null);
  }

  static Object number(double value) {
    return value == Math.rint(value) && Math.abs(value) < 1e9 ? (Object) Long.valueOf((long) value) : (Object) Double.valueOf(value);
  }

  static State parse(Device device, Map<String, Object> payload) {
    Map<String, Object> latest = orEmpty(payload.get("latestData"));
    Map<String, Object> ui = orEmpty(latest.get("uiData"));
    Map<String, Object> fan = orEmpty(latest.get("fanData"));
    State state = new State();
    state.id = device.id;
    state.name = device.name;
    state.online = flag(payload, "deviceLive") && !flag(payload, "communicationLost");
    state.units = "C".equals(ui.get("DisplayUnits")) ? "C" : "F";
    state.indoor = decimal(ui, "DispTemperature");
    state.humidity = flag(ui, "IndoorHumiditySensorAvailable") && flag(ui, "IndoorHumiditySensorNotFault") ? decimal(ui, "IndoorHumidity") : null;
    state.outdoorTemperature = flag(ui, "OutdoorTemperatureAvailable") ? decimal(ui, "OutdoorTemperature") : null;
    state.outdoorHumidity = flag(ui, "OutdoorHumidityAvailable") ? decimal(ui, "OutdoorHumidity") : null;
    state.heatSetpoint = decimal(ui, "HeatSetpoint");
    state.coolSetpoint = decimal(ui, "CoolSetpoint");
    state.heatMin = decimal(ui, "HeatLowerSetptLimit");
    state.heatMax = decimal(ui, "HeatUpperSetptLimit");
    if (state.heatMin == null || state.heatMax == null || state.heatMin > state.heatMax) state.heatMin = state.heatMax = null;
    state.coolMin = decimal(ui, "CoolLowerSetptLimit");
    state.coolMax = decimal(ui, "CoolUpperSetptLimit");
    if (state.coolMin == null || state.coolMax == null || state.coolMin > state.coolMax) state.coolMin = state.coolMax = null;
    Double deadband = decimal(ui, "Deadband");
    state.deadband = deadband == null ? 0 : deadband;
    state.mode = pick(MODES, whole(ui, "SystemSwitchPosition"));
    for (int i = 0; i < MODE_FLAGS.length; i++) if (flag(ui, MODE_FLAGS[i])) state.modes.add(MODES[i]);
    state.statusHeat = whole(ui, "StatusHeat");
    state.statusCool = whole(ui, "StatusCool");
    state.heatNextPeriod = whole(ui, "HeatNextPeriod");
    state.coolNextPeriod = whole(ui, "CoolNextPeriod");
    boolean hasFan = flag(latest, "hasFan");
    state.fan = hasFan ? pick(FANS, whole(fan, "fanMode")) : null;
    state.fanRunning = hasFan && flag(fan, "fanIsRunning");
    state.running = pick(RUNNING, whole(ui, "EquipmentOutputStatus"));
    return state;
  }

  private static Map<String, Object> orEmpty(Object value) {
    Map<String, Object> map = Json.map(value);
    return map == null ? new LinkedHashMap<String, Object>() : map;
  }

  private static boolean flag(Map<String, Object> source, String key) {
    return Boolean.TRUE.equals(source.get(key));
  }

  private static Double decimal(Map<String, Object> source, String key) {
    Object value = source.get(key);
    return value instanceof Number ? Double.valueOf(((Number) value).doubleValue()) : null;
  }

  private static Integer whole(Map<String, Object> source, String key) {
    Object value = source.get(key);
    return value instanceof Number ? Integer.valueOf(((Number) value).intValue()) : null;
  }

  private static String pick(String[] names, Integer index) {
    return index == null || index < 0 || index >= names.length ? null : names[index];
  }

  private void ensureSession() throws Problem {
    if (!hasSession()) login(true);
  }

  private Object json(String method, String path, String body, boolean retry) throws Problem {
    Reply reply = exchange(method, path, "application/json", body);
    if (reply.status == 401 || reply.status == 403) {
      cookies.remove(AUTH_COOKIE);
      if (!retry) throw new Problem("session_expired");
      login(true);
      return json(method, path, body, false);
    }
    if (reply.status != 200) throw new Problem("unavailable");
    if (reply.contentType == null || !reply.contentType.toLowerCase(Locale.ROOT).startsWith("application/json")) throw new Problem("unexpected");
    try {
      Object value = Json.parse(reply.body);
      if (failures != 0) guard(0, 0);
      return value;
    } catch (Json.Malformed malformed) {
      throw new Problem("unexpected");
    }
  }

  private void login(boolean automatic) throws Problem {
    if (!hasCredentials()) throw new Problem("signed_out");
    long now = clock.now();
    long up = uptime.millis();
    long left = locked();
    if (left > 0) throw new Problem("locked", now + left);
    if (automatic && lastLogin != 0 && up - lastLogin < RELOGIN_MILLIS) throw new Problem("session_expired", now + lastLogin + RELOGIN_MILLIS - up);
    lastLogin = up;
    cookies.clear();
    tracing = true;
    try {
      follow("GET", "/portal", "application/json", null);
      String form = "timeOffset=" + (-TimeZone.getDefault().getOffset(now) / 60000) + "&UserName=" + encode(username) + "&Password=" + encode(password)
          + "&RememberMe=false";
      Reply posted = follow("POST", "/portal", "application/x-www-form-urlencoded", form);
      if (posted.status == 401) throw new Problem("bad_credentials");
      if (posted.status != 200) throw new Problem("unavailable");
      if (posted.body.contains("The email or password provided is incorrect") || posted.body.contains("The email address is not in the correct format")) {
        throw new Problem("bad_credentials");
      }
      emptyAuthCookie = false;
      Reply confirmed = follow("GET", "/portal", "application/json", null);
      if (emptyAuthCookie) throw new Problem("login_failed");
      if (confirmed.status == 401) throw new Problem("bad_credentials");
      if (confirmed.status != 200) throw new Problem("unavailable");
      if (!hasSession()) throw new Problem("login_failed");
      guard(0, 0);
    } catch (Problem problem) {
      cookies.clear();
      if ("throttled".equals(problem.code)) {
        fail(MAX_LOGIN_FAILURES);
        throw new Problem("locked", lockedUntil);
      }
      if ("bad_credentials".equals(problem.code) || "login_failed".equals(problem.code)) fail(0);
      throw problem;
    } finally {
      tracing = false;
    }
  }

  String steps() {
    synchronized (steps) {
      return steps.toString();
    }
  }

  private void fail(int floor) {
    int next = Math.max(failures + 1, floor);
    guard(next, next < MAX_LOGIN_FAILURES ? 0 : Math.min(LONGEST_LOCK_MILLIS, LOCK_MILLIS << Math.min(next - MAX_LOGIN_FAILURES, 10)));
  }

  private void guard(int count, long lock) {
    failures = count;
    lockedUp = lock > 0 ? uptime.millis() + lock : 0;
    save(lock > 0 ? clock.now() + lock : 0);
  }

  private void save(long until) {
    lockedUntil = until;
    storage.put(GUARD, Json.write(Json.object("failures", failures, "lockedUntil", until)));
  }

  private Reply follow(String method, String path, String contentType, String body) throws Problem {
    String verb = method;
    String target = path;
    String content = body;
    for (int hop = 0; hop <= MAX_REDIRECTS; hop++) {
      Reply reply = exchange(verb, target, content == null ? "application/json" : contentType, content);
      if (reply.status < 300 || reply.status >= 400) return reply;
      if (reply.location == null || reply.location.trim().isEmpty()) throw new Problem("unavailable");
      target = sameOrigin(reply.location, target);
      if (target.contains("TooManyAttempts")) throw new Problem("throttled");
      if (target.contains("/Error")) throw new Problem("unavailable");
      verb = "GET";
      content = null;
    }
    throw new Problem("unavailable");
  }

  static String sameOrigin(String location, String from) throws Problem {
    try {
      URI target = URI.create(ORIGIN + from).resolve(location.trim());
      boolean trusted = "https".equals(target.getScheme()) && HOST.equals(target.getHost()) && target.getPort() == -1 && target.getRawUserInfo() == null
          && target.getRawPath() != null && target.getRawPath().startsWith("/");
      if (!trusted) throw new Problem("foreign_host");
      return target.getRawPath() + (target.getRawQuery() == null ? "" : "?" + target.getRawQuery());
    } catch (RuntimeException unreadable) {
      throw new Problem("foreign_host");
    }
  }

  private Reply exchange(String method, String path, String contentType, String body) throws Problem {
    Map<String, String> headers = new LinkedHashMap<>();
    if (!tracing) headers.put("X-Requested-With", "XMLHttpRequest");
    headers.put("Accept", "*/*");
    headers.put("Content-Type", contentType);
    if (!cookies.isEmpty()) {
      StringBuilder jar = new StringBuilder();
      for (Map.Entry<String, String> cookie : cookies.entrySet()) {
        if (jar.length() > 0) jar.append("; ");
        jar.append(cookie.getKey()).append('=').append(cookie.getValue());
      }
      headers.put("Cookie", jar.toString());
    }
    Reply reply;
    try {
      reply = transport.send(method, path, headers, body);
    } catch (IOException offline) {
      synchronized (steps) {
        steps.add(method + " " + path.split("\\?", 2)[0] + " failed " + offline.getClass().getSimpleName() + " " + offline.getMessage());
        if (steps.size() > 12) steps.remove(0);
      }
      throw new Problem("offline");
    }
    for (String cookie : reply.cookies) {
      String pair = cookie.split(";", 2)[0].trim();
      int split = pair.indexOf('=');
      if (split <= 0) continue;
      String name = pair.substring(0, split);
      String value = pair.substring(split + 1);
      String lowered = cookie.toLowerCase(Locale.US);
      if (value.isEmpty() && (AUTH_COOKIE.equals(name) || lowered.contains("expires=") || lowered.contains("max-age="))) {
        cookies.remove(name);
        if (AUTH_COOKIE.equals(name)) emptyAuthCookie = true;
      } else {
        cookies.put(name, value);
      }
    }
    {
      StringBuilder step = new StringBuilder(method).append(' ').append(path.split("\\?", 2)[0]).append(' ').append(reply.status);
      if (reply.location != null) step.append(" to ").append(reply.location.split("\\?", 2)[0]);
      for (String cookie : reply.cookies) {
        String[] pair = cookie.split(";", 2)[0].trim().split("=", 2);
        step.append(pair.length == 2 && pair[1].isEmpty() ? " -" : " +").append(pair[0]);
      }
      java.util.regex.Matcher title = java.util.regex.Pattern.compile("<title>\\s*([^<]{0,60})").matcher(reply.body == null ? "" : reply.body);
      if (title.find()) step.append(" title ").append(title.group(1).trim());
      if (reply.body != null && reply.body.contains("validation-summary-errors")) step.append(" refused");
      step.append(" type ").append(reply.contentType);
      synchronized (steps) {
        steps.add(step.toString());
        if (steps.size() > 12) steps.remove(0);
      }
    }
    return reply;
  }

  private static String encode(String text) {
    try {
      return URLEncoder.encode(text, "UTF-8");
    } catch (UnsupportedEncodingException impossible) {
      throw new IllegalStateException(impossible);
    }
  }
}
