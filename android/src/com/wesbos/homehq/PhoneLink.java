package com.wesbos.homehq;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONArray;

final class PhoneLink implements LocalApi.Events {
  interface Dashboard {
    boolean evaluate(String script);
  }

  private static final String TAG = "Skylit";
  private static final String SERVICE_TYPE = "_skylit._tcp";

  final LocalApi api;
  private final Handler main = new Handler(Looper.getMainLooper());
  private final Dashboard dashboard;
  private final LocalServer server;
  private final ICloudSync icloud;
  private final ExecutorService albumWorker = Executors.newSingleThreadExecutor();
  private final NsdManager nsd;
  private final ConnectivityManager connectivity;
  private final WifiManager.MulticastLock multicast;
  private final Map<String, Object> waitingSettings = new LinkedHashMap<>();
  private NsdManager.RegistrationListener registration;
  private boolean running;
  private boolean watchingNetwork;
  private volatile boolean advertised;
  private volatile int port;

  private final Runnable expirePairing = new Runnable() {
    @Override public void run() {
      api.expirePairing();
    }
  };

  private final Runnable albumCheck = new Runnable() {
    @Override public void run() {
      icloud.request(false);
      main.postDelayed(this, 60000L);
    }
  };

  private final Runnable advertise = new Runnable() {
    @Override public void run() {
      withdraw.run();
      if (!running || port == 0) return;
      NsdServiceInfo service = new NsdServiceInfo();
      service.setServiceName(LocalApi.NAME);
      service.setServiceType(SERVICE_TYPE);
      service.setPort(port);
      service.setAttribute("v", "2");
      service.setAttribute("id", api.frameId());
      final NsdManager.RegistrationListener attempt = new NsdManager.RegistrationListener() {
        @Override public void onServiceRegistered(NsdServiceInfo registered) {
          final NsdManager.RegistrationListener self = this;
          main.post(new Runnable() {
            @Override public void run() {
              if (registration == self) advertised = true;
            }
          });
        }

        @Override public void onRegistrationFailed(NsdServiceInfo failed, int error) {
          Log.w(TAG, "Phone discovery could not be advertised: " + error);
          final NsdManager.RegistrationListener self = this;
          main.post(new Runnable() {
            @Override public void run() {
              if (registration == self) registration = null;
            }
          });
        }

        @Override public void onServiceUnregistered(NsdServiceInfo unregistered) {}

        @Override public void onUnregistrationFailed(NsdServiceInfo failed, int error) {}
      };
      try {
        nsd.registerService(service, NsdManager.PROTOCOL_DNS_SD, attempt);
        registration = attempt;
      } catch (RuntimeException unavailable) {
        Log.w(TAG, "Phone discovery is unavailable", unavailable);
      }
    }
  };

  private final Runnable withdraw = new Runnable() {
    @Override public void run() {
      advertised = false;
      if (registration == null) return;
      try {
        nsd.unregisterService(registration);
      } catch (RuntimeException notRegistered) {
        Log.w(TAG, "Phone discovery was already withdrawn");
      }
      registration = null;
    }
  };

  private final ConnectivityManager.NetworkCallback network = new ConnectivityManager.NetworkCallback() {
    @Override public void onAvailable(Network joined) {
      main.post(advertise);
      if (icloud.troubled()) icloud.request(true);
    }

    @Override public void onLost(Network left) {
      main.post(withdraw);
    }
  };

  PhoneLink(Context context, final CalendarStore calendars, final PhotoStore photos, final PhotoMail mail, Dashboard dashboard) {
    this.dashboard = dashboard;
    Context app = context.getApplicationContext();
    nsd = (NsdManager) app.getSystemService(Context.NSD_SERVICE);
    connectivity = (ConnectivityManager) app.getSystemService(Context.CONNECTIVITY_SERVICE);
    multicast = ((WifiManager) app.getSystemService(Context.WIFI_SERVICE)).createMulticastLock("skylit-phone");
    multicast.setReferenceCounted(false);
    final SharedPreferences saved = app.getSharedPreferences("skylit-phone", Context.MODE_PRIVATE);
    KeyValue storage = new KeyValue() {
      @Override public String get(String key) {
        return saved.getString(key, null);
      }

      @Override public void put(String key, String value) {
        if (!saved.edit().putString(key, value).commit()) Log.e(TAG, "Could not save phone link data: " + key);
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
    LocalApi.Calendars feeds = new LocalApi.Calendars() {
      @Override public List<Object> list() {
        try {
          return Json.list(Json.parse(calendars.labels()));
        } catch (Json.Malformed unreadable) {
          return new ArrayList<>();
        }
      }

      @Override public String add(String name, String color, String url) {
        final String id = calendars.add(name, color, url);
        if (!id.isEmpty()) {
          calendars.refresh(id, new CalendarStore.Receiver() {
            @Override public void accept(String result) {
              show("window.SkylitCalendar&&window.SkylitCalendar.receive(" + result + ")");
            }
          });
        }
        return id;
      }

      @Override public boolean remove(String id) {
        boolean removed = calendars.remove(id);
        if (removed) {
          show("window.SkylitCalendar&&window.SkylitCalendar.receive(" + Json.write(Json.object("id", id, "removed", true,
              "error", "This calendar was removed from a paired phone.")) + ")");
        }
        return removed;
      }
    };
    LocalApi.Photos library = new LocalApi.Photos() {
      @Override public List<LocalApi.Photo> list() {
        List<LocalApi.Photo> visible = new ArrayList<>();
        JSONArray rows = photos.list();
        JSONArray hidden = photos.excluded();
        HashSet<String> excluded = new HashSet<>();
        for (int i = 0; i < hidden.length(); i++) excluded.add(hidden.optString(i));
        for (int i = 0; i < rows.length(); i++) {
          String id = rows.optJSONObject(i).optString("id");
          if (!excluded.contains(id)) visible.add(new LocalApi.Photo(id, rows.optJSONObject(i).optLong("at")));
        }
        return visible;
      }

      @Override public boolean add(byte[] jpeg, long addedAt) {
        try {
          photos.add(jpeg, addedAt, "phone");
          mail.libraryChanged();
          return true;
        } catch (Exception | OutOfMemoryError unusable) {
          Log.w(TAG, "A phone picture could not be stored");
          return false;
        }
      }

      @Override public byte[] read(String id) {
        try (InputStream in = photos.open(id); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
          byte[] buffer = new byte[32768];
          for (int count; (count = in.read(buffer)) >= 0;) out.write(buffer, 0, count);
          return out.toByteArray();
        } catch (Exception missing) {
          return null;
        }
      }

      @Override public boolean remove(String id) {
        boolean removed = photos.remove(id);
        if (removed) mail.libraryChanged();
        return removed;
      }
    };
    ICloudSync.Library albumLibrary = new ICloudSync.Library() {
      @Override public List<ICloudAlbum.Stored> pictures() {
        List<ICloudAlbum.Stored> visible = new ArrayList<>();
        JSONArray rows = photos.list();
        Set<String> hidden = excluded();
        for (int i = 0; i < rows.length(); i++) {
          String id = rows.optJSONObject(i).optString("id");
          if (!hidden.contains(id)) {
            visible.add(new ICloudAlbum.Stored(id, rows.optJSONObject(i).optLong("at"), "album".equals(rows.optJSONObject(i).optString("origin"))));
          }
        }
        return visible;
      }

      @Override public Set<String> excluded() {
        JSONArray hidden = photos.excluded();
        Set<String> ids = new HashSet<>();
        for (int i = 0; i < hidden.length(); i++) ids.add(hidden.optString(i));
        return ids;
      }

      @Override public boolean add(byte[] image, long at) {
        try {
          photos.add(image, at, "album");
        } catch (Exception | OutOfMemoryError unusable) {
          Log.w(TAG, "A shared album picture could not be stored");
          return false;
        }
        mail.libraryChanged();
        String id = Digests.sha256(image);
        for (ICloudAlbum.Stored picture : pictures()) if (picture.id.equals(id)) return true;
        return false;
      }

      @Override public void remove(String id) {
        if (photos.removeOrigin("album", id) > 0) mail.libraryChanged();
      }

      @Override public void removeAll() {
        if (photos.removeOrigin("album", null) > 0) mail.libraryChanged();
      }

      @Override public int capacity() {
        return mail.capacity();
      }
    };
    icloud = new ICloudSync(storage, clock, uptime, new ICloudHttp(), albumLibrary, new ICloudSync.Runner() {
      @Override public void start(Runnable work) {
        try {
          albumWorker.execute(work);
        } catch (RuntimeException stopped) {
          Log.w(TAG, "Shared album sync is stopped");
        }
      }
    }, new ICloudSync.Listener() {
      @Override public void changed() {
        show("window.SkylitICloud&&window.SkylitICloud.receive(" + api.icloudStatus() + ")");
      }
    });
    api = new LocalApi(storage, clock, uptime, feeds, library, icloud, this);
    server = new LocalServer(api);
  }

  void start() {
    if (running) return;
    running = true;
    main.post(albumCheck);
    try {
      multicast.acquire();
    } catch (RuntimeException denied) {
      Log.w(TAG, "Multicast lock unavailable", denied);
    }
    new Thread(new Runnable() {
      @Override public void run() {
        try {
          final int bound = server.start(null, LocalServer.PREFERRED_PORT);
          main.post(new Runnable() {
            @Override public void run() {
              if (!running) {
                stopServer();
                return;
              }
              port = bound;
              Log.i(TAG, "Phone API listening on port " + bound);
              NetworkRequest lan = new NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                  .addTransportType(NetworkCapabilities.TRANSPORT_ETHERNET).build();
              try {
                connectivity.registerNetworkCallback(lan, network);
                watchingNetwork = true;
              } catch (RuntimeException denied) {
                Log.w(TAG, "Network changes cannot be watched", denied);
                advertise.run();
              }
            }
          });
        } catch (IOException failed) {
          Log.e(TAG, "Phone API could not start", failed);
        }
      }
    }, "skylit-local-start").start();
  }

  void stop() {
    running = false;
    port = 0;
    main.removeCallbacksAndMessages(null);
    albumWorker.shutdownNow();
    if (watchingNetwork) {
      try {
        connectivity.unregisterNetworkCallback(network);
      } catch (RuntimeException notWatching) {
        Log.w(TAG, "Network watch was already removed");
      }
      watchingNetwork = false;
    }
    withdraw.run();
    try {
      multicast.release();
    } catch (RuntimeException notHeld) {
      Log.w(TAG, "Multicast lock was not held");
    }
    stopServer();
  }

  String status() {
    return api.pairingStatus(port, advertised, LocalServer.lanAddress());
  }

  void pageReady() {
    if (!waitingSettings.isEmpty() && evaluate(applySettings(Json.write(waitingSettings)))) waitingSettings.clear();
  }

  @Override public void householdChanged(String snapshot) {
    show("window.SkylitHousehold&&window.SkylitHousehold.receive(" + snapshot + ")");
  }

  @Override public void pairingChanged(final String state, final long remaining) {
    main.post(new Runnable() {
      @Override public void run() {
        evaluate("window.SkylitPairing&&window.SkylitPairing.update(" + state + ")");
        main.removeCallbacks(expirePairing);
        if (remaining >= 0) main.postDelayed(expirePairing, remaining + 250);
      }
    });
  }

  @Override public void settingsRequested(final String settings) {
    main.post(new Runnable() {
      @Override public void run() {
        if (evaluate(applySettings(settings))) return;
        try {
          waitingSettings.putAll(Json.map(Json.parse(settings)));
        } catch (Json.Malformed impossible) {
          Log.w(TAG, "A phone setting could not be queued");
        }
      }
    });
  }

  private static String applySettings(String settings) {
    return "window.SkylitRemote&&window.SkylitRemote.apply(" + settings + ")";
  }

  private void show(final String script) {
    main.post(new Runnable() {
      @Override public void run() {
        evaluate(script);
      }
    });
  }

  private boolean evaluate(String script) {
    return running && dashboard.evaluate(script);
  }

  private void stopServer() {
    new Thread(new Runnable() {
      @Override public void run() {
        server.stop();
      }
    }, "skylit-local-stop").start();
  }
}
