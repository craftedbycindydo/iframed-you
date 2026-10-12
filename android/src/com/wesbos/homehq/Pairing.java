package com.wesbos.homehq;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

final class Pairing {
  interface Listener {
    void changed(Map<String, Object> state, long remaining);
  }

  static final long WINDOW = 120000L;
  static final long SEEN_INTERVAL = 86400000L;
  static final int MAX_DEVICES = 20;
  private static final byte[] LABEL = "skylit-pair-v2\0".getBytes(StandardCharsets.US_ASCII);
  private static final int WAITING = 202;
  private static final int APPROVED = 200;
  private static final int REFUSED = 403;
  private static final int EXPIRED = 410;

  private final Identity identity;
  private final FrameTime.Clock clock;
  private final FrameTime.Uptime uptime;
  private final Listener listener;
  private final SecureRandom random = new SecureRandom();
  private final List<Object> devices;
  private String phase = "idle";
  private String reason;
  private long closesAt;
  private String session;
  private int outcome;
  private byte[] commit;
  private byte[] nF;
  private String tokenHash;
  private String name;
  private String deviceId;
  private String code;
  private String pick;
  private List<Object> numbers;

  Pairing(Identity identity, FrameTime.Clock clock, FrameTime.Uptime uptime, Listener listener) {
    this.identity = identity;
    this.clock = clock;
    this.uptime = uptime;
    this.listener = listener;
    devices = identity.devices();
  }

  static byte[] digest(byte[] nP, byte[] nF, byte[] fpRaw) {
    try {
      byte[] key = new byte[nP.length + nF.length];
      System.arraycopy(nP, 0, key, 0, nP.length);
      System.arraycopy(nF, 0, key, nP.length, nF.length);
      Mac mac = Mac.getInstance("HmacSHA256");
      mac.init(new SecretKeySpec(key, "HmacSHA256"));
      mac.update(LABEL);
      return mac.doFinal(fpRaw);
    } catch (GeneralSecurityException missing) {
      throw new IllegalStateException(missing);
    }
  }

  private static long u32be(byte[] bytes, int at) {
    return (bytes[at] & 0xFFL) << 24 | (bytes[at + 1] & 0xFFL) << 16 | (bytes[at + 2] & 0xFFL) << 8 | bytes[at + 3] & 0xFFL;
  }

  static String code(byte[] digest) {
    return String.format(Locale.ROOT, "%06d", u32be(digest, 0) % 1000000L);
  }

  static String pick(byte[] digest) {
    return String.format(Locale.ROOT, "%02d", u32be(digest, 4) % 100L);
  }

  private static byte[] hex(Map<String, Object> fields, String key, int length) throws ApiException {
    byte[] bytes = Digests.bytes(fields.get(key));
    if (bytes == null || bytes.length != length) throw ApiException.badRequest(key + " must be " + length * 2 + " lowercase hex characters");
    return bytes;
  }

  synchronized Map<String, Object> open() throws ApiException {
    if (devices.size() >= MAX_DEVICES) throw ApiException.conflict("Too many paired devices. Remove one on the frame.");
    session = null;
    outcome = 0;
    closesAt = uptime.millis() + WINDOW;
    show("waiting", null);
    return state();
  }

  synchronized boolean accepting() {
    expireIfDue();
    return phase.equals("waiting") && session == null;
  }

  synchronized Map<String, Object> start(Map<String, Object> fields) throws ApiException {
    byte[] offeredCommit = hex(fields, "commit", 32);
    String offeredHash = Digests.hex(hex(fields, "tokenHash", 32));
    String offeredName = Fields.text(fields, "deviceName", 1, 40);
    expireIfDue();
    if (active() && session != null) throw ApiException.pairingBusy("Another phone is already using this pairing window. Tap Pair a phone on the frame again.");
    if (!phase.equals("waiting")) throw ApiException.conflict("No pairing window is open. Tap Pair a phone on the frame.");
    commit = offeredCommit;
    tokenHash = offeredHash;
    name = offeredName;
    nF = new byte[32];
    random.nextBytes(nF);
    session = secret(16);
    outcome = WAITING;
    return Json.object("session", session, "nF", Digests.hex(nF));
  }

  synchronized void reveal(Map<String, Object> fields) throws ApiException {
    byte[] offered = hex(fields, "session", 16);
    byte[] nP = hex(fields, "nP", 32);
    current(offered);
    if (!phase.equals("waiting")) throw ApiException.conflict("This pairing session was already revealed");
    if (!MessageDigest.isEqual(Digests.digest(nP), commit)) {
      end(REFUSED, "refused");
      throw ApiException.badRequest("nP does not match the commitment");
    }
    byte[] digest = digest(nP, nF, identity.fpRaw);
    code = code(digest);
    pick = pick(digest);
    numbers = new ArrayList<>();
    numbers.add(pick);
    while (numbers.size() < 3) {
      String decoy = String.format(Locale.ROOT, "%02d", random.nextInt(100));
      if (!numbers.contains(decoy)) numbers.add(decoy);
    }
    Collections.shuffle(numbers, random);
    show("code", null);
  }

  synchronized void cancel(Map<String, Object> fields) throws ApiException {
    byte[] offered = hex(fields, "session", 16);
    expireIfDue();
    if (session == null || !MessageDigest.isEqual(offered, Digests.bytes(session))) throw ApiException.conflict("No such pairing session");
    if (outcome == WAITING) end(REFUSED, "phone");
  }

  synchronized Map<String, Object> result(String offered) throws ApiException {
    byte[] asked = Digests.bytes(offered);
    if (asked == null || asked.length != 16) throw ApiException.badRequest("session must be 32 lowercase hex characters");
    expireIfDue();
    if (session == null || !MessageDigest.isEqual(asked, Digests.bytes(session))) throw ApiException.notFound("No such pairing session");
    if (outcome == REFUSED) throw ApiException.forbidden("Pairing was cancelled on the frame");
    if (outcome == EXPIRED) throw ApiException.gone("The pairing window closed");
    return outcome == APPROVED ? Json.object("deviceId", deviceId) : null;
  }

  synchronized boolean tap(String number) {
    expireIfDue();
    if (!phase.equals("code") || number == null) return false;
    if (!MessageDigest.isEqual(number.getBytes(StandardCharsets.UTF_8), pick.getBytes(StandardCharsets.UTF_8))) {
      end(REFUSED, "decoy");
      return false;
    }
    String now = FrameTime.iso(clock.now());
    deviceId = secret(8);
    for (Iterator<Object> rows = devices.iterator(); rows.hasNext();) {
      if (Digests.same((String) Json.map(rows.next()).get("hash"), tokenHash)) rows.remove();
    }
    devices.add(Json.object("id", deviceId, "name", name, "pairedAt", now, "lastSeen", now, "hash", tokenHash));
    identity.save();
    outcome = APPROVED;
    show("paired", null);
    return true;
  }

  synchronized boolean dismiss() {
    expireIfDue();
    if (phase.equals("idle")) return false;
    if (active()) end(REFUSED, "frame");
    else show("idle", null);
    return true;
  }

  synchronized void expireIfDue() {
    if (active() && uptime.millis() >= closesAt) end(EXPIRED, "expired");
  }

  synchronized Map<String, Object> state() {
    Map<String, Object> state = Json.object("phase", phase);
    if (active()) state.put("remaining", Math.max(0, closesAt - uptime.millis()));
    if (phase.equals("code")) {
      state.put("code", code);
      state.put("numbers", new ArrayList<>(numbers));
    }
    if (phase.equals("paired")) state.put("name", name);
    if (phase.equals("cancelled")) state.put("reason", reason);
    return state;
  }

  synchronized String pick() {
    return phase.equals("code") ? pick : null;
  }

  synchronized String authenticate(String token) {
    byte[] raw = Digests.bytes(token);
    if (raw == null || raw.length != 32) return null;
    String hash = Digests.sha256(raw);
    Map<String, Object> matched = null;
    for (Object device : devices) if (Digests.same((String) Json.map(device).get("hash"), hash)) matched = Json.map(device);
    if (matched == null) return null;
    long now = clock.now();
    if (now - FrameTime.instant(matched.get("lastSeen")) >= SEEN_INTERVAL) {
      matched.put("lastSeen", FrameTime.iso(now));
      identity.save();
    }
    return (String) matched.get("id");
  }

  synchronized List<Object> devices(String caller) {
    List<Object> visible = new ArrayList<>();
    for (Object device : devices) {
      Map<String, Object> row = Json.map(device);
      Map<String, Object> shown = Json.object("id", row.get("id"), "name", row.get("name"), "pairedAt", row.get("pairedAt"), "lastSeen", row.get("lastSeen"));
      if (caller != null) shown.put("self", caller.equals(row.get("id")));
      visible.add(shown);
    }
    return visible;
  }

  synchronized boolean revoke(String id) {
    for (Iterator<Object> rows = devices.iterator(); rows.hasNext();) {
      if (Json.map(rows.next()).get("id").equals(id)) {
        rows.remove();
        identity.save();
        return true;
      }
    }
    return false;
  }

  synchronized boolean revokeAll() {
    devices.clear();
    identity.save();
    return true;
  }

  private boolean active() {
    return phase.equals("waiting") || phase.equals("code");
  }

  private void current(byte[] offered) throws ApiException {
    expireIfDue();
    if (session == null || !MessageDigest.isEqual(offered, Digests.bytes(session))) throw ApiException.conflict("No such pairing session");
    if (outcome == EXPIRED) throw ApiException.gone("The pairing window closed");
    if (outcome != WAITING) throw ApiException.conflict("This pairing session has ended");
  }

  private void end(int result, String why) {
    if (session != null) outcome = result;
    show("cancelled", why);
  }

  private void show(String next, String why) {
    phase = next;
    reason = why;
    if (!phase.equals("code")) {
      code = null;
      pick = null;
      numbers = null;
    }
    listener.changed(state(), active() ? Math.max(0, closesAt - uptime.millis()) : -1);
  }

  private String secret(int bytes) {
    byte[] value = new byte[bytes];
    random.nextBytes(value);
    return Digests.hex(value);
  }
}
