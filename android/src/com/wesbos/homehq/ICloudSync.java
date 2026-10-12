package com.wesbos.homehq;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class ICloudSync {
  interface Library {
    List<ICloudAlbum.Stored> pictures();

    Set<String> excluded();

    boolean add(byte[] image, long at);

    void remove(String id);

    void removeAll();

    int capacity();
  }

  interface Runner {
    void start(Runnable work);
  }

  interface Listener {
    void changed();
  }

  static final long INTERVAL = 30 * 60000L;
  static final long LONGEST_WAIT = 6 * 3600000L;
  private static final String KEY = "icloud";
  private static final String OFFLINE = "Could not reach iCloud. The frame will try again when it is online.";

  private final KeyValue storage;
  private final FrameTime.Clock clock;
  private final ICloudAlbum.Transport transport;
  private final Library library;
  private final Runner runner;
  private final Listener listener;
  private final Object pictures = new Object();
  private String token;
  private String host;
  private String name = "";
  private String error;
  private Long lastSync;
  private long lastAttempt;
  private int failures;
  private int generation;
  private boolean syncing;
  private boolean again;
  private Map<String, String> known = new HashMap<>();
  private Set<String> rejected = new HashSet<>();

  ICloudSync(KeyValue storage, FrameTime.Clock clock, ICloudAlbum.Transport transport, Library library, Runner runner,
      Listener listener) {
    this.storage = storage;
    this.clock = clock;
    this.transport = transport;
    this.library = library;
    this.runner = runner;
    this.listener = listener;
    try {
      Map<String, Object> saved = Json.map(Json.parse(storage.get(KEY)));
      String savedToken = (String) saved.get("token");
      if (!savedToken.matches("[A-Za-z0-9]{8,64}")) throw new IllegalArgumentException();
      Map<String, String> savedKnown = new HashMap<>();
      for (Map.Entry<String, Object> entry : Json.map(saved.get("known")).entrySet()) savedKnown.put(entry.getKey(), (String) entry.getValue());
      Set<String> savedRejected = new HashSet<>();
      for (Object guid : Json.list(saved.get("rejected"))) savedRejected.add((String) guid);
      token = savedToken;
      host = (String) saved.get("host");
      name = (String) saved.get("name");
      error = (String) saved.get("error");
      lastSync = (Long) saved.get("lastSync");
      failures = ((Number) saved.get("failures")).intValue();
      known = savedKnown;
      rejected = savedRejected;
    } catch (Json.Malformed | RuntimeException absentOrUnreadable) {
      token = null;
    }
  }

  synchronized Map<String, Object> status() {
    if (token == null) return null;
    int count = 0;
    for (ICloudAlbum.Stored picture : library.pictures()) if (picture.album) count++;
    return Json.object("name", name, "count", count, "lastSync", lastSync == null ? null : FrameTime.iso(lastSync),
        "syncing", syncing, "error", error);
  }

  void connect(Object link) throws ApiException {
    String next = ICloudAlbum.token(link);
    boolean replaced;
    synchronized (this) {
      replaced = token != null && !next.equals(token);
      if (!next.equals(token)) {
        generation++;
        token = next;
        host = null;
        name = "";
        error = null;
        lastSync = null;
        failures = 0;
        known = new HashMap<>();
        rejected = new HashSet<>();
        save();
      }
    }
    if (replaced) {
      synchronized (pictures) {
        library.removeAll();
      }
    }
    listener.changed();
    request(true);
  }

  boolean disconnect() {
    synchronized (this) {
      if (token == null) return false;
      generation++;
      token = null;
      storage.put(KEY, "");
    }
    synchronized (pictures) {
      library.removeAll();
    }
    listener.changed();
    return true;
  }

  synchronized boolean due() {
    long wait = failures == 0 ? INTERVAL : Math.min(LONGEST_WAIT, INTERVAL << Math.min(failures, 4));
    return token != null && !syncing && (lastAttempt == 0 || clock.now() - lastAttempt >= wait);
  }

  synchronized boolean troubled() {
    return token != null && error != null;
  }

  boolean request(final boolean force) {
    synchronized (this) {
      if (token == null) return false;
      if (!force && !due()) return true;
    }
    runner.start(new Runnable() {
      @Override public void run() {
        sync();
      }
    });
    return true;
  }

  void sync() {
    synchronized (this) {
      if (token == null) return;
      if (syncing) {
        again = true;
        return;
      }
      syncing = true;
    }
    boolean repeat = true;
    while (repeat) {
      listener.changed();
      attempt();
      synchronized (this) {
        repeat = again && token != null;
        again = false;
        if (!repeat) syncing = false;
      }
    }
    listener.changed();
  }

  private void attempt() {
    String album;
    String server;
    int started;
    Map<String, String> mapping;
    Set<String> refused;
    synchronized (this) {
      album = token;
      server = host;
      started = generation;
      mapping = new HashMap<>(known);
      refused = new HashSet<>(rejected);
      lastAttempt = clock.now();
    }
    String failure = null;
    String label = null;
    try {
      ICloudAlbum.Listing listing = ICloudAlbum.list(transport, album, server);
      server = listing.host;
      label = listing.name;
      Set<String> listed = new HashSet<>();
      for (ICloudAlbum.Photo photo : listing.photos) listed.add(photo.guid);
      mapping.keySet().retainAll(listed);
      refused.retainAll(listed);
      Set<String> excluded = library.excluded();
      ICloudAlbum.Plan plan = ICloudAlbum.plan(listing.photos, mapping, refused, library.pictures(), excluded, library.capacity());
      for (String id : plan.remove) {
        synchronized (pictures) {
          if (stale(started)) return;
          library.remove(id);
        }
      }
      int missed = 0;
      for (int from = 0; from < plan.download.size(); from += ICloudAlbum.BATCH) {
        List<ICloudAlbum.Photo> batch = plan.download.subList(from, Math.min(plan.download.size(), from + ICloudAlbum.BATCH));
        Map<String, String> urls = ICloudAlbum.urls(transport, server, album, new ArrayList<>(batch));
        for (ICloudAlbum.Photo photo : batch) {
          if (stale(started)) return;
          String url = urls.get(photo.checksum);
          byte[] image = null;
          try {
            if (url != null) image = transport.get(url, ICloudAlbum.MAX_IMAGE);
          } catch (IOException unavailable) {
            image = null;
          }
          if (image == null) {
            missed++;
            continue;
          }
          String id = Digests.sha256(image);
          boolean kept;
          synchronized (pictures) {
            if (stale(started)) return;
            kept = library.add(image, plan.times.get(photo.guid));
          }
          mapping.put(photo.guid, id);
          if (!kept && !excluded.contains(id) && !library.excluded().contains(id)) refused.add(photo.guid);
        }
      }
      if (missed > 0) failure = missed + (missed == 1 ? " picture" : " pictures") + " could not be downloaded yet. The frame will try again.";
    } catch (ICloudAlbum.Problem problem) {
      failure = problem.getMessage();
    } catch (IOException offline) {
      failure = OFFLINE;
    } catch (RuntimeException unexpected) {
      failure = "The album could not be synced.";
    }
    synchronized (this) {
      if (generation != started) return;
      host = server;
      if (label != null) name = label;
      known = mapping;
      rejected = refused;
      error = failure;
      failures = failure == null ? 0 : Math.min(failures + 1, 10);
      if (failure == null) lastSync = clock.now();
      save();
    }
  }

  private synchronized boolean stale(int started) {
    return generation != started;
  }

  private void save() {
    Map<String, Object> mapping = new HashMap<>();
    mapping.putAll(known);
    storage.put(KEY, Json.write(Json.object("token", token, "host", host, "name", name, "error", error,
        "lastSync", lastSync, "failures", failures, "known", mapping, "rejected", new ArrayList<Object>(rejected))));
  }
}
