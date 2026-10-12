package com.wesbos.homehq;

import java.security.SecureRandom;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;

final class Pairing {
  interface Listener {
    void codeShown(String code, long expiresAt);

    void codeHidden();
  }

  static final long CODE_LIFETIME = 120000L;
  static final int MAX_WRONG = 5;
  static final int MAX_STARTS = 5;
  static final long START_WINDOW = 600000L;
  static final long FIRST_LOCKOUT = 300000L;
  static final long LONGEST_LOCKOUT = 3600000L;
  static final int MAX_DEVICES = 20;
  private static final String KEY = "devices";

  private final KeyValue storage;
  private final FrameTime.Clock clock;
  private final Listener listener;
  private final SecureRandom random = new SecureRandom();
  private final ArrayDeque<Long> starts = new ArrayDeque<>();
  private List<Object> devices = new ArrayList<>();
  private String code;
  private long expiresAt;
  private int wrong;
  private boolean exhausted;
  private int exhaustedCodes;
  private long lockedUntil;

  Pairing(KeyValue storage, FrameTime.Clock clock, Listener listener) {
    this.storage = storage;
    this.clock = clock;
    this.listener = listener;
    try {
      List<Object> saved = Json.list(Json.parse(storage.get(KEY)));
      for (Object device : saved) if (!(Json.map(device).get("hash") instanceof String)) throw new IllegalArgumentException();
      devices = saved;
    } catch (Json.Malformed | RuntimeException absentOrUnreadable) {
      devices = new ArrayList<>();
    }
  }

  synchronized void start() throws ApiException {
    long now = clock.now();
    while (!starts.isEmpty() && starts.peekFirst() <= now - START_WINDOW) starts.removeFirst();
    if (now < lockedUntil || starts.size() >= MAX_STARTS) {
      throw ApiException.rateLimited("Too many pairing attempts. Try again later.");
    }
    starts.addLast(now);
    code = String.format(Locale.ROOT, "%06d", random.nextInt(1000000));
    expiresAt = now + CODE_LIFETIME;
    wrong = 0;
    exhausted = false;
    listener.codeShown(code, expiresAt);
  }

  synchronized Map<String, Object> finish(Map<String, Object> fields) throws ApiException {
    Object offered = fields.get("code");
    if (!(offered instanceof String) || !((String) offered).matches("[0-9]{6}")) {
      throw ApiException.badRequest("code must be six digits");
    }
    String name = Fields.text(fields, "deviceName", 1, 80);
    expireIfDue();
    if (code == null) {
      if (exhausted) throw ApiException.rateLimited("Too many wrong codes. Start pairing again later.");
      throw ApiException.conflict("No pairing code is active. Start pairing again.");
    }
    if (!Digests.same(code, (String) offered)) {
      if (++wrong < MAX_WRONG) throw ApiException.unauthorized("That code is not correct.");
      exhausted = true;
      lockedUntil = clock.now() + Math.min(LONGEST_LOCKOUT, FIRST_LOCKOUT << Math.min(exhaustedCodes++, 4));
      clear();
      throw ApiException.rateLimited("Too many wrong codes. Start pairing again later.");
    }
    clear();
    if (devices.size() >= MAX_DEVICES) throw ApiException.conflict("Too many paired devices. Remove one on the frame.");
    exhaustedCodes = 0;
    lockedUntil = 0;
    String token = secret(32);
    Map<String, Object> device = Json.object("id", secret(8), "name", name,
        "pairedAt", FrameTime.iso(clock.now()), "hash", Digests.sha256(token.getBytes(java.nio.charset.StandardCharsets.US_ASCII)));
    devices.add(device);
    save();
    return Json.object("token", token, "deviceId", device.get("id"));
  }

  synchronized void expireIfDue() {
    if (code != null && clock.now() >= expiresAt) clear();
  }

  synchronized String authenticate(String token) {
    if (token == null || !token.matches("[0-9a-f]{64}")) return null;
    String hash = Digests.sha256(token.getBytes(java.nio.charset.StandardCharsets.US_ASCII));
    String matched = null;
    for (Object device : devices) {
      if (Digests.same((String) Json.map(device).get("hash"), hash)) matched = (String) Json.map(device).get("id");
    }
    return matched;
  }

  synchronized List<Object> devices() {
    List<Object> visible = new ArrayList<>();
    for (Object device : devices) {
      Map<String, Object> row = Json.map(device);
      visible.add(Json.object("id", row.get("id"), "name", row.get("name"), "pairedAt", row.get("pairedAt")));
    }
    return visible;
  }

  synchronized boolean revoke(String id) {
    for (Iterator<Object> rows = devices.iterator(); rows.hasNext();) {
      if (Json.map(rows.next()).get("id").equals(id)) {
        rows.remove();
        save();
        return true;
      }
    }
    return false;
  }

  synchronized boolean revokeAll() {
    devices.clear();
    save();
    return true;
  }

  private void clear() {
    code = null;
    wrong = 0;
    listener.codeHidden();
  }

  private String secret(int bytes) {
    byte[] value = new byte[bytes];
    random.nextBytes(value);
    return Digests.hex(value);
  }

  private void save() {
    storage.put(KEY, Json.write(devices));
  }
}
