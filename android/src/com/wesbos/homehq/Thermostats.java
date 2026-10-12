package com.wesbos.homehq;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class Thermostats {
  private static final String TAG = "Skylit";
  private static final long TICK = 15000L;

  interface Screen {
    boolean showing();
  }

  final ThermostatBridge bridge;
  private final Handler main = new Handler(Looper.getMainLooper());
  private final ExecutorService worker = Executors.newSingleThreadExecutor();
  private final ConnectivityManager connectivity;
  private final Screen screen;
  private boolean running;
  private boolean watchingNetwork;

  private final Runnable tick = new Runnable() {
    @Override public void run() {
      bridge.watch(screen.showing());
      bridge.tick();
      main.postDelayed(this, TICK);
    }
  };

  private final ConnectivityManager.NetworkCallback network = new ConnectivityManager.NetworkCallback() {
    @Override public void onAvailable(Network joined) {
      bridge.wake();
    }
  };

  Thermostats(Context context, final PhoneLink.Dashboard dashboard, Screen screen) {
    this.screen = screen;
    Context app = context.getApplicationContext();
    connectivity = (ConnectivityManager) app.getSystemService(Context.CONNECTIVITY_SERVICE);
    final SharedPreferences saved = app.getSharedPreferences("skylit-thermostat", Context.MODE_PRIVATE);
    KeyValue storage = new KeyValue() {
      @Override public String get(String key) {
        return saved.getString(key, null);
      }

      @Override public void put(String key, String value) {
        if (!saved.edit().putString(key, value).commit()) Log.e(TAG, "Could not save thermostat data: " + key);
      }
    };
    FrameTime.Clock clock = new FrameTime.Clock() {
      @Override public long now() {
        return System.currentTimeMillis();
      }
    };
    FrameTime.Uptime uptime = new FrameTime.Uptime() {
      @Override public long millis() {
        return SystemClock.elapsedRealtime();
      }
    };
    TccSync.Secrets secrets = new TccSync.Secrets() {
      @Override public String[] load() {
        String email = saved.getString("email", null);
        String sealed = saved.getString("password", null);
        if (email == null || sealed == null) return null;
        try {
          return new String[] {email, TccSecret.open(sealed, email)};
        } catch (Exception unreadable) {
          Log.w(TAG, "Thermostat sign-in could not be restored: " + unreadable.getClass().getSimpleName());
          return null;
        }
      }

      @Override public void save(String username, String password) {
        try {
          if (!saved.edit().putString("email", username).putString("password", TccSecret.seal(password, username)).commit()) {
            Log.e(TAG, "Thermostat sign-in could not be saved");
          }
        } catch (Exception unavailable) {
          Log.e(TAG, "Thermostat sign-in could not be sealed: " + unavailable.getClass().getSimpleName());
        }
      }

      @Override public void clear() {
        saved.edit().remove("email").remove("password").commit();
        try {
          TccSecret.forget();
        } catch (Exception unavailable) {
          Log.w(TAG, "Thermostat key could not be removed: " + unavailable.getClass().getSimpleName());
        }
      }
    };
    TccSync.Runner runner = new TccSync.Runner() {
      @Override public void start(Runnable work) {
        try {
          worker.execute(work);
        } catch (RuntimeException stopped) {
          Log.w(TAG, "Thermostat worker is stopped");
        }
      }
    };
    TccSync.Timer timer = new TccSync.Timer() {
      @Override public void after(long millis, Runnable work) {
        main.postDelayed(work, millis);
      }
    };
    bridge = new ThermostatBridge(new TccClient(new TccHttp(), storage, clock, uptime), secrets, clock, uptime, runner, timer, new ThermostatBridge.Output() {
      @Override public void changed(final String snapshot) {
        main.post(new Runnable() {
          @Override public void run() {
            if (running) dashboard.evaluate("window.SkylitThermostat&&window.SkylitThermostat.receive(" + snapshot + ")");
          }
        });
      }

      @Override public void note(String event) {
        Log.i(TAG, event);
      }
    });
  }

  void start() {
    if (running) return;
    running = true;
    main.post(tick);
    NetworkRequest lan = new NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
        .addTransportType(NetworkCapabilities.TRANSPORT_ETHERNET).build();
    try {
      connectivity.registerNetworkCallback(lan, network);
      watchingNetwork = true;
    } catch (RuntimeException denied) {
      Log.w(TAG, "Network changes cannot be watched for thermostats", denied);
    }
  }

  void stop() {
    running = false;
    main.removeCallbacksAndMessages(null);
    worker.shutdownNow();
    if (watchingNetwork) {
      try {
        connectivity.unregisterNetworkCallback(network);
      } catch (RuntimeException notWatching) {
        Log.w(TAG, "Thermostat network watch was already removed");
      }
      watchingNetwork = false;
    }
  }
}
