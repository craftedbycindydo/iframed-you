package com.wesbos.homehq;

import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TimeZone;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

final class LocalApi {
  interface Calendars {
    List<Object> list();

    String add(String name, String color, String url);

    boolean remove(String id);
  }

  interface Photos {
    List<Photo> list();

    boolean add(byte[] jpeg, long addedAt);

    byte[] read(String id);

    boolean remove(String id);
  }

  interface Events {
    void householdChanged(String snapshot);

    void pairingChanged(String state, long remaining);

    void settingsRequested(String settings);
  }

  static final class Photo {
    final String id;
    final long addedAt;

    Photo(String id, long addedAt) {
      this.id = id;
      this.addedAt = addedAt;
    }
  }

  static final String NAME = "Skylit";
  static final int MAX_JSON = 64 * 1024;
  static final int MAX_UNPAIRED_JSON = 4 * 1024;
  static final int MAX_PHOTO = 15 * 1024 * 1024;
  static final int MAX_CALENDARS = 6;
  private static final int UPLOAD_WAIT_SECONDS = 20;
  private static final String[] PALETTES = {"linen", "sage", "stone", "ocean", "plum", "contrast"};
  private static final String[] MODES = {"light", "dark", "auto"};

  private final KeyValue storage;
  private final FrameTime.Clock clock;
  private final Calendars calendars;
  private final Photos photos;
  private final Events events;
  private final ICloudSync icloud;
  private final HouseholdStore household;
  private final Pairing pairing;
  private final Semaphore uploads = new Semaphore(1);
  private final Identity identity;
  private Map<String, Object> settings;
  private String observed;

  LocalApi(KeyValue storage, FrameTime.Clock clock, FrameTime.Uptime uptime, Calendars calendars, Photos photos, ICloudSync icloud, final Events events) {
    this.storage = storage;
    this.clock = clock;
    this.calendars = calendars;
    this.photos = photos;
    this.events = events;
    this.icloud = icloud;
    household = new HouseholdStore(storage);
    identity = Identity.open(storage);
    pairing = new Pairing(identity, clock, uptime, new Pairing.Listener() {
      @Override public void changed(Map<String, Object> state, long remaining) {
        events.pairingChanged(Json.write(state), remaining);
      }
    });
    settings = Json.object("location", null, "appearance", Json.object("palette", "linen", "mode", "auto"));
    try {
      Map<String, Object> saved = Json.map(Json.parse(storage.get("settings")));
      Object location = saved.get("location") == null ? null : location(Json.map(saved.get("location")));
      settings = Json.object("location", location, "appearance", appearance(Json.map(saved.get("appearance"))));
    } catch (Json.Malformed | ApiException | RuntimeException absentOrUnreadable) {
      storage.put("settings", Json.write(settings));
    }
    observed = external();
  }

  String frameId() {
    return identity.frameId;
  }

  Identity identity() {
    return identity;
  }

  LocalHttp.Response handle(LocalHttp.Request request, LocalHttp.Body body) throws IOException {
    try {
      return route(request, body);
    } catch (ApiException problem) {
      return LocalHttp.Response.error(problem);
    } catch (RuntimeException unexpected) {
      return LocalHttp.Response.error(500, "internal", "The frame could not complete this request");
    }
  }

  String householdSnapshot() {
    return Json.write(household.snapshot(today()));
  }

  String householdMutate(String json) {
    try {
      Map<String, Object> op = Json.map(Json.parse(json));
      if (op == null) throw ApiException.badRequest("Expected an object");
      mutate(op);
      return Json.write(Json.object("ok", true, "snapshot", household.snapshot(today())));
    } catch (Json.Malformed | ApiException problem) {
      return Json.write(Json.object("ok", false, "error", problem.getMessage()));
    }
  }

  boolean reportSettings(String json) {
    try {
      Map<String, Object> reported = Json.map(Json.parse(json));
      Map<String, Object> changed = new LinkedHashMap<>();
      if (reported.containsKey("location")) {
        changed.put("location", reported.get("location") == null ? null : location(Json.map(reported.get("location"))));
      }
      if (reported.containsKey("appearance")) changed.put("appearance", appearance(Json.map(reported.get("appearance"))));
      merge(changed);
      return true;
    } catch (Json.Malformed | ApiException | RuntimeException rejected) {
      return false;
    }
  }

  String pairingStatus(int port, boolean advertised, String address) {
    pairing.expireIfDue();
    return Json.write(Json.object("devices", pairing.devices(null), "port", port, "advertised", advertised, "address", address,
        "pairing", pairing.state()));
  }

  String pairingOpen() {
    try {
      return Json.write(Json.object("ok", true, "pairing", pairing.open()));
    } catch (ApiException refused) {
      return Json.write(Json.object("ok", false, "error", refused.getMessage()));
    }
  }

  boolean pairingTap(String number) {
    return pairing.tap(number);
  }

  boolean pairingCancel() {
    return pairing.dismiss();
  }

  String pairingPick() {
    return pairing.pick();
  }

  boolean pairingRevoke(String id) {
    return pairing.revoke(id);
  }

  boolean pairingRevokeAll() {
    return pairing.revokeAll();
  }

  String icloudStatus() {
    return Json.write(icloud.status());
  }

  String icloudConnect(String url) {
    try {
      icloud.connect(url);
      return Json.write(Json.object("ok", true));
    } catch (ApiException rejected) {
      return Json.write(Json.object("ok", false, "error", rejected.getMessage()));
    }
  }

  boolean icloudDisconnect() {
    return icloud.disconnect();
  }

  void icloudSync() {
    icloud.request(true);
  }

  void expirePairing() {
    pairing.expireIfDue();
  }

  synchronized long observe() {
    String current = external();
    if (!current.equals(observed)) {
      observed = current;
      return household.touch();
    }
    return household.rev();
  }

  private String external() {
    StringBuilder signature = new StringBuilder(Json.write(calendars.list()));
    for (Photo photo : photos.list()) signature.append(photo.id);
    signature.append(Json.write(icloud.status()));
    return signature.toString();
  }

  private String today() {
    return FrameTime.day(clock.now(), zone());
  }

  private synchronized TimeZone zone() {
    Map<String, Object> location = Json.map(settings.get("location"));
    Object name = location == null ? null : location.get("timezone");
    if (name instanceof String && TimeZone.getTimeZone((String) name).getID().equals(name)) {
      return TimeZone.getTimeZone((String) name);
    }
    return TimeZone.getDefault();
  }

  private Map<String, Object> mutate(Map<String, Object> op) throws ApiException {
    long before = household.rev();
    Map<String, Object> result = household.mutate(op, today());
    if (!result.get("rev").equals(before)) events.householdChanged(householdSnapshot());
    return result;
  }

  private synchronized long merge(Map<String, Object> changed) {
    Map<String, Object> next = new LinkedHashMap<>(settings);
    next.putAll(changed);
    if (Json.write(next).equals(Json.write(settings))) return household.rev();
    settings = next;
    storage.put("settings", Json.write(settings));
    return household.touch();
  }

  private static Map<String, Object> location(Map<String, Object> fields) throws ApiException {
    if (fields == null) throw ApiException.badRequest("location must be an object");
    Object zone = fields.get("timezone");
    if (zone != null && !(zone instanceof String && ((String) zone).matches("[A-Za-z0-9_+\\-/]{1,64}"))) {
      throw ApiException.badRequest("timezone must be an IANA zone name");
    }
    return Json.object("name", Fields.text(fields, "name", 1, 80),
        "latitude", Fields.decimal(fields, "latitude", -90, 90),
        "longitude", Fields.decimal(fields, "longitude", -180, 180), "timezone", zone);
  }

  private static Map<String, Object> appearance(Map<String, Object> fields) throws ApiException {
    if (fields == null) throw ApiException.badRequest("appearance must be an object");
    return Json.object("palette", Fields.choice(fields, "palette", PALETTES), "mode", Fields.choice(fields, "mode", MODES));
  }

  private LocalHttp.Response route(LocalHttp.Request request, LocalHttp.Body body) throws ApiException, IOException {
    String route = request.method + " " + request.path;
    switch (route) {
      case "GET /v2/info":
        return LocalHttp.Response.json(200, Json.object("v", 2, "frameId", identity.frameId, "name", NAME, "pairing", pairing.accepting()));
      case "POST /v2/pair/start":
        return LocalHttp.Response.json(200, pairing.start(fields(body, MAX_UNPAIRED_JSON)));
      case "POST /v2/pair/reveal":
        pairing.reveal(fields(body, MAX_UNPAIRED_JSON));
        return LocalHttp.Response.empty(204);
      case "POST /v2/pair/cancel":
        pairing.cancel(fields(body, MAX_UNPAIRED_JSON));
        return LocalHttp.Response.empty(204);
      case "GET /v2/pair/result":
        Map<String, Object> paired = pairing.result(request.query.get("session"));
        if (paired == null) return LocalHttp.Response.empty(202);
        return LocalHttp.Response.json(200, Json.object("deviceId", paired.get("deviceId"), "frameId", identity.frameId, "name", NAME));
      default:
        break;
    }
    String authorization = request.headers.get("authorization");
    String caller = authorization != null && authorization.startsWith("Bearer ") ? pairing.authenticate(authorization.substring(7).trim()) : null;
    if (caller == null) throw ApiException.unauthorized("Pair this device with the frame first");
    switch (route) {
      case "GET /v1/devices":
        return LocalHttp.Response.json(200, pairing.devices(caller));
      case "GET /v1/state":
        return state(request.query.get("since"));
      case "POST /v1/people":
        return mutation("person.add", null, body);
      case "POST /v1/chores":
        return mutation("chore.add", null, body);
      case "POST /v1/shopping":
        return mutation("item.add", null, body);
      case "POST /v1/shopping/clear-done":
        return mutation("items.clearDone", null, null);
      case "PUT /v1/settings/location":
        return setting("location", location(fields(body)));
      case "PUT /v1/settings/appearance":
        return setting("appearance", appearance(fields(body)));
      case "PUT /v1/settings/icloud-album":
        icloud.connect(fields(body).get("url"));
        return LocalHttp.Response.json(200, Json.object("rev", observe()));
      case "DELETE /v1/settings/icloud-album":
        icloud.disconnect();
        return LocalHttp.Response.json(200, Json.object("rev", observe()));
      case "POST /v1/settings/icloud-album/sync":
        if (!icloud.request(true)) throw ApiException.conflict("No shared album is connected");
        return LocalHttp.Response.empty(204);
      case "POST /v1/calendars":
        return addCalendar(fields(body));
      case "GET /v1/photos":
        List<Object> listed = new ArrayList<>();
        for (Photo photo : photos.list()) listed.add(described(photo));
        return LocalHttp.Response.json(200, listed);
      case "POST /v1/photos":
        return upload(request, body);
      default:
        break;
    }
    String[] parts = request.path.split("/");
    if (parts.length == 5 && route.startsWith("PUT /v1/chores/") && parts[4].equals("done")) {
      return mutation("chore.done", parts[3], body);
    }
    if (parts.length != 4 || !parts[1].equals("v1")) throw ApiException.notFound("No such route");
    String id = parts[3];
    switch (request.method + " " + parts[2]) {
      case "DELETE devices":
        if (!id.equals(caller)) throw ApiException.forbidden("A phone can only remove itself. Remove others on the frame.");
        pairing.revoke(id);
        return LocalHttp.Response.empty(204);
      case "PATCH people":
        return mutation("person.update", id, body);
      case "DELETE people":
        return mutation("person.remove", id, null);
      case "PATCH chores":
        return mutation("chore.update", id, body);
      case "DELETE chores":
        return mutation("chore.remove", id, null);
      case "PATCH shopping":
        return mutation("item.update", id, body);
      case "DELETE shopping":
        return mutation("item.remove", id, null);
      case "DELETE calendars":
        if (calendar(id) == null || !calendars.remove(id)) throw ApiException.notFound("No such calendar");
        return LocalHttp.Response.json(200, Json.object("rev", observe()));
      case "GET photos":
        byte[] image = id.matches("[a-f0-9]{64}") ? photos.read(id) : null;
        if (image == null) throw ApiException.notFound("No such photo");
        return LocalHttp.Response.jpeg(image);
      case "DELETE photos":
        if (!id.matches("[a-f0-9]{64}") || !photos.remove(id)) throw ApiException.notFound("No such photo");
        observe();
        return LocalHttp.Response.empty(204);
      default:
        throw ApiException.notFound("No such route");
    }
  }

  private static Map<String, Object> fields(LocalHttp.Body body) throws ApiException, IOException {
    return fields(body, MAX_JSON);
  }

  private static Map<String, Object> fields(LocalHttp.Body body, int limit) throws ApiException, IOException {
    try {
      String text = java.nio.charset.StandardCharsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(body.read(limit))).toString();
      Map<String, Object> fields = Json.map(Json.parse(text));
      if (fields == null) throw ApiException.badRequest("Expected a JSON object");
      return fields;
    } catch (java.nio.charset.CharacterCodingException notText) {
      throw ApiException.badRequest("The body is not UTF-8 text");
    } catch (Json.Malformed malformed) {
      throw ApiException.badRequest("Malformed JSON: " + malformed.getMessage());
    }
  }

  private LocalHttp.Response mutation(String op, String id, LocalHttp.Body body) throws ApiException, IOException {
    Map<String, Object> fields = body == null ? new LinkedHashMap<String, Object>() : fields(body);
    fields.put("op", op);
    fields.remove("id");
    if (id != null) fields.put("id", id);
    observe();
    return LocalHttp.Response.json(200, mutate(fields));
  }

  private LocalHttp.Response state(String since) throws ApiException {
    if (since != null && !since.matches("[0-9]{1,18}")) throw ApiException.badRequest("since must be a revision number");
    observe();
    Map<String, Object> state;
    synchronized (this) {
      state = household.snapshot(today());
      state.put("settings", Json.copy(settings));
    }
    Json.map(state.get("settings")).put("icloudAlbum", icloud.status());
    if (since != null && state.get("rev").equals(Long.valueOf(since))) return LocalHttp.Response.empty(304);
    List<Object> feeds = new ArrayList<>();
    for (Object feed : calendars.list()) feeds.add(calendarSummary(Json.map(feed)));
    state.put("calendars", feeds);
    state.put("photos", Json.object("count", photos.list().size()));
    return LocalHttp.Response.json(200, state);
  }

  private LocalHttp.Response setting(String key, Map<String, Object> value) {
    observe();
    long rev = merge(Json.object(key, value));
    events.settingsRequested(Json.write(Json.object(key, value)));
    return LocalHttp.Response.json(200, Json.object("rev", rev));
  }

  private static Map<String, Object> calendarSummary(Map<String, Object> feed) {
    return Json.object("id", feed.get("id"), "name", feed.get("name"), "color", feed.get("color"));
  }

  private Map<String, Object> calendar(String id) {
    for (Object feed : calendars.list()) if (Json.map(feed).get("id").equals(id)) return calendarSummary(Json.map(feed));
    return null;
  }

  private LocalHttp.Response addCalendar(Map<String, Object> fields) throws ApiException {
    String name = Fields.text(fields, "name", 1, 80);
    String color = Fields.color(fields, "color");
    Object url = fields.get("url");
    if (!(url instanceof String) || !CalendarFeed.valid((String) url)) {
      throw ApiException.badRequest("url must be a Google Calendar secret iCal address");
    }
    if (calendars.list().size() >= MAX_CALENDARS) throw ApiException.badRequest("The limit of " + MAX_CALENDARS + " calendars has been reached");
    String id = calendars.add(name, color, (String) url);
    if (id == null || id.isEmpty()) throw ApiException.conflict("That calendar is already on the frame");
    return LocalHttp.Response.json(200, Json.object("rev", observe(), "calendar", calendar(id)));
  }

  private Photo photo(String id) {
    for (Photo photo : photos.list()) if (photo.id.equals(id)) return photo;
    return null;
  }

  private static Map<String, Object> described(Photo photo) {
    return Json.object("id", photo.id, "addedAt", FrameTime.iso(photo.addedAt));
  }

  private LocalHttp.Response upload(LocalHttp.Request request, LocalHttp.Body body) throws ApiException, IOException {
    String type = request.headers.get("content-type");
    if (type == null || !type.toLowerCase(Locale.ROOT).startsWith("image/jpeg")) {
      throw ApiException.badRequest("Content-Type must be image/jpeg");
    }
    try {
      if (!uploads.tryAcquire(UPLOAD_WAIT_SECONDS, TimeUnit.SECONDS)) {
        throw ApiException.rateLimited("Another photo is being received. Try again shortly.");
      }
    } catch (InterruptedException stopping) {
      Thread.currentThread().interrupt();
      throw ApiException.rateLimited("The frame is busy. Try again shortly.");
    }
    try {
      byte[] jpeg = body.read(MAX_PHOTO);
      if (!PhotoPolicy.jpeg(jpeg)) throw ApiException.badRequest("The body is not a JPEG image");
      String id = Digests.sha256(jpeg);
      Photo saved = photo(id);
      if (saved == null) {
        if (!photos.add(jpeg, clock.now())) throw ApiException.badRequest("The frame could not use this picture");
        saved = photo(id);
        if (saved == null) throw ApiException.badRequest("The frame could not keep this picture");
      }
      return LocalHttp.Response.json(200, Json.object("rev", observe(), "photo", described(saved)));
    } finally {
      uploads.release();
    }
  }
}
