# iFramed You

A cheap Android photo frame turned into a family dashboard you own, plus a native
iPhone app that controls it over your home Wi-Fi. No subscription, no vendor account,
no cloud service of ours.

<img src="design/logo/iframed-you-512.png" width="120" alt="iFramed You logo">

This repository is a modified copy of [Skylit](https://github.com/sachasayan/skylit) by
Sacha Sayan, which was itself inspired by Wes Bos's
[photo-frame-dashboard](https://github.com/wesbos/photo-frame-dashboard). The dashboard,
themes, Momo, calendar, weather and photo viewer are Skylit's work. See
[Credits](#credits) and [docs/credits.md](docs/credits.md).

## What this fork adds

| Area | Addition |
| --- | --- |
| Frame | A paired local HTTP server inside the Android viewer, advertised over Bonjour as `_skylit._tcp` |
| Dashboard | A Chores page (people, daily and weekly chores, tap to complete) and a shared shopping list |
| Photos | Pictures sent straight from a phone, and a mirrored public iCloud Shared Album |
| iPhone | `ios/`: a SwiftUI app for chores, shopping, photos and frame setup, including setting the weather city from the phone's location |
| Contract | [docs/local-api.md](docs/local-api.md): every endpoint, the pairing flow and the dashboard bridge |

Everything stays on the home network. The phone finds the frame by name, pairs once with a
six-digit code shown on the frame, and is trusted from then on.

## Status

Tested on one frame: a TIKVITO S580 sold as a Frameo frame (Rockchip RK3126, Android 6.0.1,
1280×800, 1 GB RAM, WebView 106).

| Verified on that frame | Not yet verified |
| --- | --- |
| Dashboard, Chores page, pairing overlay | The iPhone app on a physical phone |
| Local API: pairing, chores, shopping, photo upload, theme change | iCloud album sync against a real album |
| Bonjour discovery from a Mac | Long-running stability (one GPU-driver hang seen, see below) |

Known limits:

- The photo library holds 30 pictures by default and 50 at most, shared by phone, email and album pictures.
- iCloud album sync uses the unofficial endpoints behind Apple's public album web page. Only
  `https://www.icloud.com/sharedalbum/#…` links are accepted.
- Traffic between phone and frame is TLS 1.2 on the local network. The phone pins the frame's self-signed certificate while pairing.
- Emoji newer than Android 6's font show as an empty box on the frame.
- The frame froze once with its render thread stuck in the Mali GPU driver. The cause is not known.

## Layout

```
web/        Dashboard (plain HTML, CSS, JavaScript; no build step)
android/    Android viewer, local server, household store, iCloud sync (no Gradle)
ios/        iPhone app (XcodeGen project + SkylitCore Swift package)
docs/       Contract, architecture, setup guides
tests/      JavaScript, Python and desktop-JVM tests
scripts/    Build, preview, dev server, privacy check
```

## Run the tests

```sh
node --test tests/*.test.cjs
python3 -m unittest discover -s tests
cd ios/SkylitCore && swift test
```

## Preview the dashboard in a browser

```sh
python3 scripts/preview.py
```

Open http://127.0.0.1:8767. The preview uses made-up events, weather, chores and photos.

## Run the frame's server on a Mac

Useful for developing the iPhone app without a frame:

```sh
python3 scripts/dev_server.py --port 8765 --fake-icloud --lan --advertise --pair-window --auto-approve 20
```

It prints its certificate fingerprint, then the pairing code and the number to tap once a phone
connects. Press Enter to open another pairing window.

## Build the Android viewer

Needs JDK 17 and Android SDK build-tools 34 and platform 34. Create `.local/build.json`:

```json
{
  "java": "/path/to/jdk-17",
  "build_tools": "/path/to/android-sdk/build-tools/34.0.0",
  "android_jar": "/path/to/android-sdk/platforms/android-34/android.jar",
  "signing_key": "/path/to/your.keystore"
}
```

```sh
python3 scripts/build.py
adb install -r dist/skylit.apk
```

The package ID is still `com.wesbos.homehq`, inherited from the projects this builds on.
The two-finger hold exits to Rootless Pixel Launcher (`amirz.rootless.nexuslauncher`); install
it first or change `openStockApp` in `MainActivity.java`.

## Build the iPhone app

```sh
cd ios && xcodegen generate && open Skylit.xcodeproj
```

Set your own development team and bundle identifier in `ios/project.yml`. The app needs
Local Network permission to find the frame.

## Getting a frame ready

This repository does not unlock a frame. The S580 above needed no exploit: Frameo's own
Settings → About → Beta Program → ADB access turned on ADB, the frame's USB port only works
as a host so ADB was reached over Wi-Fi on port 5555, and the firmware ships with root.
WebView was upgraded from 44 to 106 following Wes Bos's
[BIUFRAME guide](https://github.com/wesbos/photo-frame-dashboard/blob/main/docs/biuframe-setup-guide.md),
and the Frameo app was disabled with `pm disable`. Frames differ; back up the firmware first
and check your own hardware before following any guide.

A frame set up this way has passwordless root over the network. Keep it on a guest or IoT
Wi-Fi network.

## Credits

- [Skylit](https://github.com/sachasayan/skylit) by Sacha Sayan: the dashboard and Android viewer this is built on. Its original README is kept at [docs/skylit-upstream-readme.md](docs/skylit-upstream-readme.md).
- [photo-frame-dashboard](https://github.com/wesbos/photo-frame-dashboard) by Wes Bos: the frame research and the kiosk app Skylit started from.
- Third-party libraries and their licences are listed in [docs/credits.md](docs/credits.md).

Neither upstream project carries a licence file. This copy is published with attribution and
will be taken down or changed at either author's request.
