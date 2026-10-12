package com.wesbos.homehq;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

final class ICloudAlbum {
  interface Transport {
    Reply post(String url, String body) throws IOException;

    byte[] get(String url, int limit) throws IOException;
  }

  static final class Reply {
    final int status;
    final String body;

    Reply(int status, String body) {
      this.status = status;
      this.body = body;
    }
  }

  static final class Problem extends Exception {
    Problem(String message) {
      super(message);
    }
  }

  static final class Photo {
    final String guid;
    final String checksum;
    final long created;

    Photo(String guid, String checksum, long created) {
      this.guid = guid;
      this.checksum = checksum;
      this.created = created;
    }
  }

  static final class Listing {
    final String name;
    final String host;
    final List<Photo> photos;

    Listing(String name, String host, List<Photo> photos) {
      this.name = name;
      this.host = host;
      this.photos = photos;
    }
  }

  static final class Stored {
    final String id;
    final long at;
    final boolean album;

    Stored(String id, long at, boolean album) {
      this.id = id;
      this.at = at;
      this.album = album;
    }
  }

  static final class Plan {
    final List<Photo> download = new ArrayList<>();
    final List<String> remove = new ArrayList<>();
    final Map<String, Long> times = new HashMap<>();
  }

  static final int MAX_EDGE = 2560;
  static final int MAX_IMAGE = 12 * 1024 * 1024;
  static final int MAX_PHOTOS = 5000;
  static final int BATCH = 25;
  private static final String DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
  private static final String GONE = "This shared album was not found. Check that Public Website is switched on for it.";
  private static final String UNEXPECTED = "iCloud sent an answer the frame did not understand.";

  private ICloudAlbum() {}

  static String token(Object link) throws ApiException {
    String text = link instanceof String ? ((String) link).trim() : "";
    if (text.matches("https://share\\.icloud\\.com/photos/.*")) {
      throw ApiException.badRequest("iCloud Links from share.icloud.com are not supported. Use the album's Public Website link.");
    }
    if (!text.matches("https://www\\.icloud\\.com/sharedalbum/([a-z]{2}-[a-z]{2}/)?#[A-Za-z0-9]{8,64}")) {
      throw ApiException.badRequest("Use the album's Public Website link, which looks like https://www.icloud.com/sharedalbum/#…");
    }
    return text.substring(text.indexOf('#') + 1);
  }

  static String host(String token) {
    String digits = token.charAt(0) == 'A' ? token.substring(1, 2) : token.substring(1, 3);
    int partition = 0;
    for (int i = 0; i < digits.length(); i++) partition = partition * 62 + DIGITS.indexOf(digits.charAt(i));
    return String.format(Locale.ROOT, "p%02d-sharedstreams.icloud.com", partition);
  }

  static boolean streamHost(Object host) {
    return host instanceof String && ((String) host).matches("p[0-9]{1,4}-sharedstreams\\.icloud\\.com");
  }

  static String assetUrl(Object location, Object path) throws Problem {
    boolean trusted = location instanceof String && path instanceof String
        && ((String) location).matches("[a-z0-9]([a-z0-9.\\-]{0,200})\\.(icloud-content\\.com|icloud\\.com)")
        && !((String) location).contains("..")
        && ((String) path).matches("/[\\x21-\\x7e]{1,4000}") && !((String) path).contains("#");
    if (!trusted) throw new Problem(UNEXPECTED);
    return "https://" + location + path;
  }

  private static Map<String, Object> ask(Transport transport, String host, String token, String call, String body)
      throws Problem, IOException {
    String current = host;
    for (int attempt = 0; attempt < 2; attempt++) {
      Reply reply = transport.post("https://" + current + "/" + token + "/sharedstreams/" + call, body);
      Map<String, Object> answer;
      try {
        answer = Json.map(Json.parse(reply.body));
      } catch (Json.Malformed notJson) {
        answer = null;
      }
      if (reply.status == 330) {
        Object moved = answer == null ? null : answer.get("X-Apple-MMe-Host");
        if (!streamHost(moved) || attempt > 0) throw new Problem(UNEXPECTED);
        current = (String) moved;
        continue;
      }
      if (reply.status == 404) throw new Problem(GONE);
      if (reply.status != 200 || answer == null) throw new Problem(UNEXPECTED);
      answer.put("X-Apple-MMe-Host", current);
      return answer;
    }
    throw new Problem(UNEXPECTED);
  }

  static Listing list(Transport transport, String token, String rememberedHost) throws Problem, IOException {
    String host = streamHost(rememberedHost) ? rememberedHost : host(token);
    Map<String, Object> stream = ask(transport, host, token, "webstream", "{\"streamCtag\":null}");
    List<Object> rows = Json.list(stream.get("photos"));
    if (rows == null) throw new Problem(UNEXPECTED);
    List<Photo> photos = new ArrayList<>();
    Set<String> seen = new HashSet<>();
    for (int i = 0; i < rows.size() && i < MAX_PHOTOS; i++) {
      Map<String, Object> row = Json.map(rows.get(i));
      if (row == null || !(row.get("photoGuid") instanceof String) || "video".equals(row.get("mediaAssetType"))) continue;
      String guid = (String) row.get("photoGuid");
      String checksum = choose(Json.map(row.get("derivatives")));
      if (!guid.matches("[A-Za-z0-9\\-]{8,64}") || checksum == null || !seen.add(guid)) continue;
      long created = FrameTime.instant(row.get("dateCreated"));
      photos.add(new Photo(guid, checksum, created > 0 ? created : FrameTime.instant(row.get("batchDateCreated"))));
    }
    Object name = stream.get("streamName");
    String label = name instanceof String ? Fields.tidy((String) name, 80) : "";
    return new Listing(label, (String) stream.get("X-Apple-MMe-Host"), photos);
  }

  private static long number(Object value) {
    if (value instanceof Number) return ((Number) value).longValue();
    return value instanceof String && ((String) value).matches("[0-9]{1,12}") ? Long.parseLong((String) value) : -1;
  }

  static String choose(Map<String, Object> derivatives) {
    if (derivatives == null) return null;
    String fitting = null;
    String oversize = null;
    long fittingEdge = 0;
    long oversizeEdge = 0;
    for (Object value : derivatives.values()) {
      Map<String, Object> derivative = Json.map(value);
      if (derivative == null || !(derivative.get("checksum") instanceof String)) continue;
      String checksum = (String) derivative.get("checksum");
      long edge = Math.max(number(derivative.get("width")), number(derivative.get("height")));
      long shortest = Math.min(number(derivative.get("width")), number(derivative.get("height")));
      if (!checksum.matches("[0-9a-fA-F]{16,128}") || shortest <= 0 || number(derivative.get("fileSize")) > MAX_IMAGE) continue;
      if (edge <= MAX_EDGE && edge > fittingEdge) {
        fitting = checksum;
        fittingEdge = edge;
      } else if (edge > MAX_EDGE && edge > oversizeEdge) {
        oversize = checksum;
        oversizeEdge = edge;
      }
    }
    return fitting != null ? fitting : oversize;
  }

  static Map<String, String> urls(Transport transport, String host, String token, List<Photo> photos)
      throws Problem, IOException {
    List<Object> guids = new ArrayList<>();
    for (Photo photo : photos) guids.add(photo.guid);
    Map<String, Object> answer = ask(transport, host, token, "webasseturls", Json.write(Json.object("photoGuids", guids)));
    Map<String, Object> items = Json.map(answer.get("items"));
    if (items == null) throw new Problem(UNEXPECTED);
    Map<String, String> urls = new HashMap<>();
    for (Photo photo : photos) {
      Map<String, Object> item = Json.map(items.get(photo.checksum));
      if (item != null) urls.put(photo.checksum, assetUrl(item.get("url_location"), item.get("url_path")));
    }
    return urls;
  }

  static Plan plan(List<Photo> album, Map<String, String> known, Set<String> rejected, List<Stored> library,
      Set<String> excluded, int capacity) {
    Map<String, Stored> stored = new LinkedHashMap<>();
    final List<Object[]> ranked = new ArrayList<>();
    for (Stored picture : library) {
      stored.put(picture.id, picture);
      if (!picture.album) ranked.add(new Object[] {picture.at, 0, null});
    }
    Plan plan = new Plan();
    Set<String> claimed = new HashSet<>();
    for (int i = 0; i < album.size(); i++) {
      Photo photo = album.get(i);
      String id = known.get(photo.guid);
      if (id != null && (excluded.contains(id) || rejected.contains(photo.guid) || !claimed.add(id))) continue;
      Stored present = id == null ? null : stored.get(id);
      if (present != null && !present.album) continue;
      long at = present != null ? present.at : Math.max(1, photo.created) + i % 1000;
      plan.times.put(photo.guid, at);
      ranked.add(new Object[] {at, 1, photo});
    }
    Collections.sort(ranked, new Comparator<Object[]>() {
      @Override public int compare(Object[] left, Object[] right) {
        int newest = Long.compare((Long) right[0], (Long) left[0]);
        return newest != 0 ? newest : Integer.compare((Integer) left[1], (Integer) right[1]);
      }
    });
    Set<String> wanted = new HashSet<>();
    for (int rank = 0; rank < ranked.size() && rank < capacity; rank++) {
      Photo photo = (Photo) ranked.get(rank)[2];
      if (photo == null) continue;
      String id = known.get(photo.guid);
      if (id != null && stored.containsKey(id)) wanted.add(id);
      else plan.download.add(photo);
    }
    for (Stored picture : library) if (picture.album && !wanted.contains(picture.id)) plan.remove.add(picture.id);
    return plan;
  }
}
