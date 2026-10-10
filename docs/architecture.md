# Architecture

`web/` contains the offline-first dashboard and canvas companion. Settings are saved
under `skylit.settings` in localStorage; Momo maintains its own preferences. A fresh
install has no city, album, household identifier, calendar ID or account baked in.
The clock uses the device timezone until a city is selected.

`android/` serves reviewed bundled assets from a virtual HTTPS origin. Only that
local, navigation-restricted WebView receives the small `Skylit` JavaScript bridge.
Google Photos, Home and YouTube open in a separate full-screen WebView
without the bridge. Remote top-level navigation uses exact HTTPS host allowlists.
Third-party sites still load their own subresources. Remote pages share WebView’s
cookie store, but no login tokens are read or transferred by the dashboard.

The native viewer owns the idle timer. It is suspended while an external service is
open. Photo idle mode returns on the first touch; manually opened services have a
persistent return button, including full-screen video. Momo stops animation while
hidden or covered. Android backup is disabled; remote debugging is opt-in per launch.

`build.py` uses JDK 17, aapt2, javac, d8, zipalign and apksigner without Gradle.
`assets.py` copies a fixed asset allowlist. Ordinary builds always overwrite local
config with an empty object; only explicit personal builds embed it. Signing keys,
SDKs, frame connection settings, logs and screenshots stay under ignored `.local/`.

No server receives your photo links or account credentials. Weather queries go to
Open-Meteo with your selected coordinates; each opened website receives its normal
web requests. External integrations depend on those services’ current compatibility.
Google Photos slideshow automation uses visible menu labels and may need maintenance.

## Calendar feeds

Calendar uses Skylit's own HTML/CSS month and agenda interface. `calendar-model.js`
uses the pinned ICAL.js parser in a worker, with bounded expansion and a time limit.
The worker resolves supplied VTIMEZONE data and recurrence exceptions. Calendar text
is rendered using textContent; feed content never becomes executable HTML.

`CalendarStore` keeps URLs and last-good ICS data in private Android SharedPreferences
(separate from dashboard localStorage, and excluded from Android backups). Its bridge
snapshots omit feed URLs. `CalendarFeed` downloads only the supported Google HTTPS
feed paths, with no redirects or browser-session transfer. Network failures retain
cached events. Successful downloads are staged until worker parsing succeeds; only
then does the native store replace its cache. Request IDs prevent deleted calendars
or responses from a previous renderer from restoring obsolete data.

No server or Google OAuth project is involved. The frame refreshes every 15 minutes
while the dashboard runs, retries failed/stale feeds on its minute timer, and refreshes
on startup or reconnection. Private setup is performed on the frame. Desktop browser
previews have no native feed bridge and cannot save calendar credentials.

The optional organizer rule is a local display policy. `calendar-model.js` retains
normalized organizer addresses, including on recurrence exceptions; `calendar-policy.js`
filters both visible-month events and the separately anchored Overview expansion.
The full parsed events remain in memory so approving an address restores them
without another download, while feed removal clears both full event lists.
Approved addresses and the owner's address live in the dashboard's localStorage;
ICS URLs remain in native private storage. The rule cannot make an invitation appear
if Google's account setting omitted it from the feed.

## Email photo cache (2.8)

`PhotoMail` connects to Gmail's TLS IMAP endpoint in read-only mode using a Google
app password entered on the frame. The password is sealed with an Android Keystore
AES-GCM key and bound to the account address. It never reaches web assets or the
remote service WebViews. `PhotoPolicy` centralizes limits; `PhotoStore` keeps only
deduplicated, resized JPEGs in app-private storage and deletes expired/excess files.
Successful checks set a last-checked time, and failures retain usable pictures.
The Android viewer intercepts only exact local HTTPS photo paths for the local
dashboard; remote web content gets neither private photos nor the bridge.

The Photos UI selects either the existing Google Photos website or Skylit's local
slideshow. Manual playback has controls; idle playback hides them and returns on
first touch. The source, speed and review presentation live locally; secrets stay
out of browser localStorage. No backend, Android account provider, Play services or
email body cache is involved. The importer is bounded to recent inbox messages,
and its app-password scope is broader than photo-only access; a dedicated account
keeps that exposure narrow. See [photo setup](photos.md) and [verification](verification.md).

## Appearance and overview (2.6)

`appearance.js` owns paired theme tokens, legacy preference migration, and solar
mode decisions. SunCalc 1.9.0 runs locally: solar altitude below -0.833° is night.
The next sunrise/sunset label uses predicted times, formatted in the selected city
zone. The clock checks every 15 seconds and on visibility/remote return. Manual
Light/Dark overrides the sun; invalid/missing coordinates follow system appearance.
Polar night/day works without inventing a sunrise. This changes dashboard colours,
not panel brightness or third-party websites. Legacy Cocoa becomes Linen + Dark;
other old themes default to Automatic. Device time must be correct.

The default Overview consumes the same forecast/cache as Weather. Its read-only
calendar summary uses a separate bounded current-date expansion when the visible
calendar month is outside today's two weeks. Generation IDs discard stale worker
completions. Removing a feed immediately removes its overview events. The overview reuses the
Weather page’s day/night landscape and forecast, without another network request.
Clock numerals and day period are formatted separately from the selected timezone
and 12/24-hour preference. Service navigation stays in the sidebar.

`overview-model.js` holds event selection and weather freshness decisions. Preview
fixtures remain outside the APK allowlist. `scripts/preview.py` serves a disposable
public-asset copy on loopback with cache disabled; it never stages personal config.
