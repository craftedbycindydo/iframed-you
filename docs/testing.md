# Testing Skylit

Run from the repository root with Node 18+, Python 3.10+, and JDK 17 for Java tests:

```sh
node --test tests/*.test.cjs
python3 -m unittest discover -s tests
python3 scripts/check_public.py --history
```

The Python run also compiles the pure-Java frame code (local server, pairing, household
store, iCloud sync, thermostat client and bridge) with the JDK and runs it against
fakes under `tests/android/jvm/`; allow about a minute and a half. `python3
tests/test_tcc.py` runs the thermostat part alone.

The suite uses Node/Python standard test runners. No runtime framework or network
service is needed. Test observable behavior and failure boundaries; avoid snapshots
of household data, tests that only repeat constants, and broad mocks of unrelated
APIs. For example the synthetic preview mocks only the forecast endpoint, and a
regression test ensures script/resource fetches pass through unchanged.

## Automated coverage

- Appearance: sunrise/sunset boundaries, both DST transition dates, date line,
  polar day/night, missing/invalid location, manual overrides, legacy settings.
- Contrast: the optional High contrast palette in both modes, text surfaces,
  accent/button text and control borders. Regular palettes are visually reviewed.
- Overview: expired/ongoing/all-day events, exclusive all-day end dates, result limit,
  stable sorting, weather validity/freshness.
- Calendar controller: overlapping worker completion, stale errors, month-independent
  upcoming list, removal during an in-flight parse without resurrecting events,
  grouped overview dates, redundant metadata removal and offline warning visibility.
- Calendar parsing: recurrence, DST, exceptions, cancellation, moved occurrences,
  all-day/floating/overnight events, organizer inheritance, malformed data and
  expansion limits. Inviter approval/revocation is tested as an exact display rule.
- Photos: slideshow style fallback and collage wraparound without duplicate images, private local image URL
  validation, malformed native status, and the
  actual Java policy for account, age, count, dimensions and downsampling. A
  serialized multipart message tests the pinned mail library's image decoding.
- Onboarding: fresh-install launch, upgrade and explicit-route preservation,
  dismissal persistence, reopening and links to the existing setup controls.
- Android: feed URL/size/redirect boundaries, native navigation allowlists, TLS-only
  device selection; packaging/privacy sentinels keep personal data outside APKs.
- Momo: canvas geometry, rendering pause/resume, reduced motion, persistence,
  gallery, daily clothing and local-time/DST routines.
- Phone link (JVM): HTTP parsing and limits, TLS-only listener and suites, the v2
  pairing exchange and its test vector, tokens, every route and limit, names in
  many scripts and invisible-only names, damaged stored rows, a store that refuses
  to save, a clock that is not set, restart persistence, twenty devices.
- iCloud album (JVM): link forms, listing, planning, sync, back-off on the elapsed
  clock, clock jumps, damaged saved state and its pictures.
- Thermostats (JVM): sign-in, redirects, lock-out and its persistence, reading,
  set-point/mode/resume, polling pace, staleness and clock jumps; the bridge's
  snapshots and messages.
- Household and pairing UI: chores, shopping, the pairing overlay and its endings,
  the device list, remote settings.

`python3 scripts/test_calendar_device.py` runs isolated storage/failure tests on an
explicitly selected paired frame using in-memory test data. It does not populate
household calendars. Unit tests supplement, rather than replace, device checks.

## Visual and device checks

1. Run `python3 scripts/preview.py` for synthetic data at localhost:8767; restart
   after edits. Check every tab, long titles/multiple events, details, month/Today
   navigation, theme changes and persisted settings after reload.
2. Inspect 1280×720 CSS pixels (1920×1080 at the tested frame's 1.5 density), a normal
   desktop viewport and a narrow viewport. Check overflow, readable text, focus and
   touch targets. Public screenshots must come from the synthetic preview only.
   Also check that a fresh browser opens the guide and an upgraded frame does not;
   reopen the guide from Settings to inspect it without resetting household data.
3. Build with `python3 scripts/build.py`; verify signature and inspect the final APK
   with `python3 scripts/check_public.py --history --apk dist/skylit.apk`.
4. Identify exact model, Android and transport, then install in place with the same
   signing key. Inspect all affected tabs and test settings persistence, HOME/back,
   weather refresh, and appearance on actual hardware. Do not change system time
   or Wi-Fi to simulate solar transitions; use deterministic unit cases.
5. For household Calendar setup, verify an actual owner-made event refresh using
   docs/calendar.md. A loaded grid or synthetic screenshot does not prove syncing.
   Test an unapproved organizer, approval, revocation and cancellation separately.
   For email Photos, follow docs/photos.md and verify a real image import, manual
   browsing/zoom, all three slideshow styles, control fade, idle entry/return and
   cache removal on the physical frame. Do not erase household cache solely for a
   release check unless a separate replacement source is ready.
6. Record results, limitations and rollback in the private setup record and its
   device Downloads copy. Run Gitleaks against history and a source export before
   publication. Follow docs/releasing.md for publication and metadata checks.

There is no claimed percentage coverage, full accessibility certification, or
long-term unattended stability result. See docs/verification.md for checks actually run.

## Optional rendered regression suite

Start `python3 scripts/preview.py`, then run `node scripts/check_ui.cjs` with a local
Playwright installation. `SKYLIT_PLAYWRIGHT` may specify its module path and
`SKYLIT_CHROME` an existing Chrome executable; these are test-only dependencies.
`--capture docs/reviews/DATE-implementation` writes synthetic screenshots plus a
manifest. It exercises Settings dialog context, focus trapping, Close/backdrop/Escape/Back,
fixed headers with internal scroll, category/return routes, Settings curation/reload, icon controls and slideshow styles,
month agenda/search/Settings visibility/metadata, local shopping undo/persistence, privacy
pause, optional navigation and display-transfer exclusion. It also checks that the
Overview never clips an event or shows an empty Upcoming card for 0–8 thermostat
tiles, that Settings closes itself (later while typing or while something is in
progress), and that every Settings text field clears an on-screen keyboard. Its viewport matrix
covers 960×540, 1024×640, 1280×720/800, 1440×900, 1600×900, 1920×1080/1200 and
390×844, both text profiles, with six feeds/long titles/50 thumbnails.

`scripts/dev_server.py` runs the frame's real server on this computer with throwaway
data (`--pair-window`, `--auto-approve`, `--fake-icloud`, `--control-port`) for
socket-level and iPhone-app testing without a frame. Its control port also takes
`/household/<URL-encoded op>` (a dashboard change through the bridge) and `/restart`
(a new server over the same stored data). `tests/test_rehearsal.py` uses both to walk
one morning end to end: pair, fill the household, photos, settings, a calendar and
the canned album, dashboard changes, a second phone, the first phone unpairing and
a restart.

Record any first-load retry separately. The previously observed desktop module
omission is not proof of a native asset failure. Chrome browser geometry coverage
does not replace Android WebView 95, touch, native quiet timing or service delivery
checks. The native calendar test also covers metadata edits during pending refresh.

`python3 scripts/test_photo_device.py --usb` identifies the configured USB frame
and runs actual PhotoStore/Bitmap/JSON code in an isolated shell-owned temporary
directory with in-memory preferences and synthetic images. It covers received-date
windows, count modes, deduplication, excluded-slot capacity, persistence through
reopening/pruning/reimport, restore/erase and importer/exclusion races. It never
opens the household cache or mailbox. Omit `--usb` to use paired TLS transport.
