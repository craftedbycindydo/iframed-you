package com.wesbos.homehq;

import java.util.HashMap;
import java.util.Map;

final class ThermostatBridge {
  interface Output {
    void changed(String snapshot);

    void note(String event);
  }

  private final TccSync sync;
  private final TccSync.Runner runner;
  private final Output output;
  private final Map<String, String> working = new HashMap<>();
  private final Map<String, String> problems = new HashMap<>();
  private Map<String, Object> signIn;
  private String account;
  private String shown;
  private String noted;

  ThermostatBridge(TccClient client, final TccSync.Secrets secrets, FrameTime.Clock clock, TccSync.Runner runner, TccSync.Timer timer, Output output) {
    this.runner = runner;
    this.output = output;
    TccSync.Secrets remembering = new TccSync.Secrets() {
      @Override public String[] load() {
        String[] saved = secrets.load();
        remember(saved != null && saved.length == 2 ? saved[0] : null);
        return saved;
      }

      @Override public void save(String username, String password) {
        secrets.save(username, password);
        remember(username);
      }

      @Override public void clear() {
        secrets.clear();
        remember(null);
      }
    };
    sync = new TccSync(client, remembering, clock, runner, timer, new TccSync.Listener() {
      @Override public void changed() {
        publish();
      }
    });
  }

  private synchronized void remember(String email) {
    account = email;
  }

  static String message(String code) {
    if (code == null) return null;
    switch (code) {
      case "ok":
      case "loading":
      case "unconfigured":
        return null;
      case "bad_credentials":
        return "That email or password was not accepted.";
      case "signed_out":
        return "Honeywell signed this frame out. Sign in again.";
      case "locked":
      case "locked_out":
      case "throttled":
        return "Too many attempts. Try again later.";
      case "stale":
        return "Not updated recently. Trying again.";
      case "unavailable":
      case "offline":
        return "Honeywell could not be reached. Check Wi-Fi and try again.";
      case "not_allowed":
        return "This thermostat does not allow that.";
      case "out_of_range":
        return "That temperature is outside this thermostat's range.";
      case "rejected":
        return "The thermostat did not accept the change.";
      case "not_found":
        return "That thermostat is no longer listed.";
      case "busy":
        return "A sign-in is already in progress.";
      case "incomplete":
        return "Enter the account email and password.";
      default:
        return "Honeywell did not answer as expected. Try again later.";
    }
  }

  String snapshot() {
    Map<String, Object> status = sync.status();
    synchronized (this) {
      status.put("account", Boolean.TRUE.equals(status.get("configured")) ? account : null);
      status.put("message", message((String) status.get("status")));
      status.put("signIn", signIn == null ? null : Json.copy(signIn));
      for (Object row : Json.list(status.get("thermostats"))) {
        Map<String, Object> thermostat = Json.map(row);
        Object id = thermostat.get("id");
        if (working.containsKey(id)) thermostat.put("changing", true);
        String code = thermostat.get("error") instanceof String ? (String) thermostat.get("error") : problems.get(id);
        thermostat.put("error", code);
        thermostat.put("message", message(code));
      }
    }
    return Json.write(status);
  }

  void publish() {
    String next = snapshot();
    String event = null;
    synchronized (this) {
      if (next.equals(shown)) return;
      shown = next;
      try {
        Map<String, Object> status = Json.map(Json.parse(next));
        String summary = status.get("status") + ", " + Json.list(status.get("thermostats")).size() + " thermostats";
        if (!summary.equals(noted)) event = "Thermostat status: " + summary;
        noted = summary;
      } catch (Json.Malformed impossible) {
        throw new IllegalStateException(impossible);
      }
    }
    if (event != null) output.note(event);
    output.changed(next);
  }

  private static String refusal(String code) {
    return Json.write(Json.object("ok", false, "error", message(code)));
  }

  String signIn(String email, final String password) {
    final String name = email == null ? "" : email.trim();
    if (!name.matches("[^\\s@]{1,64}@[^\\s@]{1,190}") || password == null || password.isEmpty() || password.length() > 256) return refusal("incomplete");
    synchronized (this) {
      if (signIn != null && Boolean.TRUE.equals(signIn.get("pending"))) return refusal("busy");
      signIn = Json.object("pending", true);
    }
    publish();
    runner.start(new Runnable() {
      @Override public void run() {
        Map<String, Object> result = null;
        try {
          sync.configure(name, password);
          output.note("Thermostat sign-in succeeded");
        } catch (TccClient.Problem problem) {
          result = Json.object("ok", false, "code", problem.code, "error", message(problem.code), "retryAt", problem.until > 0 ? FrameTime.iso(problem.until) : null);
          output.note("Thermostat sign-in failed: " + problem.code);
        } catch (RuntimeException unexpected) {
          result = Json.object("ok", false, "code", "unexpected", "error", message("unexpected"), "retryAt", null);
          output.note("Thermostat sign-in failed: " + unexpected.getClass().getSimpleName());
        }
        synchronized (ThermostatBridge.this) {
          signIn = result;
          problems.clear();
        }
        publish();
      }
    });
    return Json.write(Json.object("ok", true, "pending", true));
  }

  boolean signOut() {
    synchronized (this) {
      signIn = null;
      problems.clear();
    }
    runner.start(new Runnable() {
      @Override public void run() {
        sync.forget();
        output.note("Thermostat account removed from this frame");
        publish();
      }
    });
    return true;
  }

  String step(String id, int delta) {
    if (delta == 0) return refusal("not_allowed");
    try {
      double setpoint = sync.step(id, delta > 0 ? 1 : -1, false);
      synchronized (this) {
        problems.remove(id);
      }
      return Json.write(Json.object("ok", true, "setpoint", setpoint));
    } catch (TccClient.Problem problem) {
      return refusal(problem.code);
    }
  }

  private interface Change {
    void apply() throws TccClient.Problem;
  }

  private boolean change(final String id, final String what, final Change change) {
    synchronized (this) {
      if (id == null || working.containsKey(id)) return false;
      working.put(id, what);
      problems.remove(id);
    }
    publish();
    runner.start(new Runnable() {
      @Override public void run() {
        String failure = null;
        try {
          change.apply();
        } catch (TccClient.Problem problem) {
          failure = problem.code;
        } catch (RuntimeException unexpected) {
          failure = "unexpected";
        }
        synchronized (ThermostatBridge.this) {
          working.remove(id);
          if (failure != null) problems.put(id, failure);
        }
        if (failure != null) output.note("Thermostat " + what + " failed: " + failure);
        publish();
      }
    });
    return true;
  }

  boolean mode(final String id, final String mode) {
    if (!"heat".equals(mode) && !"cool".equals(mode)) return false;
    return change(id, "mode change", new Change() {
      @Override public void apply() throws TccClient.Problem {
        sync.mode(id, mode);
      }
    });
  }

  boolean resume(final String id) {
    return change(id, "resume", new Change() {
      @Override public void apply() throws TccClient.Problem {
        sync.resume(id);
      }
    });
  }

  void watch(boolean visible) {
    sync.watch(visible);
    if (visible) sync.request(false);
  }

  void tick() {
    sync.request(false);
    publish();
  }

  void wake() {
    sync.request(true);
  }
}
