# Delivery verification — October 9, 2026

## Version 2.8 — Photos and inviter review

- Added a local email-photo importer, Android Keystore-protected app password,
  bounded private image cache and Skylit slideshow controls. Shared-album playback
  remains available and is still the default.
- Added organizer parsing and an optional on-frame approved-inviters rule across
  Calendar and Overview. This does not alter Google Contacts or Calendar's account
  invitation setting.
- 36 JavaScript tests and 11 Python tests passed, including organizer inheritance,
  review policy, private image URLs, native retention/size limits and multipart
  image extraction with the pinned mail libraries. A signed
  2.8.0 APK built and passed Android signature verification. Source/history/APK
  public-data scan found no file-content findings; historical commit author email
  still needs review before changing repository visibility.
- A synthetic 1280×720 preview was inspected for the Photos empty state, Calendar
  month and inviter panel. No personal pictures or events were used.
- On October 10, the signed 2.8.0 APK (version code 15) was installed in place over
  the explicitly selected USB transport on the Android 12 D156 frame at 1920×1080.
  The configured serial matched; the original Skylight app remained installed and
  Skylit remained HOME. Overview, Photos, Calendar, inviter review and the email
  setup form were visually checked on the frame. The existing shared-album source
  was restored after viewing the email empty state.
- No Gmail app password was entered. Real image import, cache pruning, offline
  playback and idle return for the new email source are **not verified**. Inviter
  review remains off, with no approved addresses or real test invitation; its
  approval/removal flow is not verified against Google Calendar.
- The household calendar is configured but its refresh failed during this check.
  Wi-Fi was enabled without an IPv4 lease or default route. One Wi-Fi off/on cycle
  did not restore a lease. No router settings or saved network credentials changed.
  A saved empty calendar is not evidence of current sync.
- The clean public source export began at commit `5099cb11cef368112b79d976905de0108297a2d3`.
  Its sole commit used a GitHub noreply address; the earlier development repository
  was retained privately. No APK was uploaded as a GitHub release. The locally built
  normal APK has SHA-256
  `8db92d2d1288bab1e7d1992fb1a52c8e2bb042ace6b36e3feacb300e3ae9fe70`;
  Android SDK 34 `apksigner` verified its v1, v2 and v3 signatures.
- See [photo setup](photos.md), [calendar setup](calendar.md) and the
  [feature review](feature-review.md) for activation, limits and acceptance tests.

Tested on the actual 1920×1080 Android 12 frame and in desktop Chrome.

**Release-status update — October 10, 2026:** The owner removed the former
license-clarification gate. References to that gate in the historical entries below
are superseded; see docs/releasing.md for the current release procedure.
The public source repository was prepared as a clean export with a GitHub noreply
commit identity; the earlier development history remains in a separate private
archive. No personal APK or household setup record is published.

## Passed

- Signed APK built with JDK 17 / Android SDK 34, verified and installed in place.
- Four tabs rendered: Weather, Photos, Home, Settings.
- Real Richmond Hill weather fetched from Open-Meteo; current, hourly and daily data rendered.
- Clock uses America/Toronto. Desktop 24-hour setting and city search checked.
- All three themes selected and visually inspected on the frame. Desktop theme survived reload.
- Supplied shared album loaded without sign-in. Native menu automation started a slideshow;
  successive actual-device captures showed different photos. Touch returned from idle photo mode.
- Default HOME survived a device reboot and dashboard reopened automatically.
- Two-minute idle timer fired after reboot; configured album and delay survived startup.
  After the Wi-Fi recovery, a fresh full idle test opened photos at 23:29:13 local
  after the last touch at about 23:27:12. Slideshow auto-started at 23:29:27,
  successive captures showed different photos, and one touch returned to weather.
- Home page reached Google sign-in. Existing Chrome household UI confirmed lights and thermostat.
- Disabled package list unchanged from baseline. Original app and watchdog remain enabled.
- Private GitHub source excludes local configuration, signing key, APKs and family screenshots.

## Observed issues and limits

The reboot exposed a network issue: Wi-Fi associated without an IPv4 address and
weather/Photos could not load. A Wi-Fi off/on cycle restored DHCP and Android's
validated internet connection. Live weather then refreshed successfully. No router
setting, saved network, or credential was changed. This is a recovered occurrence,
not proof that the underlying boot-time networking issue is permanently fixed.

Weather now retries failed requests after one minute, retains cached data with an
explicit saved-data message, and also refreshes on the browser online event.

Google Home account sign-in and device operations on the frame are not verified.
No thermostat, light, lock, speaker or account settings were changed. Google may
reject authentication on the older embedded browser.

No claim of long-term unattended stability, slideshow looping, immediate discovery
of newly added album photos, offline photo playback, or consumer Keep API access.
Two-finger stock-app gesture and deliberate renderer-crash recovery not physically tested.

## Follow-up

Finish Google Home sign-in on the frame, verify supported controls, then investigate
an authenticated shared Keep note for the voice shopping-list phase. If Wi-Fi again
fails after boot, investigate the firmware/router DHCP interaction separately.

## Version 2.1 — October 10, 2026

- Added and visually checked the Netflix tab on the physical frame.
- Netflix returned **Update required** / unsupported browser, operating system or device.
  Playback is blocked, not verified. The tab reports this limitation explicitly.
- Built and verified signed version code 3; installed successfully over paired TLS Wi-Fi ADB.
- Verified both Wi-Fi and developer-options shortcuts reached their intended activities.
- Four discovery-helper tests passed: exact device match, TLS-only connect service,
  connected-transport reuse, and invalid-endpoint rejection.
- Restart retained pairing but disabled wireless debugging. The Wi-Fi DHCP failure recurred.
  Reconnecting Wi-Fi and allowing wireless debugging again restored the connection.
  A second install over Wi-Fi succeeded without re-pairing. See docs/wireless.md.
- No system packages disabled. Original app remains present, and baseline disabled NFC unchanged.
- Updated on-device setup log verified against the Mac copy using SHA-256.
- User completed the separate Google account signup; signed-in identity verified in Chrome.
  Family album is viewable from that account through the shared link. Direct album invitation
  is prepared and awaits final access-grant confirmation. Home invitation remains pending
  the Google Home mobile app. No password set or 2FA configured by this setup; no account
  session copied to the frame.

## Version 2.2 — Momo

Replaced the sidebar wordmark with a procedural Canvas 2D companion. Added twelve
expressive reactions, gaze/scroll response, eleven accessories, persistent wardrobe
and motion settings, reduced-motion handling, and native/visibility pause hooks.
Five focused tests pass. Browser interaction checks and physical frame rendering /
wardrobe shortcut verified. See docs/momo.md for controls and verification scope.

## Version 2.3 — Momo gallery and daily rhythm

Twelve routine/rendering tests pass, including midnight, daylight-saving repeated hour,
night snoozing, morning yawns, gallery selection and daily-outfit persistence.
Chrome gallery and reload checks passed without captured console errors. Signed
version code 5 installed over paired TLS ADB. Gallery rendered on the physical
frame; New clothes every day enabled and selected beanie verified.

## Version 2.4 — YouTube, Calendar and distribution preparation

- Replaced Netflix with YouTube; the mobile site loads and search works on the frame.
  A public NASA video played, with elapsed time observed advancing from 0:43 to 1:05.
  Full-screen video and the Skylit return button both worked. Desktop layout is
  selectable but its video playback has not been separately verified.
- Added Google Calendar’s official web view with a saved, validated Calendar URL.
  Calendar URL rejection and persistence, plus YouTube layout persistence, checked
  in Chrome. The official “Sign in to continue to Google Calendar” screen renders correctly
  on the frame. Authenticated events/editing still require the owner’s frame sign-in.
- A clean browser starts without any album, household or location configured.
  An in-place frame upgrade preserved the existing weather/photo/Momo settings.
- Standard APK builds now use an asset allowlist and blank household config;
  private config requires explicit `--personal` and produces a differently named APK.
- Twelve JS tests and seven Python tests pass. Signature verification passes.
- Gitleaks 8.30.1 found no secrets in the original six commits or proposed source
  export. Additional all-blob and APK checks found no private album/account/household
  or device identifiers. This is a targeted publication check, not a full security audit.
- Commit metadata contains a personal author email. Public release must resolve it
  along with the upstream Android code’s missing license; no history was force-pushed.
- README, AGENTS, architecture, household setup, credits and release instructions
  are prepared. CI runs the source tests and privacy checks. Repository remains private.
- Android backup disabled and unused generic URL-handler intent filter removed.
  No system apps disabled, firmware changed, account permissions changed, or sessions copied.

### Hosted checks

The first GitHub Actions run did not execute any steps: GitHub reported that the
account’s Actions budget prevents further use. The equivalent 19 tests and privacy
checks passed locally. No billing settings were changed. Hosted CI success remains
unverified until the account permits a runner to start.

## Version 2.4.1 — Google sign-in redirect fix

The password-submit page remained dimmed with a progress bar. The last navigation
logged was to `gds.google.com`, a Google destination absent from the remote WebView’s
exact host allowlist. A test using the production navigation policy failed with
“Calendar password-submit redirect is blocked.” Adding this exact HTTPS hostname
for Google and YouTube sign-in made the test pass. Lookalike domains, HTTP and
unrelated hosts remain rejected. A blocked main-frame navigation now shows a notice.

After installing the upgrade, Calendar opened using the existing session without
another password entry. No credentials were inspected, copied or submitted by the
agent. Google displays an unsupported-browser banner for this frame’s WebView 95;
compatibility remains limited to the interactions actually verified.

The 12 JS and 8 Python tests pass, including a JDK-backed native navigation test.
Public-source/APK checks pass apart from the previously documented history metadata
review. This fix was installed over paired TLS ADB, preserving settings and app data.

Physical verification: dismissed the introductory notices, navigated from October
4–10 to October 11–17, and saw the Canadian Thanksgiving holiday render. Returned
to Today. No calendar events were created or edited. The sign-in stall is resolved;
full calendar feature compatibility and event editing are not yet certified.

## Version 2.5 — Integrated calendar

- Replaced the website shortcut with a themed month grid and two-week agenda, date
  navigation, event details and guided private Google iCal setup. No hosted service.
- Actual Android 12 / WebView 95 frame fetched Google's public Canadian holiday feed
  directly over HTTPS and showed Thanksgiving, Halloween and the DST transition.
  The temporary test source was labelled explicitly and removed after verification.
- Warm linen, Evening cocoa and Garden sage inspected on the physical frame at
  1920×1080. All six month rows fit. Original Warm linen preference restored.
- Feed configuration and saved events survived an in-place signed APK upgrade.
  Browser preview verified month navigation, details and the saved-data/error state
  using a public-data fixture; that fixture is not bundled in the application.
- 19 JavaScript tests and 9 Python tests pass. Calendar tests include all-day exclusive
  ends, overnight/floating times, weekly DST transitions, EXDATE, moved/cancelled
  occurrences, malformed feeds, unknown timezones, download size and URL boundaries.
- Isolated CalendarStore tests passed on Android using in-memory preferences and
  simulated downloads: network/parse failure keeps the prior cache, rejected/stale
  responses cannot overwrite it, removal deletes the URL and events, snapshots omit
  URLs, and removed calendars cannot be restored by in-flight responses. Run with
  `python3 scripts/test_calendar_device.py` when a paired frame is available.
- The standard APK has blank household configuration; signing and source/APK privacy
  checks pass. Private-feed detection was added to the publication check. ICAL.js
  2.2.1 is pinned, integrity-checked and bundled with its MPL-2.0 license.
- No household feed has been entered. Its private access and an owner-made event
  change must still be verified during setup. Actual Wi-Fi disconnection was not
  induced for this test; cache failure handling was tested without disrupting Wi-Fi.
- No accounts, router settings, system apps, firmware or HOME selection changed.
  The existing photo, weather, Momo and remote-service settings are preserved.

## Version 2.6 — Overview and appearance

- Added the default Overview with clock/date, shared forecast and a current-date
  upcoming list. Android Back returns there. Sidebar clock and calm link removed.
- Six paired palettes and Light/Dark/Automatic settings. The physical frame selected
  dark automatically before sunrise; manual Light and an Ocean/Automatic switch
  worked. Left on Linen + Automatic. Settings and daily Momo outfit survived upgrades.
- All seven tabs inspected on the 1920×1080 Android 12 / WebView 95 frame and Chrome.
  Desktop and narrow layouts inspected; the narrow calendar has no horizontal page
  overflow. Calendar grid, +N, month/Today navigation and event details checked with
  synthetic data; the actual frame remains unconfigured for household feeds.
- 29 JavaScript tests and 9 Python tests pass. Added solar/DST/polar/date-line cases,
  twelve palette contrast checks, overview selection/freshness, and calendar worker
  races/removal. The count is tests, not a coverage percentage.
- The synthetic forecast fixture initially intercepted unrelated fetches and caused
  intermittent preview module loading. Scoped the mock to its forecast endpoint;
  added a regression test and verified three consecutive complete reloads.
- Four public screenshots contain only explicitly synthetic data. README, agent
  directions, architecture, design critique and testing guide updated.
- Signed 2.6/version code 9 built and verified, installed in place over paired TLS
  ADB. Source/history/APK privacy check and Gitleaks history/source export pass.
  The ordinary APK has blank household configuration and excludes demo fixtures.
- Upstream GitHub still reports no license; repo remains private. Historical author
  metadata still needs a reviewed cleanup/clean export before publication. Hosted
  CI has not been certified successful; the latest prior run failed to execute
  because of the account's Actions budget. Local checks above ran successfully.
- No device clock, account, router, firmware, HOME selection or installed-app disable
  state changed. No live event editing, new account sign-in, Home operation or new
  video playback was claimed from this UI pass. Solar boundary transitions were
  tested with fixed unit dates, not by changing the frame's system clock.

## Version 2.6.1 — Softer regular palettes

- Restored original Linen, Cocoa (Linen dark), and Sage light colours. Softened
  text and dividers in the additional regular palettes. High contrast remains
  unchanged and opt-in, with focused AA text/control contrast tests.
- Preserved Overview, calendar layout, all themes and sunset switching. Settings
  now names the active palette and resolved mode. Browser origins and the frame
  store preferences independently; Ocean dark is blue, Linen dark is warm brown.
- 29 JavaScript tests and 9 Python tests pass; signed 2.6.1/version code 10 built,
  verified and installed in place over paired TLS ADB. All seven local tabs
  inspected on the 1920×1080 frame; Linen + Automatic retained and confirmed dark
  before sunrise. No household configuration, system settings or app data changed.
- Chrome screenshots refreshed for Linen overview/calendar/settings and Ocean
  dark using synthetic data only. Warm Linen dark also visually checked. Browser
  automation timed out during final preview preference cleanup; the frame's
  verified Linen/Automatic state is independent of that preview.
- Source/history/APK privacy checks pass. Public-release license and historical
  author-metadata limitations from 2.6 remain unchanged.

## Version 2.7 — Overview redesign

- Larger clock with separate AM/PM, full date, shared Weather landscape, current
  temperature/high/low and rain/wind/sunset. Removed redundant service shortcuts.
  Preserved the softer palette tokens, settings, Momo and current-date agenda.
- 29 JS and 9 Python tests pass. Signed version code 11 built and verified;
  source/history/APK privacy check passes.
- Inspected Chrome at 1280×720, 1920×1080 and 390×844; light, warm dark and Ocean dark,
  12/24-hour display and Weather/Calendar drill-downs checked. Refreshed both public
  overview screenshots using synthetic data. An initial preview load omitted Momo;
  reload rendered it normally, and the installed frame renders it correctly.
- Installed over paired TLS Wi-Fi with USB disconnected on the Android 12 frame.
  Overview and Weather render correctly at 1920×1080; real night forecast produces
  the moon artwork. Existing Linen/Automatic and household settings retained.
- The actual frame still has no household calendar feed configured. Populated
  overview events were visually checked only with the synthetic browser fixture.
  No system, account, router, firmware or launcher changes.

## Version 2.7.1 — Card-based overview

- Clock/date, weather and upcoming events now use matching cards; softer colour
  tokens, large clock, artwork and sidebar navigation preserved.
- 29 JS and 9 Python tests pass. Signed APK verified and installed in place over
  paired TLS Wi-Fi on the Android 12 frame; actual Overview inspected.
- Chrome inspected at 1280×720, 1920×1080 and 390×844. Five synthetic events fit
  without page overflow at frame resolution. Light and dark screenshots refreshed.
- Source/history/APK privacy and Gitleaks checks pass. No household, launcher,
  account or system settings changed; setup record updated privately.

## Version 2.7.2 — Overview spacing and agenda

- Compact clock/date card above the illustrated weather, with Upcoming beside both.
  Removed stretched weather whitespace, grouped event dates, enlarged supporting
  text and hid repeated single-calendar labels. Healthy refresh timestamps remain
  in detailed tabs; Overview retains stale/offline/missing-data warnings.
- 30 JS and 9 Python tests pass, including grouped dates and offline warning
  coverage. Signed APK version code 13 built and verified. Source/history/APK
  privacy scan and Gitleaks history scan pass.
- Light and Ocean dark previews checked at 1280×720 CSS pixels, plus desktop
  1920×1080 and narrow 390×844. Public overview screenshots use synthetic data.
  Calendar's populated layout inspected. As noted in 2.7, the first browser load
  omitted a module; reloading restored Momo and calendar. No such omission was
  seen on the installed frame.
- Installed in place on the Android 12 D156 frame over paired TLS wireless ADB.
  Overview and Calendar inspected at 1920×1080 physical resolution. Existing
  Linen/Automatic, household settings and app data retained; no system changes.
- No household calendar feed is connected; this pass does not claim live calendar
  synchronization. Private setup/restoration record updated on Mac and frame.


## Version 2.7.3 — Momo sidebar simplification

- Removed the hanger shortcut beside Momo. Clothing and daily wardrobe controls
  remain in Settings; tapping Momo still triggers his expressions.
- All 30 JS and 9 Python tests pass; signed APK and source/history/APK privacy
  checks pass. Inspected the sidebar across seven tabs in the synthetic preview,
  clothing selection, light/dark, frame-size, desktop and narrow layouts.
- Installed in place over explicitly selected USB on the Android 12 D156 frame.
  Calendar and Overview retain their settings; connected calendar data survives
  the upgrade. Public screenshots use synthetic fixtures only.
