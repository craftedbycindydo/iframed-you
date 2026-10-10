# Working on Skylit

Read README.md, docs/architecture.md, docs/credits.md and docs/verification.md first.
This is an Android frame dashboard with a plain HTML/CSS/JS front end. Do not migrate
frameworks or add a backend just to change a screen. Target Chromium/WebView 95 and
Android 12. Keep touch targets generous and preserve the warm themes and Momo.

## Setup

- Work in the repository root. Preview with Python’s localhost HTTP server; see README.
- Node 18+ runs the built-in JS tests. Python 3.10+ runs build/privacy/ADB tools.
- Android builds need the private `.local/build.json`, JDK 17, SDK platform/build-tools 34.
- Read [wireless setup](docs/wireless.md) for first USB-to-Wi-Fi pairing and later
  reconnection. Verify with scripts/frame.py after USB is unplugged; pairing alone
  is not proof of a working wireless connection. Preserve normal authorization expiry.
- Missing personal configuration is normal; do not invent household credentials.
- Do not print `.local/` files, tokens, shared-album links or account cookies.

## Calendar setup direction

Read [calendar setup](docs/calendar.md) before configuring or changing Calendar.
The agreed integration is a themed, read-only calendar fetched directly from private
iCal feeds on the frame. Easy household setup and no maintained hosted service are
requirements. Do not introduce hosted OAuth, require a Google developer project,
make calendars public, or install Google Play services for this integration.

Guide the owner through Google Calendar's **Settings → calendar → Integrate calendar
→ Secret address in iCal format** on their computer. Treat each URL as a credential:
enter it through Calendar → Manage calendars on the frame, never chat, tracked
files, screenshots, logs, setup records or distributable APKs. Do not reuse the
legacy Calendar website URL configuration for a feed. Verify actual event refresh before claiming that a household calendar is connected.
Record calendar labels, verification results and removal steps without secret URLs
or event details. The full procedure and verification criteria are in the guide.

## Email photo setup direction

Read [photo setup](docs/photos.md) before changing mail import or asking the owner
to connect it. The owner enters the dedicated Gmail account and its app password
on the frame, after enabling Google 2-Step Verification. Never ask for or print
the app password. A stored credential is not a verified connection: confirm a
real imported picture, slide advance, offline cache and idle return on the frame.
Keep the shared-album source working. Retain bounded private storage, direct TLS
IMAP, the local-only bridge and an immediate erase/revoke path. Do not embed
household mail identifiers or pictures in source, screenshots or a normal APK.

## Changes and verification

- Run `node --test tests/*.test.cjs` and `python3 -m unittest discover -s tests`.
- Run `python3 scripts/check_public.py --history`; scan with Gitleaks before publication.
- For Android changes, build, verify the APK and test the actual frame when available.
- Inspect every affected tab at the frame’s 1920×1080 resolution and desktop preview.
- For a new install, verify the first-run guide opens; for an upgrade, verify it does
  not interrupt existing settings. Reopen it from Settings and follow its direct
  links. The guide must never prefill or reveal household credentials.
- Distinguish a loaded website, successful sign-in and verified functionality. Never
  claim playback, calendar sync or home control based solely on a rendered shortcut.
- Add focused tests for behavior and privacy boundaries; avoid snapshotting private data.
- Preserve device settings, installed-app data and the signing key during upgrades.

## Hardware boundaries

Identify the exact model, Android version and transport before deployment. Use paired
TLS wireless ADB or an explicitly selected USB device. The helper verifies serials.
Do not flash, root, unlock, factory-reset, disable system apps, change router settings,
weaken authentication, or enable unauthenticated port 5555 for app-only work.
Any separate firmware task needs device-specific research, backup/recovery preparation
and authorization for that task. Never reuse another model’s image or partition map.

Record actual device changes and undo steps in the private local setup record and
its copy in the frame’s Downloads folder. Never commit those household records.
Keep the original launcher installed and record HOME before replacing it.

## External services and releases

Only the local asset WebView gets the native bridge. Never inject it into remote
content, transfer browser cookies, spoof account authentication, or commit OAuth tokens.
Use exact HTTPS host allowlists. Let the owner sign in on the device.

Normal builds must have empty household configuration. A `--personal` APK is private,
even though its source config is ignored. Inspect Git history and the final APK;
.gitignore alone is insufficient. Do not publish screenshots showing family photos,
events, addresses or account identities. Preserve Wes’s attribution and third-party
notices in docs/credits.md. The owner has removed the previous license-clarification
release gate; do not reintroduce it. Follow docs/releasing.md for publication checks.

## Appearance, overview and public previews

- Read docs/design.md and docs/testing.md for UI changes. Appearance decisions belong
  in web/appearance.js; keep six light/dark pairs and their contrast tests aligned.
- Automatic means astronomical sunrise/sunset at the configured city, computed
  offline. Do not add location permissions, a server or weather API dependence.
- Overview events must remain anchored to today when the user browses other months.
  Add regression coverage for async worker races, removal and stale data handling.
- Use `python3 scripts/preview.py` for public screenshots. It stages allowlisted
  assets and synthetic fixtures, never web/local-config.js. Real frame screenshots
  stay private. Never add the demo fixture to PUBLIC_ASSETS or distributable APKs.
- Review at 1280×720 CSS pixels (the frame's 1920×1080 physical screen), desktop and
  a narrow viewport. Use clear labels/status, not slogans or invented service data.
