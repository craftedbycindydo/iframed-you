package com.wesbos.homehq;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

public final class ICloudTest {
  static final long START = 1791676800000L;
  static final String TOKEN = "B0zEXAMPLEtoken";
  static final String LINK = "https://www.icloud.com/sharedalbum/#" + TOKEN;
  static int checks;

  static Fakes.Storage storage;
  static Fakes.Clock clock;
  static Fakes.PhotoShelf photos;
  static Fakes.Recorder events;
  static Fakes.Album album;
  static ICloudSync sync;
  static LocalApi api;
  static String bearer;

  static void check(boolean value, String message) {
    if (!value) throw new AssertionError(message);
    checks++;
  }

  static void same(Object expected, Object actual, String message) {
    check(expected == null ? actual == null : expected.equals(actual), message + ": expected " + expected + " but was " + actual);
  }

  static String guid(int number) {
    return String.format("%08d-AAAA-BBBB-CCCC-%012d", number, number);
  }

  static String day(int number) {
    return String.format("2026-09-%02dT12:00:00Z", number);
  }

  static byte[] image(int seed) {
    return Fakes.jpeg(seed, 6000);
  }

  static void fresh() {
    storage = new Fakes.Storage();
    clock = new Fakes.Clock(START);
    photos = new Fakes.PhotoShelf();
    events = new Fakes.Recorder();
    album = new Fakes.Album();
    for (int i = 1; i <= 4; i++) album.add(guid(i), day(i), image(i), 342, 2048);
    album.addVideo(guid(90), day(20));
    sync = new ICloudSync(storage, clock, album, photos.library, Fakes.inline(), events.album);
  }

  static void rejectedLink(Object link, String reason) {
    try {
      ICloudAlbum.token(link);
      throw new AssertionError("accepted " + reason);
    } catch (ApiException expected) {
      same(400, expected.status, reason);
    }
  }

  static void links() throws Exception {
    same(TOKEN, ICloudAlbum.token(LINK), "public website link");
    same(TOKEN, ICloudAlbum.token("  " + LINK + "\n"), "surrounding space is trimmed");
    same(TOKEN, ICloudAlbum.token("https://www.icloud.com/sharedalbum/en-gb/#" + TOKEN), "localised link");
    Object[] bad = {null, 5, "", TOKEN, "http://www.icloud.com/sharedalbum/#" + TOKEN, "https://icloud.com/sharedalbum/#" + TOKEN,
        "https://www.icloud.com.evil.test/sharedalbum/#" + TOKEN, "https://evil.test/https://www.icloud.com/sharedalbum/#" + TOKEN,
        "https://www.icloud.com/sharedalbum/#", "https://www.icloud.com/sharedalbum/#short", "https://www.icloud.com/sharedalbum/#" + TOKEN + "/../x",
        "https://www.icloud.com/sharedalbum/#" + TOKEN + "?x=1", "https://www.icloud.com/sharedalbum/?x=1#" + TOKEN,
        "https://www.icloud.com/photos/#" + TOKEN, "https://user@www.icloud.com/sharedalbum/#" + TOKEN,
        "https://www.icloud.com/sharedalbum/#" + TOKEN + " " + TOKEN, "https://www.icloud.com/sharedalbum/#B0z5q%41GN1JIFd3y",
        "https://share.icloud.com/photos/0a1B2c3D4e5F6g7H8i9J0kLmN"};
    for (Object link : bad) rejectedLink(link, "link " + link);
    try {
      ICloudAlbum.token("https://share.icloud.com/photos/0a1B2c3D4e5F6g7H8i9J0kLmN");
    } catch (ApiException explained) {
      check(explained.getMessage().contains("share.icloud.com") && explained.getMessage().contains("Public Website"), "iCloud Links get a clear explanation");
    }

    same("p61-sharedstreams.icloud.com", ICloudAlbum.host(TOKEN), "two base-62 digits for B tokens");
    same("p00-sharedstreams.icloud.com", ICloudAlbum.host("B00abcdefgh"), "zero padded partition");
    same("p10-sharedstreams.icloud.com", ICloudAlbum.host("B0Aabcdefgh"), "letters are digits above nine");
    same("p3843-sharedstreams.icloud.com", ICloudAlbum.host("Bzzabcdefgh"), "largest two digit partition");
    same("p05-sharedstreams.icloud.com", ICloudAlbum.host("A5zabcdefgh"), "one base-62 digit for A tokens");
    same("p61-sharedstreams.icloud.com", ICloudAlbum.host("Az0abcdefgh"), "A token with a letter digit");
    check(ICloudAlbum.streamHost("p150-sharedstreams.icloud.com") && ICloudAlbum.streamHost("p07-sharedstreams.icloud.com"), "Apple stream hosts");
    for (Object host : new Object[] {null, 7, "", "evil.test", "p10-sharedstreams.icloud.com.evil.test", "p10-sharedstreams.icloud.com:8443",
        "x@p10-sharedstreams.icloud.com", "p10-sharedstreams.icloud.com/evil", "pxx-sharedstreams.icloud.com", "www.icloud.com"}) {
      check(!ICloudAlbum.streamHost(host), "refused stream host " + host);
    }

    same("https://cvws.icloud-content.com/S/abc/IMG.JPG?o=1&e=2", ICloudAlbum.assetUrl("cvws.icloud-content.com", "/S/abc/IMG.JPG?o=1&e=2"), "asset url");
    same("https://p10-content.icloud.com/x", ICloudAlbum.assetUrl("p10-content.icloud.com", "/x"), "icloud.com asset host");
    Object[][] badAssets = {{"evil.test", "/x"}, {"icloud-content.com.evil.test", "/x"}, {"evilicloud-content.com", "/x"}, {"evilicloud.com", "/x"},
        {"cvws.icloud-content.com:8443", "/x"}, {"user@cvws.icloud-content.com", "/x"}, {"cvws.icloud-content.com/evil", "/x"},
        {"cvws.icloud-content.com", "x"}, {"cvws.icloud-content.com", "/a b"}, {"cvws.icloud-content.com", "/a#b"}, {"cvws.icloud-content.com", ""},
        {"CVWS.ICLOUD-CONTENT.COM", "/x"}, {"a..icloud.com", "/x"}, {null, "/x"}, {"cvws.icloud-content.com", null}, {5, 6}, {"http://cvws.icloud-content.com", "/x"}};
    for (Object[] asset : badAssets) {
      try {
        ICloudAlbum.assetUrl(asset[0], asset[1]);
        throw new AssertionError("accepted asset " + Arrays.toString(asset));
      } catch (ICloudAlbum.Problem expected) {
        checks++;
      }
    }
    String[] refused = {"http://p10-sharedstreams.icloud.com/x", "https://p10-sharedstreams.icloud.com@evil.test/x", "https://p10-sharedstreams.icloud.com:8443/x",
        "https://www.icloud.com/x", "https://evil.test/x", "file:///etc/passwd", "ftp://p10-sharedstreams.icloud.com/x"};
    for (String address : refused) {
      try {
        ICloudHttp.allowed(address, true);
        throw new AssertionError("api transport accepted " + address);
      } catch (IOException expected) {
        checks++;
      }
    }
    for (String address : new String[] {"http://cvws.icloud-content.com/x", "https://evil.test/x", "https://icloud-content.com.evil.test/x",
        "https://cvws.icloud-content.com@evil.test/x", "https://cvws.icloud-content.com:444/x", "https://evilicloud.com/x"}) {
      try {
        ICloudHttp.allowed(address, false);
        throw new AssertionError("download transport accepted " + address);
      } catch (IOException expected) {
        checks++;
      }
    }
    same("cvws.icloud-content.com", ICloudHttp.allowed("https://cvws.icloud-content.com/S/a?b=1", false).getHost(), "download transport accepts Apple content hosts");
    same("p150-sharedstreams.icloud.com", ICloudHttp.allowed("https://p150-sharedstreams.icloud.com/t/sharedstreams/webstream", true).getHost(), "api transport accepts stream hosts");
  }

  static Map<String, Object> derivative(String checksum, Object width, Object height, Object size) {
    return Json.object("checksum", checksum, "width", width, "height", height, "fileSize", size);
  }

  static String sum(int number) {
    return String.format("%040x", number);
  }

  static void derivatives() {
    same(sum(2), ICloudAlbum.choose(Json.object("342", derivative(sum(1), "342", "256", "9000"), "2049", derivative(sum(2), "2049", "1536", "900000"),
        "4032", derivative(sum(3), "4032", "3024", "4000000"))), "largest derivative within 2560");
    same(sum(2), ICloudAlbum.choose(Json.object("a", derivative(sum(1), 1536L, 2049L, 100L), "b", derivative(sum(2), 1920L, 2560L, 100L))), "portrait uses its longest edge, numbers allowed");
    same(sum(3), ICloudAlbum.choose(Json.object("a", derivative(sum(1), "3000", "2000", "1"), "b", derivative(sum(3), "4032", "3024", "1"))), "largest available when nothing fits");
    same(sum(1), ICloudAlbum.choose(Json.object("a", derivative(sum(1), "342", "256", "1"), "b", derivative(sum(2), "2048", "1536", String.valueOf(ICloudAlbum.MAX_IMAGE + 1)))), "oversize files are skipped");
    same(sum(1), ICloudAlbum.choose(Json.object("a", derivative(sum(1), "342", "256", null), "b", derivative("not-hex", "2048", "1536", "1"),
        "c", derivative(sum(3), "x", "y", "1"), "d", "text", "e", Json.object("width", "2000", "height", "1500"))), "malformed derivatives are ignored");
    same(null, ICloudAlbum.choose(Json.object()), "no derivatives");
    same(null, ICloudAlbum.choose(null), "missing derivatives");
    same(null, ICloudAlbum.choose(Json.object("a", derivative(sum(1), "0", "0", "1"), "b", derivative(sum(2), "-5", "10", "1"))), "zero and negative sizes");
  }

  static ICloudAlbum.Problem problem(String remembered) throws IOException {
    try {
      ICloudAlbum.list(album, TOKEN, remembered);
      throw new AssertionError("listing succeeded");
    } catch (ICloudAlbum.Problem expected) {
      checks++;
      return expected;
    }
  }

  static void listing() throws Exception {
    fresh();
    ICloudAlbum.Listing listing = ICloudAlbum.list(album, TOKEN, null);
    same(4, listing.photos.size(), "videos are skipped");
    same("Family", listing.name, "album name");
    same("p61-sharedstreams.icloud.com", listing.host, "computed host");
    same("https://p61-sharedstreams.icloud.com/" + TOKEN + "/sharedstreams/webstream {\"streamCtag\":null}", album.posts.get(0), "webstream request");
    same(guid(1), listing.photos.get(0).guid, "photo guid");
    same(FrameTime.instant(day(1)), listing.photos.get(0).created, "photo date");
    check(listing.photos.get(0).checksum.matches("[0-9a-f]{40}"), "chosen checksum");

    album.posts.clear();
    album.home = "p150-sharedstreams.icloud.com";
    listing = ICloudAlbum.list(album, TOKEN, null);
    same(2, album.posts.size(), "a 330 is retried once");
    check(album.posts.get(1).startsWith("https://p150-sharedstreams.icloud.com/" + TOKEN + "/sharedstreams/webstream "), "the retry goes to the host Apple named");
    same("p150-sharedstreams.icloud.com", listing.host, "the new host is reported for remembering");
    album.posts.clear();
    ICloudAlbum.list(album, TOKEN, listing.host);
    same(1, album.posts.size(), "a remembered host is used directly");
    album.posts.clear();
    ICloudAlbum.list(album, TOKEN, "evil.test");
    check(album.posts.get(0).startsWith("https://p61-"), "an untrusted remembered host is ignored");

    album.posts.clear();
    album.alwaysMoved = true;
    problem(null);
    same(2, album.posts.size(), "a 330 loop stops after one retry");
    album.alwaysMoved = false;
    album.posts.clear();
    album.home = "evil.test";
    problem(null);
    same(1, album.posts.size(), "an off-domain 330 host is never contacted");
    album.home = null;

    album.status = 404;
    check(problem(null).getMessage().contains("Public Website"), "a missing album explains itself");
    album.status = 500;
    problem(null);
    album.status = 302;
    problem(null);
    album.status = 200;
    String[] hostile = {"<html><body>Sign in</body></html>", "", "[]", "null", "{}", "{\"photos\":\"many\"}", "{\"photos\":{\"0\":{}}}", "{\"photos\":[" };
    for (String body : hostile) {
      album.rawStream = body;
      problem(null);
    }
    album.rawStream = "{\"streamName\":5,\"photos\":[null,7,\"x\",{},{\"photoGuid\":5},{\"photoGuid\":\"../../etc/passwd\",\"derivatives\":{}},"
        + "{\"photoGuid\":\"" + guid(1) + "\"},{\"photoGuid\":\"" + guid(2) + "\",\"derivatives\":[]},"
        + "{\"photoGuid\":\"" + guid(3) + "\",\"derivatives\":{\"1\":{\"checksum\":\"" + sum(3) + "\",\"width\":\"100\",\"height\":\"80\"}}},"
        + "{\"photoGuid\":\"" + guid(3) + "\",\"derivatives\":{\"1\":{\"checksum\":\"" + sum(4) + "\",\"width\":\"100\",\"height\":\"80\"}}}]}";
    listing = ICloudAlbum.list(album, TOKEN, null);
    same(1, listing.photos.size(), "rows with missing fields and repeated guids are skipped");
    same("", listing.name, "a non-text name becomes empty");
    same(0L, listing.photos.get(0).created, "a missing date is tolerated");
    StringBuilder many = new StringBuilder("{\"streamName\":\"" + new String(new char[300]).replace('\0', 'n') + "\",\"photos\":[");
    for (int i = 0; i < 6000; i++) {
      many.append(i == 0 ? "" : ",").append("{\"photoGuid\":\"").append(guid(i + 100)).append("\",\"dateCreated\":\"garbage\",\"derivatives\":{\"1\":{\"checksum\":\"")
          .append(sum(i)).append("\",\"width\":100,\"height\":80,\"fileSize\":1}}}");
    }
    album.rawStream = many.append("]}").toString();
    listing = ICloudAlbum.list(album, TOKEN, null);
    same(ICloudAlbum.MAX_PHOTOS, listing.photos.size(), "huge albums are bounded");
    same(80, listing.name.length(), "long names are bounded");
    album.rawStream = "{\"streamName\":\"Empty\",\"photos\":[]}";
    same(0, ICloudAlbum.list(album, TOKEN, null).photos.size(), "an empty album is fine");
    album.rawStream = null;
    album.photos.clear();
    album.addVideo(guid(1), day(1));
    album.addVideo(guid(2), day(2));
    same(0, ICloudAlbum.list(album, TOKEN, null).photos.size(), "an album of only videos is fine");
    album.offline = true;
    try {
      ICloudAlbum.list(album, TOKEN, null);
      throw new AssertionError("offline listing succeeded");
    } catch (IOException expected) {
      checks++;
    }

    fresh();
    listing = ICloudAlbum.list(album, TOKEN, null);
    album.posts.clear();
    Map<String, String> urls = ICloudAlbum.urls(album, listing.host, TOKEN, listing.photos);
    same(4, urls.size(), "one url per requested picture");
    check(album.posts.get(0).startsWith("https://p61-sharedstreams.icloud.com/" + TOKEN + "/sharedstreams/webasseturls {\"photoGuids\":[\"" + guid(1) + "\","), "webasseturls request");
    String url = urls.get(listing.photos.get(0).checksum);
    check(url.startsWith("https://cvws.icloud-content.com/S/" + listing.photos.get(0).checksum + "/"), "url joins location and path");
    for (String location : new String[] {"evil.test", "cvws.icloud-content.com.evil.test", "cvws.icloud-content.com:81", ""}) {
      album.location = location;
      try {
        ICloudAlbum.urls(album, listing.host, TOKEN, listing.photos);
        throw new AssertionError("accepted location " + location);
      } catch (ICloudAlbum.Problem expected) {
        checks++;
      }
    }
    album.location = "cvws.icloud-content.com";
    for (String body : new String[] {"<html>", "{}", "{\"items\":[]}", "{\"items\":{\"" + listing.photos.get(0).checksum + "\":{\"url_location\":\"cvws.icloud-content.com\",\"url_path\":5}}}",
        "{\"items\":{\"" + listing.photos.get(0).checksum + "\":{\"url_location\":\"http://cvws.icloud-content.com\",\"url_path\":\"/x\"}}}"}) {
      album.rawUrls = body;
      try {
        ICloudAlbum.urls(album, listing.host, TOKEN, listing.photos);
        throw new AssertionError("accepted urls " + body);
      } catch (ICloudAlbum.Problem expected) {
        checks++;
      }
    }
    album.rawUrls = "{\"items\":{\"" + sum(77) + "\":{\"url_location\":\"cvws.icloud-content.com\",\"url_path\":\"/x\"},\"" + listing.photos.get(1).checksum + "\":\"text\"}}";
    same(0, ICloudAlbum.urls(album, listing.host, TOKEN, listing.photos).size(), "items for other checksums are ignored");
  }

  static List<ICloudAlbum.Photo> shots(int count) {
    List<ICloudAlbum.Photo> shots = new ArrayList<>();
    for (int i = 1; i <= count; i++) shots.add(new ICloudAlbum.Photo(guid(i), sum(i), FrameTime.instant(day(i))));
    return shots;
  }

  static List<String> guids(List<ICloudAlbum.Photo> photos) {
    List<String> guids = new ArrayList<>();
    for (ICloudAlbum.Photo photo : photos) guids.add(photo.guid);
    return guids;
  }

  static void planning() {
    Map<String, String> known = new HashMap<>();
    Set<String> none = new HashSet<>();
    List<ICloudAlbum.Stored> library = new ArrayList<>();
    ICloudAlbum.Plan plan = ICloudAlbum.plan(shots(10), known, none, library, none, 5);
    same(Arrays.asList(guid(10), guid(9), guid(8), guid(7), guid(6)), guids(plan.download), "newest first up to the limit");
    same(0, plan.remove.size(), "nothing to remove from an empty library");
    same(10, ICloudAlbum.plan(shots(10), known, none, library, none, 50).download.size(), "a roomy library takes everything");
    same(0, ICloudAlbum.plan(shots(10), known, none, library, none, 0).download.size(), "no room, no downloads");
    same(0, ICloudAlbum.plan(shots(0), known, none, library, none, 5).download.size(), "empty album");

    long recent = FrameTime.instant(day(30));
    library.add(new ICloudAlbum.Stored("phone-1", recent, false));
    library.add(new ICloudAlbum.Stored("mail-1", recent - 1000, false));
    library.add(new ICloudAlbum.Stored("mail-old", FrameTime.instant(day(1)) - 86400000L, false));
    plan = ICloudAlbum.plan(shots(10), known, none, library, none, 5);
    same(Arrays.asList(guid(10), guid(9), guid(8)), guids(plan.download), "newer phone and email pictures keep their places");
    same(0, plan.remove.size(), "other pictures are never removed by the album");

    for (int i = 6; i <= 10; i++) {
      known.put(guid(i), "album-" + i);
      library.add(new ICloudAlbum.Stored("album-" + i, FrameTime.instant(day(i)) + 7, true));
    }
    plan = ICloudAlbum.plan(shots(10), known, none, library, none, 50);
    same(Arrays.asList(guid(5), guid(4), guid(3), guid(2), guid(1)), guids(plan.download), "stored pictures are not downloaded again");
    same(0, plan.remove.size(), "stored pictures stay");
    plan = ICloudAlbum.plan(shots(10), known, none, library, none, 5);
    same(0, plan.download.size(), "a full library downloads nothing");
    same(Arrays.asList("album-6", "album-7"), plan.remove, "album pictures beyond the limit leave");
    plan = ICloudAlbum.plan(shots(10).subList(0, 8), known, none, library, none, 50);
    same(Arrays.asList("album-9", "album-10"), plan.remove, "pictures deleted from the album leave the frame");
    same(5, plan.download.size(), "the rest of the album still arrives");
    same(5, ICloudAlbum.plan(new ArrayList<ICloudAlbum.Photo>(), known, none, library, none, 50).remove.size(), "an emptied album empties its pictures");

    Set<String> excluded = new HashSet<>(Arrays.asList("album-10", "trashed-5"));
    known.put(guid(5), "trashed-5");
    List<ICloudAlbum.Stored> visible = new ArrayList<>(library);
    visible.remove(visible.size() - 1);
    plan = ICloudAlbum.plan(shots(10), known, none, visible, excluded, 50);
    check(!guids(plan.download).contains(guid(10)) && !guids(plan.download).contains(guid(5)), "pictures trashed on the frame are not downloaded again");
    same(Arrays.asList(guid(4), guid(3), guid(2), guid(1)), guids(plan.download), "other pictures still arrive");
    same(0, plan.remove.size(), "an excluded picture frees no other");
    plan = ICloudAlbum.plan(shots(10), known, none, visible, excluded, 6);
    same(0, plan.download.size(), "excluded pictures do not use places");
    same(0, plan.remove.size(), "and do not push others out");

    Set<String> rejected = new HashSet<>(Arrays.asList(guid(4)));
    known.put(guid(4), "unusable-4");
    check(!guids(ICloudAlbum.plan(shots(10), known, rejected, visible, excluded, 50).download).contains(guid(4)), "a picture the frame could not use is not fetched again");
    known.put(guid(3), "phone-1");
    plan = ICloudAlbum.plan(shots(10), known, rejected, visible, excluded, 50);
    check(!guids(plan.download).contains(guid(3)) && !plan.remove.contains("phone-1"), "a picture already sent from a phone is neither fetched nor removed");
    known.put(guid(2), "album-9");
    check(!guids(ICloudAlbum.plan(shots(10), known, rejected, visible, excluded, 50).download).contains(guid(2)), "two album entries with one picture are stored once");
    known.clear();
    plan = ICloudAlbum.plan(shots(3), known, none, visible, none, 50);
    same(3, plan.download.size(), "a forgotten mapping downloads again");
    same(4, plan.remove.size(), "and unmapped album pictures leave");
    List<ICloudAlbum.Photo> undated = Arrays.asList(new ICloudAlbum.Photo(guid(1), sum(1), 0), new ICloudAlbum.Photo(guid(2), sum(2), 0));
    same(2, ICloudAlbum.plan(undated, known, none, new ArrayList<ICloudAlbum.Stored>(), none, 5).download.size(), "undated pictures still sync");
  }

  static Map<String, Object> status() {
    return sync.status();
  }

  static void syncing() throws Exception {
    fresh();
    same(null, status(), "no album, no status");
    check(!sync.request(true) && !sync.due() && !sync.disconnect(), "nothing happens without an album");
    try {
      sync.connect("https://share.icloud.com/photos/abc");
      throw new AssertionError("accepted an iCloud Link");
    } catch (ApiException expected) {
      same(null, status(), "a rejected link connects nothing");
    }
    photos.add(Fakes.jpeg(50, 5000), START - 5000);
    sync.connect(LINK);
    same("{\"name\":\"Family\",\"count\":4,\"lastSync\":\"2026-10-11T00:00:00Z\",\"syncing\":false,\"error\":null}", Json.write(status()), "first sync on connect");
    same(5, photos.list().size(), "album pictures join the library");
    same(4, album.downloads, "four pictures downloaded");
    check(events.count("album") >= 3, "the dashboard hears about connecting, syncing and finishing");
    check(storage.values.get("icloud").contains(TOKEN), "the token is kept in private storage");
    check(!Json.write(status()).contains(TOKEN) && !Json.write(status()).contains("icloud.com"), "status never carries the link");
    for (String post : album.posts) check(post.contains("/" + TOKEN + "/sharedstreams/"), "requests address the album");
    check(album.posts.get(1).contains("\"photoGuids\":[") && !album.posts.get(1).contains(guid(90)), "videos are not requested");

    check(!sync.due(), "not due right after a sync");
    clock.now += ICloudSync.INTERVAL - 1;
    check(!sync.due(), "not due before 30 minutes");
    sync.request(false);
    same(2, album.posts.size(), "an early check does nothing");
    clock.now += 1;
    check(sync.due(), "due after 30 minutes");
    sync.request(false);
    same(3, album.posts.size(), "an unchanged album costs one request");
    same(4, album.downloads, "and no downloads");
    same("2026-10-11T00:30:00Z", status().get("lastSync"), "last sync advances");

    String newest = album.add(guid(5), day(5), image(5), 342, 2048);
    album.drop(guid(1));
    sync.request(true);
    same(4L, ((Number) status().get("count")).longValue(), "one added, one removed");
    same(5, album.downloads, "only the new picture is downloaded");
    check(photos.read(Digests.sha256(image(1))) == null, "a picture deleted from the album leaves the frame");
    check(photos.read(Digests.sha256(image(5))) != null, "the new picture arrives");
    check(photos.read(Digests.sha256(Fakes.jpeg(50, 5000))) != null, "the phone picture is untouched");
    check(newest != null, "largest derivative recorded");

    photos.trash(Digests.sha256(image(5)));
    sync.request(true);
    sync.request(true);
    same(5, album.downloads, "a picture trashed on the frame is not downloaded again");
    same(3L, ((Number) status().get("count")).longValue(), "count after trashing");
    photos.hidden.clear();
    sync.request(true);
    same(6, album.downloads, "restoring the exclusion brings it back");

    photos.capacity = 3;
    sync.request(true);
    same(3, photos.list().size(), "a smaller limit is respected across phone and album pictures");
    same(2L, ((Number) status().get("count")).longValue(), "the phone picture keeps its place because it is newest");
    check(photos.read(Digests.sha256(image(5))) != null && photos.read(Digests.sha256(image(4))) != null, "the newest album pictures stay");
    sync.request(true);
    same(6, album.downloads, "a full library does not churn");
    photos.capacity = 30;
    sync.request(true);
    same(4L, ((Number) status().get("count")).longValue(), "a larger limit fills up again");

    ICloudSync reopened = new ICloudSync(storage, clock, album, photos.library, Fakes.inline(), events.album);
    same(Json.write(status()), Json.write(reopened.status()), "status survives a restart");
    check(reopened.due(), "a sync is due at start");
    int before = album.downloads;
    reopened.request(false);
    same(before, album.downloads, "a restart does not download known pictures again");
    sync = reopened;

    byte[] big = image(6);
    String expiring = album.add(guid(6), day(6), big, 2048);
    album.expired.add(expiring);
    sync.request(true);
    check(((String) status().get("error")).startsWith("1 picture could not be downloaded"), "an expired download is reported");
    same(4L, ((Number) status().get("count")).longValue(), "other pictures are kept");
    String kept = (String) status().get("lastSync");
    clock.now += ICloudSync.INTERVAL;
    check(!sync.due(), "a failure waits longer than the usual interval");
    clock.now += ICloudSync.INTERVAL;
    check(sync.due(), "the first retry comes after an hour");
    album.expired.clear();
    sync.request(false);
    same(null, status().get("error"), "a later success clears the error");
    same(5L, ((Number) status().get("count")).longValue(), "the missed picture arrives");
    check(!kept.equals(status().get("lastSync")), "last sync moves only on success");

    album.offline = true;
    for (int failure = 1; failure <= 7; failure++) {
      clock.now += ICloudSync.LONGEST_WAIT;
      sync.request(false);
    }
    check(((String) status().get("error")).contains("Could not reach iCloud"), "offline is explained");
    same(5L, ((Number) status().get("count")).longValue(), "offline keeps every picture");
    check(sync.troubled(), "trouble is visible to the network watcher");
    clock.now += ICloudSync.LONGEST_WAIT - 1;
    check(!sync.due(), "repeated failures back off to six hours");
    clock.now += 1;
    check(sync.due(), "and no further");
    int postsOffline = album.posts.size();
    sync.request(true);
    same(postsOffline + 1, album.posts.size(), "an on-demand sync ignores the backoff");
    album.offline = false;
    album.status = 404;
    sync.request(true);
    check(((String) status().get("error")).contains("Public Website"), "an unpublished album is explained");
    same(5L, ((Number) status().get("count")).longValue(), "an unreachable album removes nothing");
    album.status = 200;
    album.rawStream = "<html>busy</html>";
    sync.request(true);
    check(((String) status().get("error")).contains("did not understand"), "an html answer is reported");
    album.rawStream = null;
    album.location = "evil.test";
    album.add(guid(7), day(7), image(7), 2048);
    int downloads = album.downloads;
    sync.request(true);
    same(downloads, album.downloads, "an off-domain download location is never fetched");
    check(status().get("error") != null, "and is reported");
    album.location = "cvws.icloud-content.com";
    album.home = "p150-sharedstreams.icloud.com";
    sync.request(true);
    same(null, status().get("error"), "recovered through a moved host");
    check(storage.values.get("icloud").contains("p150-sharedstreams.icloud.com"), "the moved host is remembered");
    int posts = album.posts.size();
    sync.request(true);
    check(album.posts.get(posts).startsWith("https://p150-"), "and used first next time");
    for (String entry : events.seen) check(!entry.contains(TOKEN), "events carry no token");

    photos.accepting = false;
    album.add(guid(8), day(8), image(8), 2048);
    sync.request(true);
    downloads = album.downloads;
    sync.request(true);
    same(downloads, album.downloads, "a picture the library refuses is tried once");
    same(null, status().get("error"), "and is not an error");
    photos.accepting = true;

    album.photos.clear();
    sync.request(true);
    same(0L, ((Number) status().get("count")).longValue(), "an emptied album empties its pictures");
    same(1, photos.list().size(), "and leaves the phone picture");
    same(null, status().get("error"), "zero pictures is not an error");

    fresh();
    for (int i = 5; i <= 60; i++) album.add(guid(i), day(i % 28 + 1), image(i), 2048);
    sync.connect(LINK);
    same(30, photos.list().size(), "a large album fills the library to its limit");
    same(30, album.downloads, "and downloads no more than that");
    same(3, album.posts.size(), "thirty downloads use two url batches");
    photos.add(Fakes.jpeg(70, 5000), clock.now);
    same(31, photos.list().size(), "a phone picture arrives");
    sync.request(true);
    same(30, photos.list().size(), "the album gives up a place");
    check(photos.read(Digests.sha256(Fakes.jpeg(70, 5000))) != null, "to the newer phone picture");
    same(29L, ((Number) status().get("count")).longValue(), "album count after sharing");

    check(sync.disconnect(), "disconnect");
    same(null, status(), "no status after disconnect");
    same(1, photos.list().size(), "disconnect removes only album pictures");
    check(!storage.values.get("icloud").contains(TOKEN), "disconnect forgets the link");
    check(!sync.request(true) && !sync.due(), "no sync after disconnect");
    check(new ICloudSync(storage, clock, album, photos.library, Fakes.inline(), events.album).status() == null, "disconnect survives a restart");

    fresh();
    sync.connect(LINK);
    Fakes.Album other = new Fakes.Album();
    other.name = "Holiday";
    other.add(guid(41), day(11), image(41), 2048);
    ICloudSync switching = new ICloudSync(storage, clock, other, photos.library, Fakes.inline(), events.album);
    switching.connect("https://www.icloud.com/sharedalbum/#B0Anotheralbum1");
    same("{\"name\":\"Holiday\",\"count\":1,\"lastSync\":\"2026-10-11T00:00:00Z\",\"syncing\":false,\"error\":null}", Json.write(switching.status()), "a different link replaces the album and its pictures");
    int again = other.posts.size();
    switching.connect("https://www.icloud.com/sharedalbum/#B0Anotheralbum1");
    same(1, photos.list().size(), "the same link keeps its pictures");
    same(again + 1, other.posts.size(), "and simply syncs");

    fresh();
    final int[] overlapping = {0};
    final List<Runnable> queued = new ArrayList<>();
    final ICloudSync[] reentrant = new ICloudSync[1];
    Fakes.Album watched = new Fakes.Album() {
      @Override public synchronized ICloudAlbum.Reply post(String url, String body) throws IOException {
        if (url.endsWith("/webstream") && overlapping[0]++ == 0) {
          reentrant[0].sync();
          check(Boolean.TRUE.equals(reentrant[0].status().get("syncing")), "status says syncing while a sync runs");
          check(!reentrant[0].due(), "nothing is due while a sync runs");
        }
        return super.post(url, body);
      }
    };
    watched.add(guid(1), day(1), image(1), 2048);
    reentrant[0] = new ICloudSync(storage, clock, watched, photos.library, new ICloudSync.Runner() {
      @Override public void start(Runnable work) {
        queued.add(work);
      }
    }, events.album);
    reentrant[0].connect(LINK);
    same(1, queued.size(), "connect queues one sync");
    same(0, watched.posts.size(), "and does not block the caller");
    same(Boolean.FALSE, reentrant[0].status().get("syncing"), "queued is not syncing");
    queued.get(0).run();
    same(2, overlapping[0], "an overlapping request is folded into one follow-up pass, never run in parallel");
    same(1, watched.downloads, "and nothing is downloaded twice");
    same(Boolean.FALSE, reentrant[0].status().get("syncing"), "syncing ends");

    fresh();
    final ICloudSync[] leaving = new ICloudSync[1];
    Fakes.Album interrupted = new Fakes.Album() {
      @Override public synchronized byte[] get(String url, int limit) throws IOException {
        leaving[0].disconnect();
        return super.get(url, limit);
      }
    };
    interrupted.add(guid(1), day(1), image(1), 2048);
    interrupted.add(guid(2), day(2), image(2), 2048);
    leaving[0] = new ICloudSync(storage, clock, interrupted, photos.library, Fakes.inline(), events.album);
    leaving[0].connect(LINK);
    same(0, photos.list().size(), "disconnecting during a sync leaves no album pictures behind");
    same(null, leaving[0].status(), "and stays disconnected");
    same(1, interrupted.downloads, "the sync stops at once");
  }

  static Fakes.Reply call(String method, String target, String json) throws Exception {
    return Fakes.inMemory(api, Fakes.json(method, target, bearer, json));
  }

  static long rev() throws Exception {
    return (Long) call("GET", "/v1/state", null).object().get("rev");
  }

  static Object albumState() throws Exception {
    return Json.map(call("GET", "/v1/state", null).object().get("settings")).get("icloudAlbum");
  }

  static void endpoints() throws Exception {
    fresh();
    api = new LocalApi(storage, clock, new Fakes.CalendarShelf(), photos, sync, events);
    Fakes.inMemory(api, Fakes.json("POST", "/v1/pair/start", null, null));
    bearer = (String) Fakes.inMemory(api, Fakes.json("POST", "/v1/pair/finish", null, "{\"code\":\"" + events.code + "\",\"deviceName\":\"Phone\"}")).object().get("token");
    same(null, albumState(), "state has a null album before connecting");
    check(Json.map(call("GET", "/v1/state", null).object().get("settings")).containsKey("icloudAlbum"), "the key is always present");
    for (String route : new String[] {"PUT /v1/settings/icloud-album", "DELETE /v1/settings/icloud-album", "POST /v1/settings/icloud-album/sync"}) {
      same(401, Fakes.inMemory(api, Fakes.json(route.split(" ")[0], route.split(" ")[1], null, "{\"url\":\"" + LINK + "\"}")).status, "token needed for " + route);
    }
    same(null, albumState(), "unauthenticated calls change nothing");
    same(409, call("POST", "/v1/settings/icloud-album/sync", null).status, "sync without an album");
    same("{\"rev\":0}", call("DELETE", "/v1/settings/icloud-album", null).text(), "disconnecting nothing is harmless");
    String[] bad = {"{}", "{\"url\":5}", "{\"url\":\"\"}", "{\"url\":\"" + TOKEN + "\"}", "{\"url\":\"http://www.icloud.com/sharedalbum/#" + TOKEN + "\"}",
        "{\"url\":\"https://www.icloud.com.evil.test/sharedalbum/#" + TOKEN + "\"}", "{\"url\":\"https://share.icloud.com/photos/0a1B2c3D4e5F6g7H8i9J\"}", "[]", "{"};
    for (String body : bad) {
      Fakes.Reply reply = call("PUT", "/v1/settings/icloud-album", body);
      same(400, reply.status, "rejected album link " + body);
      check(!reply.text().contains(TOKEN), "errors do not echo the link");
    }
    same(0L, rev(), "rejected links change nothing");
    same(0, album.posts.size(), "and contact nobody");

    byte[] sent = Fakes.jpeg(60, 9000);
    same(200, Fakes.inMemory(api, Fakes.request("POST", "/v1/photos", bearer, "image/jpeg", sent)).status, "a phone picture");
    Fakes.Reply connected = call("PUT", "/v1/settings/icloud-album", "{\"url\":\"" + LINK + "\"}");
    same("{\"rev\":2}", connected.text(), "connecting is one revision once its first sync lands");
    Fakes.Reply state = call("GET", "/v1/state", null);
    same("{\"name\":\"Family\",\"count\":4,\"lastSync\":\"2026-10-11T00:00:00Z\",\"syncing\":false,\"error\":null}",
        Json.write(Json.map(state.object().get("settings")).get("icloudAlbum")), "state carries the album status");
    same("{\"count\":5}", Json.write(state.object().get("photos")), "album pictures count in the library");
    check(!state.text().contains(TOKEN) && !state.text().contains("sharedalbum") && !state.text().contains("icloud.com"), "state never returns the link");
    same(5, call("GET", "/v1/photos", null).list().size(), "album pictures are listed with the others");
    check(!call("GET", "/v1/photos", null).text().contains(TOKEN), "the photo list has no link");
    same(304, call("GET", "/v1/state?since=2", null).status, "nothing else changed");

    album.add(guid(5), day(5), image(5), 2048);
    same(204, call("POST", "/v1/settings/icloud-album/sync", null).status, "sync now");
    same(0, call("POST", "/v1/settings/icloud-album/sync", null).body.length, "204 has no body");
    same(3L, rev(), "a sync that changed something is one revision");
    same(5L, Json.map(albumState()).get("count"), "the new picture is counted");
    clock.now += 60000L;
    album.offline = true;
    same(204, call("POST", "/v1/settings/icloud-album/sync", null).status, "a failing sync still answers");
    same(4L, rev(), "an error is one revision");
    check(((String) Json.map(albumState()).get("error")).contains("Could not reach iCloud"), "state carries the error");
    same(304, call("GET", "/v1/state?since=4", null).status, "and only one");
    album.offline = false;
    call("POST", "/v1/settings/icloud-album/sync", null);
    same(null, Json.map(albumState()).get("error"), "recovery clears the error");
    same(5L, rev(), "recovery is one revision");

    String photoId = Digests.sha256(image(5));
    same(204, call("DELETE", "/v1/photos/" + photoId, null).status, "the phone can delete an album picture");
    photos.hidden.add(photoId);
    int downloads = album.downloads;
    call("POST", "/v1/settings/icloud-album/sync", null);
    same(downloads, album.downloads, "and it stays deleted");

    Fakes.Reply removed = call("DELETE", "/v1/settings/icloud-album", null);
    same(200, removed.status, "disconnect");
    same(null, albumState(), "album is null after disconnect");
    same("{\"count\":1}", Json.write(call("GET", "/v1/state", null).object().get("photos")), "phone pictures stay after disconnect");
    check(photos.read(Digests.sha256(sent)) != null, "the phone picture is intact");
    same(removed.object().get("rev"), rev(), "disconnect is one revision");
    same(409, call("POST", "/v1/settings/icloud-album/sync", null).status, "sync after disconnect");
    same(404, call("GET", "/v1/settings/icloud-album", null).status, "the link cannot be read back");
    same(404, call("PUT", "/v1/settings/icloud-album/sync", "{}").status, "wrong method on sync");

    same("null", api.icloudStatus(), "bridge status without an album");
    same("{\"ok\":true}", api.icloudConnect(LINK), "bridge connect");
    same(4L, Json.map(Json.parse(api.icloudStatus())).get("count"), "bridge status after connect");
    check(!api.icloudStatus().contains(TOKEN), "bridge status has no link");
    Map<String, Object> refused = Json.map(Json.parse(api.icloudConnect("https://example.test/album")));
    same(Boolean.FALSE, refused.get("ok"), "bridge rejects other links");
    check(refused.get("error") instanceof String && !refused.containsKey("url"), "with a reason");
    same(Boolean.FALSE, Json.map(Json.parse(api.icloudConnect(null))).get("ok"), "bridge rejects a missing link");
    same(4L, Json.map(Json.parse(api.icloudStatus())).get("count"), "a rejected link leaves the album connected");
    int posts = album.posts.size();
    api.icloudSync();
    same(posts + 1, album.posts.size(), "bridge sync runs");
    check(api.icloudDisconnect() && !api.icloudDisconnect(), "bridge disconnect is true once");
    same("null", api.icloudStatus(), "bridge status after disconnect");
    api.icloudSync();
    same(posts + 1, album.posts.size(), "bridge sync without an album does nothing");
  }

  static void robustness() throws Exception {
    fresh();
    album.rawStream = "{\"streamName\":\"Fa‮mily \ud83d" + new String(new char[100]).replace("\0", "😀") + "\",\"photos\":[]}";
    ICloudAlbum.Listing listing = ICloudAlbum.list(album, TOKEN, null);
    same(80, listing.name.codePointCount(0, listing.name.length()), "album names are cut to eighty code points");
    check(listing.name.startsWith("Family ") && listing.name.endsWith("😀"), "without direction overrides or half characters");
    for (int i = 0; i < listing.name.length(); i++) check(!Fields.forbidden(listing.name, i), "album name character " + i + " is safe");

    fresh();
    byte[] png = image(21);
    png[0] = (byte) 0x89;
    png[1] = 'P';
    png[2] = 'N';
    album.add(guid(21), day(21), png, 2048);
    byte[] gif = image(22);
    System.arraycopy("GIF89a".getBytes("US-ASCII"), 0, gif, 0, 6);
    album.add(guid(22), day(22), gif, 2048);
    sync.connect(LINK);
    same(4L, ((Number) status().get("count")).longValue(), "only JPEG downloads reach the picture decoder");
    same(4, photos.albumDownloads, "non-JPEG downloads are never handed to the library");
    same(null, status().get("error"), "a non-JPEG picture is skipped quietly");
    int downloads = album.downloads;
    sync.request(true);
    same(downloads, album.downloads, "and is not fetched again");

    fresh();
    StringBuilder bomb = new StringBuilder(ICloudHttp.MAX_ANSWER).append("{\"photos\":[");
    while (bomb.length() < ICloudHttp.MAX_ANSWER - 8) bomb.append("{},");
    album.rawStream = bomb.append("{}]}").toString();
    check(ICloudHttp.MAX_ANSWER <= 2 * 1024 * 1024, "answers are capped at two mebibytes");
    final Throwable[] escaped = new Throwable[1];
    final ICloudSync bombed = sync;
    Thread worker = new Thread(new Runnable() {
      @Override public void run() {
        try {
          bombed.connect(LINK);
        } catch (ApiException impossible) {
          throw new IllegalStateException(impossible);
        }
      }
    });
    worker.setUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
      @Override public void uncaughtException(Thread thread, Throwable problem) {
        escaped[0] = problem;
      }
    });
    worker.start();
    worker.join();
    same(null, escaped[0], "an answer made of empty objects does not escape the worker");
    same(Boolean.FALSE, status().get("syncing"), "syncing ends after the hostile answer");
    check(status().get("error") != null, "and it is recorded as a failure");

    for (final Throwable thrown : new Throwable[] {new OutOfMemoryError("test"), new StackOverflowError(), new IllegalStateException("test")}) {
      fresh();
      final boolean[] failing = {false};
      Fakes.Album fragile = new Fakes.Album() {
        @Override public synchronized ICloudAlbum.Reply post(String url, String body) throws IOException {
          if (failing[0] && thrown instanceof Error) throw (Error) thrown;
          if (failing[0]) throw (RuntimeException) thrown;
          return super.post(url, body);
        }
      };
      fragile.add(guid(1), day(1), image(1), 2048);
      ICloudSync survivor = new ICloudSync(storage, clock, fragile, photos.library, Fakes.inline(), events.album);
      survivor.connect(LINK);
      failing[0] = true;
      survivor.request(true);
      same("The album could not be synced.", survivor.status().get("error"), thrown.getClass().getSimpleName() + " is recorded as a failure");
      same(Boolean.FALSE, survivor.status().get("syncing"), "syncing ends after " + thrown.getClass().getSimpleName());
      same(1L, ((Number) survivor.status().get("count")).longValue(), "pictures survive " + thrown.getClass().getSimpleName());
      check(!survivor.due(), "and the failure backs off");
      failing[0] = false;
      survivor.request(true);
      same(null, survivor.status().get("error"), "the next sync recovers");
    }

    fresh();
    final List<Runnable> queued = new ArrayList<>();
    final ICloudSync[] busy = new ICloudSync[1];
    final int[] passes = {0};
    Fakes.Album counted = new Fakes.Album() {
      @Override public synchronized ICloudAlbum.Reply post(String url, String body) throws IOException {
        if (url.endsWith("/webstream") && passes[0]++ == 0) for (int i = 0; i < 5; i++) busy[0].request(true);
        return super.post(url, body);
      }
    };
    counted.add(guid(1), day(1), image(1), 2048);
    busy[0] = new ICloudSync(storage, clock, counted, photos.library, new ICloudSync.Runner() {
      @Override public void start(Runnable work) {
        queued.add(work);
      }
    }, events.album);
    busy[0].connect(LINK);
    for (int i = 0; i < 20; i++) busy[0].request(true);
    busy[0].request(false);
    same(1, queued.size(), "requests while one sync is pending queue nothing more");
    queued.get(0).run();
    same(1, queued.size(), "requests while a sync runs queue nothing more");
    same(2, passes[0], "they fold into one follow-up pass");
    busy[0].request(true);
    same(2, queued.size(), "a request after it finished queues the next sync");
  }

  public static void main(String[] args) throws Exception {
    java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("UTC"));
    links();
    derivatives();
    listing();
    planning();
    syncing();
    endpoints();
    robustness();
    System.out.println("ICloud: " + checks + " checks passed");
  }
}
