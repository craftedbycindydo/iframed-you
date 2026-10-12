package com.wesbos.homehq;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

final class TccSync {
  interface Secrets {
    String[] load();

    void save(String username, String password);

    void clear();
  }

  interface Runner {
    void start(Runnable work);
  }

  interface Timer {
    void after(long millis, Runnable work);
  }

  interface Listener {
    void changed();
  }

  static final long WATCHED = 60000L;
  static final long IDLE = 5 * 60000L;
  static final long LONGEST_WAIT = 10 * 60000L;
  static final long STALE = 10 * 60000L;
  static final long SETTLE = 1000L;

  private final TccClient client;
  private final Secrets secrets;
  private final FrameTime.Clock clock;
  private final FrameTime.Uptime uptime;
  private final Runner runner;
  private final Timer timer;
  private final Listener listener;
  private final Object remote = new Object();
  private final Map<String, Double> pending = new HashMap<>();
  private final Map<String, Integer> taps = new HashMap<>();
  private final Map<String, String> errors = new HashMap<>();
  private List<TccClient.Device> devices = new ArrayList<>();
  private List<TccClient.State> states = new ArrayList<>();
  private String status;
  private long polledAt;
  private long polledUp;
  private long lastAttempt;
  private long lockedUntil;
  private long lockedUp;
  private int failures;
  private int generation;
  private boolean watched;
  private boolean polling;
  private boolean again;
  private boolean queued;

  TccSync(TccClient client, Secrets secrets, FrameTime.Clock clock, FrameTime.Uptime uptime, Runner runner, Timer timer, Listener listener) {
    this.client = client;
    this.secrets = secrets;
    this.clock = clock;
    this.uptime = uptime;
    this.runner = runner;
    this.timer = timer;
    this.listener = listener;
    String[] saved = secrets.load();
    if (saved != null && saved.length == 2 && saved[0] != null && saved[1] != null) {
      client.credentials(saved[0], saved[1]);
      status = "loading";
    } else {
      status = "unconfigured";
    }
  }

  void configure(String username, String password) throws TccClient.Problem {
    List<TccClient.Device> found;
    synchronized (remote) {
      boolean working;
      synchronized (this) {
        generation++;
        working = configured();
      }
      TccClient.Kept kept = client.keep();
      try {
        client.signIn(username, password);
        found = client.devices();
      } catch (TccClient.Problem problem) {
        if (working) {
          client.restore(kept);
        } else {
          client.signOut();
          secrets.clear();
          synchronized (this) {
            devices = new ArrayList<>();
            states = new ArrayList<>();
            status = "unconfigured";
          }
        }
        listener.changed();
        throw problem;
      }
      secrets.save(username, password);
      synchronized (this) {
        devices = found;
        states = new ArrayList<>();
        status = "loading";
        failures = 0;
        lastAttempt = 0;
      }
    }
    poll();
  }

  void forget() {
    synchronized (remote) {
      synchronized (this) {
        generation++;
        devices = new ArrayList<>();
        states = new ArrayList<>();
        pending.clear();
        errors.clear();
        status = "unconfigured";
        failures = 0;
        polledAt = 0;
      }
      secrets.clear();
      client.signOut();
    }
    listener.changed();
  }

  synchronized void watch(boolean visible) {
    watched = visible;
  }

  synchronized boolean configured() {
    return !"unconfigured".equals(status) && !"signed_out".equals(status);
  }

  synchronized long pause() {
    long cadence = watched ? WATCHED : IDLE;
    return failures == 0 ? cadence : Math.min(LONGEST_WAIT, cadence << Math.min(failures, 4));
  }

  synchronized boolean due() {
    if (!configured() || polling) return false;
    if ("locked_out".equals(status)) return uptime.millis() >= lockedUp;
    return lastAttempt == 0 || uptime.millis() - lastAttempt >= pause();
  }

  boolean request(final boolean force) {
    synchronized (this) {
      if (!configured()) return false;
      if (!force && !due() || queued) return true;
      if (polling) {
        again = true;
        return true;
      }
      queued = true;
    }
    runner.start(new Runnable() {
      @Override public void run() {
        synchronized (TccSync.this) {
          queued = false;
        }
        poll();
      }
    });
    return true;
  }

  void poll() {
    synchronized (this) {
      if (!configured()) return;
      if (polling) {
        again = true;
        return;
      }
      polling = true;
    }
    boolean repeat = true;
    while (repeat) {
      attempt();
      synchronized (this) {
        repeat = again && configured();
        again = false;
        if (!repeat) polling = false;
      }
    }
    listener.changed();
  }

  private void attempt() {
    int started;
    List<TccClient.Device> known;
    synchronized (this) {
      started = generation;
      known = devices;
      lastAttempt = uptime.millis();
    }
    List<TccClient.State> fresh = new ArrayList<>();
    TccClient.Problem failure = null;
    synchronized (remote) {
      try {
        if (known.isEmpty()) known = client.devices();
        for (TccClient.Device device : known) fresh.add(client.read(device));
      } catch (TccClient.Problem problem) {
        failure = problem;
      }
    }
    synchronized (this) {
      if (generation != started) return;
      devices = known;
      if (failure == null) {
        states = fresh;
        polledAt = clock.now();
        polledUp = uptime.millis();
        failures = 0;
        status = "ok";
      } else if ("bad_credentials".equals(failure.code) || "signed_out".equals(failure.code)) {
        status = "signed_out";
        states = new ArrayList<>();
      } else if ("locked".equals(failure.code)) {
        status = "locked_out";
        lockedUntil = failure.until;
        lockedUp = uptime.millis() + Math.max(0, failure.until - clock.now());
      } else {
        failures = Math.min(failures + 1, 10);
        if (failures >= 3 || !"ok".equals(status)) status = "unavailable";
      }
    }
    if (failure != null && ("bad_credentials".equals(failure.code) || "signed_out".equals(failure.code))) {
      secrets.clear();
      client.signOut();
    }
  }

  synchronized Map<String, Object> status() {
    long now = clock.now();
    long up = uptime.millis();
    if (polledAt != 0) polledAt = FrameTime.anchored(polledAt, now - (up - polledUp));
    if ("locked_out".equals(status)) lockedUntil = FrameTime.anchored(lockedUntil, now + lockedUp - up);
    String shown = "ok".equals(status) && up - polledUp > STALE ? "stale" : status;
    List<Object> thermostats = new ArrayList<>();
    String units = null;
    Double outdoorTemperature = null;
    Double outdoorHumidity = null;
    for (int i = 0; i < states.size(); i++) {
      TccClient.State state = states.get(i);
      String active = state.active();
      Double low = "heat".equals(active) ? state.heatMin : "cool".equals(active) ? state.coolMin : null;
      Double high = "heat".equals(active) ? state.heatMax : "cool".equals(active) ? state.coolMax : null;
      String id = "t" + (i + 1);
      Double waiting = pending.get(id);
      boolean starting = waiting != null && state.following();
      thermostats.add(Json.object("id", id, "name", state.name, "online", state.online, "units", state.units, "indoor", state.indoor,
          "humidity", state.humidity, "mode", state.mode, "heatAllowed", state.modes.contains("heat"), "coolAllowed", state.modes.contains("cool"),
          "setpoint", waiting != null ? waiting : setpoint(state), "changing", waiting != null, "error", errors.get(id),
          "heatSetpoint", state.heatSetpoint, "coolSetpoint", state.coolSetpoint,
          "range", low == null || high == null ? null : Json.object("min", low, "max", high), "step", "C".equals(state.units) ? 0.5 : 1.0,
          "hold", starting ? "temporary" : state.hold(), "holdUntil", starting ? state.nextPeriod() : state.holdUntil(), "running", state.running, "fan", state.fan, "fanRunning", state.fanRunning));
      if (units == null) units = state.units;
      if (outdoorTemperature == null) outdoorTemperature = state.outdoorTemperature;
      if (outdoorHumidity == null) outdoorHumidity = state.outdoorHumidity;
    }
    return Json.object("configured", configured(), "status", shown, "controllable", "ok".equals(shown), "polledAt", polledAt == 0 ? null : FrameTime.iso(polledAt),
        "retryAt", "locked_out".equals(status) ? FrameTime.iso(lockedUntil) : null, "units", units, "thermostats", thermostats,
        "outdoor", outdoorTemperature == null && outdoorHumidity == null ? null : Json.object("temperature", outdoorTemperature, "humidity", outdoorHumidity));
  }

  private static Double setpoint(TccClient.State state) {
    String active = state.active();
    return "heat".equals(active) ? state.heatSetpoint : "cool".equals(active) ? state.coolSetpoint : null;
  }

  double step(final String id, int steps, final boolean permanent) throws TccClient.Problem {
    final double wanted;
    final int tap;
    synchronized (this) {
      TccClient.State state = controllable(id);
      String active = state.active();
      Double current = pending.containsKey(id) ? pending.get(id) : setpoint(state);
      Double low = "heat".equals(active) ? state.heatMin : state.coolMin;
      Double high = "heat".equals(active) ? state.heatMax : state.coolMax;
      if (active == null || current == null || low == null || high == null) throw new TccClient.Problem("not_allowed");
      wanted = Math.min(high, Math.max(low, current + steps * ("C".equals(state.units) ? 0.5 : 1.0)));
      Double shown = setpoint(state);
      if (!pending.containsKey(id) && shown != null && shown == wanted) return wanted;
      pending.put(id, wanted);
      errors.remove(id);
      tap = taps.containsKey(id) ? taps.get(id) + 1 : 1;
      taps.put(id, tap);
    }
    listener.changed();
    timer.after(SETTLE, new Runnable() {
      @Override public void run() {
        synchronized (TccSync.this) {
          if (taps.get(id) == null || taps.get(id) != tap || !pending.containsKey(id)) return;
        }
        runner.start(new Runnable() {
          @Override public void run() {
            commit(id, tap, permanent);
          }
        });
      }
    });
    return wanted;
  }

  private void commit(String id, int tap, boolean permanent) {
    Double wanted;
    synchronized (this) {
      wanted = pending.get(id);
      if (wanted == null || taps.get(id) == null || taps.get(id) != tap) return;
    }
    String failure = null;
    try {
      setpoint(id, wanted, permanent);
    } catch (TccClient.Problem problem) {
      failure = problem.code;
    }
    synchronized (this) {
      if (taps.get(id) != null && taps.get(id) == tap) {
        pending.remove(id);
        if (failure != null) errors.put(id, failure);
      }
    }
    listener.changed();
  }

  private TccClient.State controllable(String id) throws TccClient.Problem {
    if (!"ok".equals(status) || uptime.millis() - polledUp > STALE) throw new TccClient.Problem("unavailable");
    TccClient.State state = null;
    for (int i = 0; i < states.size(); i++) if (("t" + (i + 1)).equals(id)) state = states.get(i);
    if (state == null) throw new TccClient.Problem("not_found");
    if (!state.online) throw new TccClient.Problem("unavailable");
    return state;
  }

  void setpoint(String id, final double value, final boolean permanent) throws TccClient.Problem {
    change(id, new Edit() {
      @Override public Map<String, Object> build(TccClient.State state) throws TccClient.Problem {
        String active = state.active();
        if (active == null) throw new TccClient.Problem("not_allowed");
        return state.setpoint(active, value, permanent);
      }
    });
  }

  void mode(String id, final String mode) throws TccClient.Problem {
    change(id, new Edit() {
      @Override public Map<String, Object> build(TccClient.State state) throws TccClient.Problem {
        return state.mode(mode);
      }
    });
  }

  void resume(String id) throws TccClient.Problem {
    change(id, new Edit() {
      @Override public Map<String, Object> build(TccClient.State state) {
        return state.resume();
      }
    });
  }

  private interface Edit {
    Map<String, Object> build(TccClient.State state) throws TccClient.Problem;
  }

  private void change(String id, Edit edit) throws TccClient.Problem {
    TccClient.State state;
    synchronized (this) {
      state = controllable(id);
    }
    Map<String, Object> change = edit.build(state);
    synchronized (remote) {
      client.apply(change);
    }
    synchronized (this) {
      lastAttempt = 0;
    }
    poll();
  }
}
