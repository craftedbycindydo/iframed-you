package com.wesbos.homehq;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public final class ThermostatBridgeTest {
  static int checks;
  static final List<Runnable> queue = new ArrayList<>();
  static final List<Runnable> timers = new ArrayList<>();
  static final List<String> pushed = new ArrayList<>();
  static final List<String> notes = new ArrayList<>();
  static TccTest.Vault vault;
  static ThermostatBridge bridge;

  static void check(boolean value, String message) {
    if (!value) throw new AssertionError(message);
    checks++;
  }

  static void same(Object expected, Object actual, String message) {
    check(expected == null ? actual == null : expected.equals(actual), message + ": expected " + expected + " but was " + actual);
  }

  static void drain() {
    while (!queue.isEmpty()) queue.remove(0).run();
  }

  static Map<String, Object> parsed(String json) throws Exception {
    return Json.map(Json.parse(json));
  }

  static Map<String, Object> shown() throws Exception {
    return parsed(bridge.snapshot());
  }

  static Map<String, Object> thermostat(int index) throws Exception {
    return Json.map(Json.list(shown().get("thermostats")).get(index));
  }

  static void launch() {
    queue.clear();
    timers.clear();
    pushed.clear();
    notes.clear();
    bridge = new ThermostatBridge(TccTest.client, vault, TccTest.clock, new TccSync.Runner() {
      @Override public void start(Runnable work) {
        queue.add(work);
      }
    }, new TccSync.Timer() {
      @Override public void after(long millis, Runnable work) {
        timers.add(work);
      }
    }, new ThermostatBridge.Output() {
      @Override public void changed(String snapshot) {
        pushed.add(snapshot);
      }

      @Override public void note(String event) {
        notes.add(event);
      }
    });
  }

  public static void main(String[] args) throws Exception {
    TccTest.fresh();
    vault = new TccTest.Vault();
    launch();
    Map<String, Object> empty = shown();
    same(false, empty.get("configured"), "starts signed out");
    same("unconfigured", empty.get("status"), "status when signed out");
    check(empty.get("account") == null && empty.get("signIn") == null && empty.get("message") == null, "nothing else is shown when signed out");
    same("[]", Json.write(empty.get("thermostats")), "no thermostats when signed out");

    for (String[] bad : new String[][] {{null, "x"}, {"", "x"}, {"not an email", "x"}, {"a@b", ""}, {"a@b", null}, {"a b@c", "x"}}) {
      Map<String, Object> refused = parsed(bridge.signIn(bad[0], bad[1]));
      same(false, refused.get("ok"), "incomplete sign-in is refused");
      same("Enter the account email and password.", refused.get("error"), "with a plain sentence");
    }
    check(queue.isEmpty() && TccTest.server.calls.isEmpty(), "an incomplete sign-in never reaches Honeywell");

    Map<String, Object> pending = parsed(bridge.signIn("  " + TccTest.USER + " ", "wrong"));
    check(Boolean.TRUE.equals(pending.get("ok")) && Boolean.TRUE.equals(pending.get("pending")), "sign-in returns at once as pending");
    same("{\"pending\":true}", Json.write(shown().get("signIn")), "the snapshot says a sign-in is pending");
    same("A sign-in is already in progress.", parsed(bridge.signIn(TccTest.USER, TccTest.PASS)).get("error"), "a second sign-in waits for the first");
    same(1, queue.size(), "the network work runs on the worker");
    drain();
    Map<String, Object> failed = Json.map(shown().get("signIn"));
    same(false, failed.get("ok"), "a wrong password fails");
    same("bad_credentials", failed.get("code"), "with its code");
    same("That email or password was not accepted.", failed.get("error"), "and a plain sentence");
    check(vault.saved == null && shown().get("account") == null, "a refused credential is not kept");
    check(notes.contains("Thermostat sign-in failed: bad_credentials"), "the failure code is noted for the log");
    for (String snapshot : pushed) check(!snapshot.contains("wrong") && !snapshot.contains(TccTest.PASS), "no snapshot carries a password");
    for (String note : notes) check(!note.contains("wrong") && !note.contains(TccTest.USER), "no note carries a credential");

    bridge.signIn(TccTest.USER, TccTest.PASS);
    drain();
    Map<String, Object> ready = shown();
    same("ok", ready.get("status"), "signed in and polled");
    same(TccTest.USER, ready.get("account"), "the account email is shown");
    check(ready.get("signIn") == null, "the sign-in result is cleared on success");
    same(2, Json.list(ready.get("thermostats")).size(), "both thermostats are listed");
    same("Level-0", thermostat(0).get("name"), "first thermostat");
    check(notes.contains("Thermostat sign-in succeeded") && notes.contains("Thermostat status: ok, 2 thermostats"), "success and status are noted");
    same(Json.write(ready), pushed.get(pushed.size() - 1), "the latest snapshot was pushed");
    check(!Json.write(ready).contains("1001") && !Json.write(ready).contains(TccTest.PASS), "no Honeywell id or password is in the snapshot");
    int before = pushed.size();
    bridge.publish();
    same(before, pushed.size(), "an unchanged snapshot is not pushed again");

    bridge.signIn(TccTest.USER, "mistyped");
    drain();
    Map<String, Object> mistyped = shown();
    same("bad_credentials", Json.map(mistyped.get("signIn")).get("code"), "a wrong password typed over a working account is refused");
    check(Boolean.TRUE.equals(mistyped.get("configured")) && "ok".equals(mistyped.get("status")) && TccTest.USER.equals(mistyped.get("account")), "but the working account stays signed in");
    check(vault.saved != null && TccTest.PASS.equals(vault.saved[1]), "with its credential still saved");
    same(2, Json.list(mistyped.get("thermostats")).size(), "and its thermostats still listed");

    Map<String, Object> stepped = parsed(bridge.step("t1", 5));
    same(true, stepped.get("ok"), "a step is accepted");
    same(71.0, stepped.get("setpoint"), "and moves one degree whatever the delta");
    same(72.0, parsed(bridge.step("t1", 1)).get("setpoint"), "rapid taps accumulate");
    same(71.0, parsed(bridge.step("t1", -1)).get("setpoint"), "in both directions");
    check(Boolean.TRUE.equals(thermostat(0).get("changing")) && Double.valueOf(71.0).equals(thermostat(0).get("setpoint")), "the pending setpoint shows as changing");
    int writes = TccTest.server.calls.size();
    while (!timers.isEmpty()) timers.remove(0).run();
    drain();
    check(TccTest.server.calls.size() > writes, "the settled value is written once the taps stop");
    check(Boolean.FALSE.equals(thermostat(0).get("changing")) && Double.valueOf(71.0).equals(thermostat(0).get("setpoint")), "and then shows as set");
    same(false, parsed(bridge.step("t9", 1)).get("ok"), "an unknown thermostat is refused");
    same("That thermostat is no longer listed.", parsed(bridge.step("t9", 1)).get("error"), "with a plain sentence");
    same(false, parsed(bridge.step("t1", 0)).get("ok"), "a zero step is refused");

    check(!bridge.mode("t1", "off") && !bridge.mode("t1", "auto") && !bridge.mode("t1", null) && queue.isEmpty(), "only heat and cool can be chosen");
    check(bridge.mode("t1", "cool"), "a mode change is accepted");
    check(Boolean.TRUE.equals(thermostat(0).get("changing")), "and shows as changing while it runs");
    check(!bridge.mode("t1", "heat") && !bridge.resume("t1"), "a second change waits for the first");
    drain();
    same("cool", thermostat(0).get("mode"), "the mode changed");
    check(Boolean.FALSE.equals(thermostat(0).get("changing")) && thermostat(0).get("error") == null, "and the tile settles");
    check(bridge.resume("t1"), "resume is accepted");
    drain();
    same("schedule", thermostat(0).get("hold"), "the schedule resumed");

    TccTest.server.rejects = true;
    check(bridge.mode("t2", "heat"), "a change Honeywell will refuse is still attempted");
    drain();
    check(thermostat(1).get("error") != null && thermostat(1).get("message") instanceof String, "a refused change leaves a plain message on that thermostat");
    check(thermostat(0).get("error") == null, "and not on the other");
    TccTest.server.rejects = false;
    check(bridge.mode("t2", "heat"), "trying again");
    drain();
    check(thermostat(1).get("error") == null && "heat".equals(thermostat(1).get("mode")), "clears the message when it works");

    bridge.watch(true);
    drain();
    TccTest.clock.now += TccSync.STALE + 1;
    before = pushed.size();
    bridge.tick();
    check(pushed.size() > before, "a tick pushes the change to stale");
    drain();
    same("ok", shown().get("status"), "and the poll it queued recovers");
    TccTest.server.unreachable = true;
    for (int attempt = 0; attempt < 4; attempt++) {
      TccTest.clock.now += TccSync.LONGEST_WAIT;
      bridge.wake();
      drain();
    }
    same("unavailable", shown().get("status"), "repeated failures show as unavailable");
    same("Honeywell could not be reached. Check Wi-Fi and try again.", shown().get("message"), "with a plain sentence");
    same(false, parsed(bridge.step("t1", 1)).get("ok"), "nothing can be changed while unavailable");
    TccTest.server.unreachable = false;
    bridge.wake();
    drain();
    same("ok", shown().get("status"), "waking after Wi-Fi returns recovers");

    launch();
    same("loading", shown().get("status"), "a restart restores the saved sign-in");
    same(TccTest.USER, shown().get("account"), "and its email");
    bridge.tick();
    drain();
    same("ok", shown().get("status"), "and polls on the first tick");

    check(bridge.signOut(), "sign out is accepted");
    drain();
    Map<String, Object> gone = shown();
    check(Boolean.FALSE.equals(gone.get("configured")) && gone.get("account") == null && vault.saved == null, "sign out forgets the account and credential");
    same("[]", Json.write(gone.get("thermostats")), "and the thermostats");
    check(notes.contains("Thermostat account removed from this frame"), "and notes it");

    for (String code : new String[] {"bad_credentials", "signed_out", "locked", "locked_out", "throttled", "stale", "unavailable", "offline", "not_allowed", "out_of_range",
        "rejected", "not_found", "login_failed", "session_expired", "foreign_host", "unexpected", "something_new"}) {
      String sentence = ThermostatBridge.message(code);
      check(sentence != null && sentence.endsWith(".") && !sentence.contains("_") && Character.isUpperCase(sentence.charAt(0)), "a plain sentence for " + code);
    }
    check(ThermostatBridge.message("ok") == null && ThermostatBridge.message(null) == null && ThermostatBridge.message("loading") == null, "no message when nothing is wrong");
    System.out.println("ThermostatBridge: " + checks + " checks passed");
  }
}
