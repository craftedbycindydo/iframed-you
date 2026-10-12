package com.wesbos.homehq;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

public final class DevServer {
  private static LocalApi api;
  private static volatile String phase = "idle";
  private static volatile String tap = "none";
  private static volatile long tapDelay;

  private static void openWindow() {
    System.out.println("pairing window " + api.pairingOpen());
  }

  private static void changed(String state) throws Json.Malformed {
    Map<String, Object> shown = Json.map(Json.parse(state));
    phase = (String) shown.get("phase");
    System.out.println("pairing " + state);
    if (!phase.equals("code")) return;
    final String pick = api.pairingPick();
    final List<Object> numbers = Json.list(shown.get("numbers"));
    System.out.println("PAIRING CODE " + shown.get("code") + " numbers " + numbers.get(0) + " " + numbers.get(1) + " " + numbers.get(2) + " pick " + pick);
    if (tap.equals("none")) return;
    Thread tapping = new Thread(new Runnable() {
      @Override public void run() {
        try {
          Thread.sleep(tapDelay);
        } catch (InterruptedException stopped) {
          return;
        }
        if (!pick.equals(api.pairingPick())) return;
        if (tap.equals("cancel")) {
          System.out.println("auto-tap Cancel");
          api.pairingCancel();
          return;
        }
        String number = pick;
        for (Object shownNumber : numbers) if (tap.equals("decoy") && !shownNumber.equals(pick)) number = (String) shownNumber;
        System.out.println("auto-tap " + number + (api.pairingTap(number) ? " approved" : " refused"));
      }
    }, "auto-tap");
    tapping.setDaemon(true);
    tapping.start();
  }

  private static String control(String target) {
    if (target.equals("/open")) openWindow();
    else if (target.equals("/cancel")) api.pairingCancel();
    else if (target.startsWith("/tap/")) api.pairingTap(target.substring(5));
    else if (!target.equals("/state")) return null;
    Map<String, Object> status = Json.map(Json.object("fp", api.identity().fp, "frameId", api.frameId(), "pick", api.pairingPick()));
    try {
      status.put("pairing", Json.map(Json.parse(api.pairingStatus(0, false, ""))).get("pairing"));
    } catch (Json.Malformed impossible) {
      throw new IllegalStateException(impossible);
    }
    return Json.write(status);
  }

  private static void serveControl(final ServerSocket listening) {
    Thread serving = new Thread(new Runnable() {
      @Override public void run() {
        while (true) {
          try (Socket caller = listening.accept()) {
            caller.setSoTimeout(2000);
            String line = new BufferedReader(new InputStreamReader(caller.getInputStream(), StandardCharsets.ISO_8859_1)).readLine();
            String[] parts = line == null ? new String[0] : line.split(" ");
            String answer = parts.length == 3 ? control(parts[1]) : null;
            byte[] body = ((answer == null ? "{\"error\":\"Use /state, /open, /cancel or /tap/NN\"}" : answer) + "\n").getBytes(StandardCharsets.UTF_8);
            caller.getOutputStream().write(("HTTP/1.1 " + (answer == null ? "404 Not Found" : "200 OK") + "\r\nContent-Type: application/json\r\nContent-Length: "
                + body.length + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.ISO_8859_1));
            caller.getOutputStream().write(body);
            caller.getOutputStream().flush();
          } catch (IOException | RuntimeException dropped) {
            if (listening.isClosed()) return;
          }
        }
      }
    }, "control");
    serving.setDaemon(true);
    serving.start();
  }

  public static void main(String[] args) throws Exception {
    int port = args.length > 0 ? Integer.parseInt(args[0]) : LocalServer.PREFERRED_PORT;
    InetAddress address = args.length > 1 && args[1].equals("lan") ? null : InetAddress.getLoopbackAddress();
    boolean fakeAlbum = args.length > 2 && args[2].equals("fake-icloud");
    boolean window = args.length > 3 && args[3].equals("window");
    tap = args.length > 4 ? args[4] : "none";
    tapDelay = args.length > 5 ? Long.parseLong(args[5]) : 0;
    int controlPort = args.length > 6 ? Integer.parseInt(args[6]) : -1;
    Fakes.Storage storage = new Fakes.Storage();
    Fakes.PhotoShelf photos = new Fakes.PhotoShelf();
    FrameTime.Clock clock = new FrameTime.Clock() {
      @Override public long now() {
        return System.currentTimeMillis();
      }
    };
    FrameTime.Uptime uptime = new FrameTime.Uptime() {
      @Override public long millis() {
        return System.nanoTime() / 1000000L;
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
    api = new LocalApi(storage, clock, uptime, new Fakes.CalendarShelf(), photos, album[0], new LocalApi.Events() {
      @Override public void householdChanged(String snapshot) {
        System.out.println("household " + snapshot);
      }

      @Override public void pairingChanged(String state, long remaining) {
        try {
          changed(state);
        } catch (Json.Malformed impossible) {
          throw new IllegalStateException(impossible);
        }
      }

      @Override public void settingsRequested(String settings) {
        System.out.println("settings requested " + settings);
      }
    });
    LocalServer server = new LocalServer(api);
    int bound = server.start(address, port);
    System.out.println("Skylit dev frame " + api.frameId() + " fp " + api.identity().fp + " listening on "
        + (address == null ? "all interfaces" : "127.0.0.1") + " port " + bound);
    if (controlPort >= 0) {
      ServerSocket control = new ServerSocket(controlPort, 8, InetAddress.getLoopbackAddress());
      serveControl(control);
      System.out.println("control on 127.0.0.1 port " + control.getLocalPort());
    }
    if (window) openWindow();
    Thread keyboard = new Thread(new Runnable() {
      @Override public void run() {
        try {
          BufferedReader lines = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
          while (lines.readLine() != null) openWindow();
        } catch (IOException closed) {
          return;
        }
      }
    }, "keyboard");
    keyboard.setDaemon(true);
    keyboard.start();
    for (int second = 1; true; second++) {
      Thread.sleep(1000L);
      api.pairingStatus(0, false, "");
      if (second % 60 == 0) album[0].request(false);
    }
  }
}
