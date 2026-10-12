package com.wesbos.homehq;

import java.net.InetAddress;

public final class DevServer {
  public static void main(String[] args) throws Exception {
    int port = args.length > 0 ? Integer.parseInt(args[0]) : LocalServer.PREFERRED_PORT;
    InetAddress address = args.length > 1 && args[1].equals("lan") ? null : InetAddress.getLoopbackAddress();
    boolean fakeAlbum = args.length > 2 && args[2].equals("fake-icloud");
    Fakes.Storage storage = new Fakes.Storage();
    Fakes.PhotoShelf photos = new Fakes.PhotoShelf();
    FrameTime.Clock clock = new FrameTime.Clock() {
      @Override public long now() {
        return System.currentTimeMillis();
      }
    };
    final ICloudSync[] album = new ICloudSync[1];
    album[0] = new ICloudSync(storage, clock, fakeAlbum ? Fakes.sampleAlbum() : new ICloudHttp(), photos.library, new ICloudSync.Runner() {
      @Override public void start(Runnable work) {
        Thread thread = new Thread(work, "album-sync");
        thread.setDaemon(true);
        thread.start();
      }
    }, new ICloudSync.Listener() {
      @Override public void changed() {
        System.out.println("icloud " + Json.write(album[0].status()));
      }
    });
    LocalApi api = new LocalApi(storage, clock, new Fakes.CalendarShelf(), photos, album[0], new LocalApi.Events() {
      @Override public void householdChanged(String snapshot) {
        System.out.println("household " + snapshot);
      }

      @Override public void pairingShown(String code, long expiresAt) {
        System.out.println("PAIRING CODE " + code + " (expires " + FrameTime.iso(expiresAt) + ")");
      }

      @Override public void pairingHidden() {
        System.out.println("pairing code hidden");
      }

      @Override public void settingsRequested(String settings) {
        System.out.println("settings requested " + settings);
      }
    });
    LocalServer server = new LocalServer(api);
    int bound = server.start(address, port);
    System.out.println("Skylit dev frame " + api.frameId() + " listening on "
        + (address == null ? "all interfaces" : "127.0.0.1") + " port " + bound);
    while (true) {
      Thread.sleep(60000L);
      album[0].request(false);
    }
  }
}
