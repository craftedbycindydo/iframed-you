# Local phone API

The frame runs a small HTTPS server on the home network so a paired phone can manage
chores, the shopping list, photos and frame setup. No cloud service is involved.
This file is the contract between the Android viewer, the dashboard and the iOS app.

## Discovery

- Bonjour/NSD service type `_skylit._tcp`, service name = frame name.
- Port `8765`; if taken, any free port. Clients must use the advertised port.
- TXT: `v=2`, `id=<frameId>`. Both are hints; identity is the certificate pin (see Transport security).
- The frame's IP changes on every reboot, so clients identify a frame by its pinned certificate,
  never by an address. A client may remember the last address it used as a hint to try when no
  advertised service matches the pin; the pin check still decides.

## Transport and errors

- HTTP/1.1 inside TLS 1.2 (never plain HTTP), JSON bodies, UTF-8. `Connection: close` on every
  response; one request per connection. Bodies need `Content-Length`; chunked bodies and requests
  carrying an `Origin` header are `400`. `Host` must be an IP address or a `.local` name.
- Request body limit 64 KiB, except `/v2/pair/*` (4 KiB) and photo upload (15 MiB). A body over
  its limit is `413` from the `Content-Length` alone, before any of it is read.
- Only `/v2/info` and `/v2/pair/*` are version 2 routes. Every other route keeps its `/v1/` path,
  is served only over this TLS listener and needs a token from a v2 pairing.
- The frame serves at most three requests from one address at a time and keeps at most twelve more
  from it waiting; further connections are closed without an answer, as is one that waits 15 s, takes
  more than 5 s to send its headers, or sends its body slower than 64 KiB/s after a 3 s start. One
  photo is received at a time; a second upload waits up to 20 s and is then `429`. A phone should use
  one connection at a time and retry a dropped one.
- Responses carry `Cache-Control: no-store`. `204` and `304` have no body.
- Errors: `{"error":{"code":"<slug>","message":"<text>"}}` with status
  400 `bad_request`, 401 `unauthorized`, 403 `forbidden`, 404 `not_found`, 409 `conflict` or
  `pairing_busy`, 410 `gone`, 413 `too_large`, 429 `rate_limited`, 500 `internal`.
  Clients branch on `code`, never on `message`.
- A change the frame cannot write to its storage (a full disk) is `500` `internal` and is not
  applied: the frame keeps showing, and serving, what it last saved. This covers people, chores,
  shopping, both settings and connecting an album. The request can be repeated later. A phone
  removing itself also gets `500`, but its token is refused from then until the frame restarts.
- Every authenticated request carries `Authorization: Bearer <token>`, where `<token>` is the 64
  lowercase hex characters of the phone's 32 raw token bytes. Anything else, including uppercase
  hex, is `401`. A route that does not exist is `401` without a valid token and `404` with one.

## Transport security (v2)

Everything below replaces the first version, which spoke plain HTTP and let a relay keep a token.

- The frame serves the API over TLS 1.2 only, on the same port, with suites
  `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256` and `TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384`.
  There is no plain-HTTP listener and no `/v1/pair/*`. Bonjour TXT carries `v=2`.
- Identity is one unit. On first run the frame creates a P-256 key and a self-signed certificate and
  keeps them for good. `fpRaw` is the 32 raw bytes of SHA-256 over the certificate's DER encoding;
  `fp` is its lowercase hex; `frameId` is the first 32 hex characters of `fp`. Key, certificate and
  the paired-device list are stored together: if the key or certificate cannot be loaded, the frame
  creates a new identity and erases the device list.
- Certificate shape: X.509 v3 with no extensions, a random positive 8-byte serial, issuer equal to
  subject (`CN=Skylit`), `notBefore` `200101000000Z`, `notAfter` `491231235959Z` (UTCTime), signed
  with `ecdsa-with-SHA256`. Neither side evaluates validity dates or the chain.
- A phone trusts only a pin. It keeps one connection pool per pinned frame; its trust callback
  accepts a server only if the leaf's `fp` equals the pin and otherwise cancels before any request
  bytes are sent. Unpinned `GET /v2/info` probes use a separate pool that never carries a token or a
  pairing session.
- TXT records and `/v2/info` are hints, not identity. For a paired frame the phone tries every
  service that advertises it and uses the one whose handshake matches the pin. A mismatch sends
  nothing and deletes nothing; the phone says another device on this Wi-Fi is claiming to be the
  frame.
- The phone speaks only HTTPS, never falls back, and deletes any token saved by the first version
  at launch. A frame updated from the first version erases its paired-device list.
- `GET /v2/info` (no token) returns `{"v":2,"frameId","name","pairing":true|false}`. `pairing` is
  `true` only while a pairing window is open and no phone has started in it yet.

## Pairing (v2)

Pairing proves the frame to the phone, and needs a tap on the frame that only the paired phone can
guide.

All hex on the wire is lowercase; receivers reject anything but `[0-9a-f]` of the exact length.
`nP`, `nF`, `commit` and `tokenHash` are 32 bytes (64 hex); `session` is 16 random bytes (32 hex).

1. On the frame, Settings → Phone app → **Pair a phone** opens a pairing window for 120 s, timed with
   a monotonic clock. Pairing calls are `409` at any other time.
2. The phone generates fresh random `nP` and a fresh random 32-byte `token`, and sends
   `POST /v2/pair/start`
   `{"commit":"<SHA-256 of nP>","tokenHash":"<SHA-256 of token>","deviceName":"Maya's iPhone"}` →
   `{"session","nF"}`. `tokenHash` is SHA-256 over the 32 raw token bytes (not over their hex
   text). `nF` is fresh per call. The first well-formed `start` after the window opens consumes
   the window whether or not it goes further; a malformed one (`400`) does not. While that session
   is still under way (waiting for `reveal`, or showing its code), every other `start` is `409`
   with code `pairing_busy`. With no window open — never opened, timed out, or its session
   already ended — `start` is `409` with code `conflict`. The phone records `fp` from this call's
   TLS handshake and every later pairing call must be on a connection with the same `fp`, checked
   before any bytes are sent.
3. `POST /v2/pair/reveal` `{"session","nP"}` → `204`, sent at most once. The frame checks
   `SHA-256(nP) == commit` (`400` and the session ends otherwise). A second `reveal`, a `reveal`
   for a session that has ended, or one for a session the frame does not know is `409`; after the
   window ran out it is `410`.
4. Both sides compute
   `D = HMAC-SHA256(key = nP ‖ nF (64 raw bytes), message = ASCII "skylit-pair-v2" (14 bytes) ‖ 0x00 ‖ fpRaw)`
   (47 message bytes), `code = u32be(D[0..3]) mod 1000000` printed as six digits with leading zeros,
   and `pick = u32be(D[4..7]) mod 100` printed as two digits. `u32be` is unsigned. The frame uses its
   own `fpRaw`; the phone uses the one from its handshake.
   Test vector: `nP` = `000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f`, `nF` = `202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f`, `fpRaw` = `404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f` gives `commit` = `630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd`, `D` = `526438df18ab2fc054b103a87964836abe6e20d4118d11b6a6e50ebbca57d7af`, `code` = `299871`, `pick` = `64`.
5. The frame shows the six-digit code, three two-digit buttons (`pick` and two different random
   decoys, shuffled) and Cancel, with: "Enter this code on your phone, then tap the number your
   phone shows." and, under Cancel, "No number on your phone? Tap Cancel."
6. The person types the code into the phone. The phone never displays its own value and allows three
   entries. On a match the pin becomes permanent and the phone shows "Tap NN on the frame". On three
   misses, or `409` `pairing_busy` at `start`, it shows "This phone did not pair. Another device
   may be trying. Tap Cancel on the frame; do not tap a number." and calls
   `POST /v2/pair/cancel` `{"session"}` (`204`, also when repeated; `409` for a session the frame
   does not know). A plain timeout is not that case: `409` `conflict` at `start` means no window is
   open ("On the frame, tap Pair a phone, then try again"), and `410` from `reveal` or `result`
   means the two minutes ran out; neither should be presented as another device interfering.
7. Tapping `pick` on the frame approves the session and stores `tokenHash` as a paired device. A
   decoy, Cancel, `cancel` or expiry ends it.
8. The phone polls `GET /v2/pair/result?session=<hex>`: `202` while waiting, `200`
   `{"deviceId","frameId","name"}` after approval, `403` after a decoy, Cancel on either side or a
   wrong `nP`, `410` after expiry, `404` for a session the frame does not know (never started,
   replaced by a newer window, or lost when the frame restarted) and `400` for a `session` that is
   not 32 lowercase hex characters. An outcome stays readable until the next window opens. The
   token never travels: the phone already holds it. The phone rejects a result whose `frameId` is
   not the first 32 hex characters of its pinned `fp`.

The phone never restarts pairing by itself; a new attempt needs the person to ask and the frame to
open a new window. There is no lock-out: each attempt already needs someone at the frame.

Device names are 1–40 characters after trimming, with at least one visible character and with
control and direction-override characters refused, and are shown as plain text. They are chosen by the device, so the frame never treats a
name as proof of anything.

What this gives: a device in the middle makes the phone and the frame compute different codes
except by a one-in-a-million chance per window, and a device that starts its own session leaves the
person with nothing to tap, because only the phone that typed the right code can name the number.
It does not protect against someone who can read the frame's screen and touch it.

## Devices

| Call | Auth | Result |
| --- | --- | --- |
| `GET /v1/devices` | token | `[{"id","name","pairedAt":"ISO-8601"|null,"lastSeen":"ISO-8601"|null,"self":true|false}]` |
| `DELETE /v1/devices/{id}` | token | `204` only for the caller's own device; `403` otherwise |

- The frame stores only `tokenHash`. Tokens do not expire; `lastSeen` is recorded at most once a day
  per device so the owner can spot and remove stale ones.
- A phone paired while the frame's clock is not set (before 2026) has `pairedAt` and `lastSeen`
  `null`; both are filled in at its first request after the clock is right. The frame's list
  shows no date until then.
- A stored device row that cannot be read is dropped by itself; the other phones stay paired.
- The frame's Settings list shows each device with its paired and last-seen dates and can remove any
  device or all of them.
- Up to 20 devices can be paired, each with its own token; with 20 paired the frame will not open
  a window. Pairing again with a `tokenHash` that is already paired replaces the earlier entry, so
  a token is never listed twice and removing the device always revokes it.

## State

`GET /v1/state` (token) returns everything the phone renders:

```json
{
  "rev": 42,
  "people": [{"id":"p1","name":"Maya","color":"#00A36C"}],
  "chores": [{"id":"c1","title":"Make bed","emoji":"🛏️","personId":"p1","days":[1,2,3,4,5],"done":["2026-10-11"]}],
  "shopping": [{"id":"s1","name":"Milk","qty":2,"note":"","done":false}],
  "settings": {
    "location": {"name":"Denver","latitude":39.74,"longitude":-104.99,"timezone":"America/Denver"},
    "appearance": {"palette":"linen","mode":"auto"},
    "icloudAlbum": null
  },
  "calendars": [{"id":"k1","name":"Family","color":"#2D5BFF"}],
  "photos": {"count": 12}
}
```

- `rev` increases by one on every change, from any source, and survives a restart. A picture or
  calendar that arrived while no phone was asking counts at the next request, also when the frame
  restarted in between. A request
  that changes nothing (a `PATCH` with the same values, `clear-done` with nothing ticked) returns
  the current `rev` unchanged. `GET /v1/state?since=42` returns `304` when `rev` is still 42 and
  the full state otherwise; `since` must be digits (`400` if not).
- `personId` is `null` for a chore anyone can do. `days` uses 0 = Sunday … 6 = Saturday;
  an empty list means every day. `done` holds local dates (`YYYY-MM-DD`, frame timezone);
  the frame keeps the last 14 days. `PUT …/done` accepts dates from 13 days ago to tomorrow in the
  frame's timezone (the chosen city's zone, else the device's) and `400`s anything else.
- `settings.location` is `null` until a city is chosen, and its `timezone` is `null` when the city
  was set without one. `settings.icloudAlbum` is described under iCloud shared album. Calendar feed
  URLs are never returned.
- Dropping chore dates older than 14 days does not change `rev`.

## Mutations

All need a token and return `{"rev":N}` plus the created or changed object under its
own key (`person`, `chore`, `item`, `calendar`, `photo`) where one exists.

| Call | Body |
| --- | --- |
| `POST /v1/people` | `{"name","color"}` |
| `PATCH /v1/people/{id}` | any of `name`, `color` |
| `DELETE /v1/people/{id}` | Chores assigned to that person become unassigned. |
| `POST /v1/chores` | `{"title","emoji"?,"personId"?,"days"?}` |
| `PATCH /v1/chores/{id}` | any of `title`, `emoji`, `personId`, `days` |
| `DELETE /v1/chores/{id}` | |
| `PUT /v1/chores/{id}/done` | `{"date":"YYYY-MM-DD","done":true\|false}` |
| `POST /v1/shopping` | `{"name","qty"?,"note"?}` |
| `PATCH /v1/shopping/{id}` | any of `name`, `qty`, `note`, `done` |
| `DELETE /v1/shopping/{id}` | |
| `POST /v1/shopping/clear-done` | Removes every ticked item. |
| `PUT /v1/settings/location` | `{"name","latitude","longitude","timezone"?}` |
| `PUT /v1/settings/appearance` | `{"palette","mode"}`; values are those `web/appearance.js` accepts. |
| `POST /v1/calendars` | `{"name","color","url"}`; `url` is a Google Calendar secret iCal address, as on the frame. |
| `DELETE /v1/calendars/{id}` | |

Limits: 12 people, 100 chores, 200 shopping items, 6 calendars; names and titles
1–80 characters after trimming; `emoji` 0–16; `note` 0–200; `qty` a whole number 1–99; colours
`#RRGGBB`; `days` whole numbers 0–6. Lengths count Unicode code points, and trimming removes
every kind of leading and trailing white space (including no-break and ideographic spaces), as
JavaScript's `trim()` does. Control characters and direction overrides are refused. A name or
title needs at least one visible character: one made only of zero-width or other invisible
characters is refused, while joined emoji and a zero-width non-joiner inside a word are fine.
A calendar name is 1–60 characters and, unlike the others, an emoji counts as two. Violations
are `400`; an unknown `id` is `404`; a calendar feed that is already on the frame is `409`.
Unknown fields are ignored, and a body `id` never overrides the one in the path.

## Photos

| Call | Notes |
| --- | --- |
| `GET /v1/photos` | `[{"id":"<64 hex>","addedAt":"ISO-8601"}]`, newest first |
| `POST /v1/photos` | Body is one JPEG, `Content-Type: image/jpeg`, 4 KiB to 15 MiB and at least 320×240 pixels; anything else is `400`. Returns `{"rev","photo":{"id","addedAt"}}`. `id` is the SHA-256 of the uploaded bytes, so the same bytes uploaded twice return the existing photo. |
| `GET /v1/photos/{id}` | The stored JPEG. The frame resizes and re-encodes what it keeps, so these are not the uploaded bytes. |
| `DELETE /v1/photos/{id}` | `204` |

Uploaded photos join the frame's local picture library and its slideshow. The list holds every
picture in that library that is not hidden on the frame: phone, email and album pictures alike.
The library keeps the newest pictures up to its limit (30 by default, 50 at most), so an upload
can push the oldest one out.

## iCloud shared album

The frame can mirror one public iCloud Shared Album (an album with "Public Website" on).
The frame downloads from Apple itself; no phone needs to stay online and no Apple ID is used.
This relies on the unofficial `sharedstreams` web endpoints Apple's own album page calls.

| Call | Body | Result |
| --- | --- | --- |
| `PUT /v1/settings/icloud-album` | `{"url":"https://www.icloud.com/sharedalbum/#<token>"}` | `{"rev":N}`; a first sync starts |
| `DELETE /v1/settings/icloud-album` | | `{"rev":N}`; album pictures are removed, phone and email pictures stay |
| `POST /v1/settings/icloud-album/sync` | | `204`; starts a sync now |
| `GET /v1/settings/thermostat-account` | | `{"email","password"}`, or `404` when the frame has no thermostat account |
| `PUT /v1/settings/thermostat-account` | `{"email","password"}` | `204`; the frame starts signing in. `409` when it cannot start |

- Only `https://www.icloud.com/sharedalbum/#<token>` links are accepted (an optional locale
  segment such as `/sharedalbum/en-gb/` is allowed); anything else, including
  `https://share.icloud.com/photos/…` links, is `400` with an explanatory message. The link is a credential: it is stored
  privately on the frame and never returned, logged or shown again.
- `GET /v1/state` gains `settings.icloudAlbum`: `null`, or
  `{"name":"Family","count":24,"lastSync":"ISO-8601"|null,"syncing":false,"error":null|"<text>"}`.
- The frame syncs on connect, on start, and every 30 minutes; after a failed sync it waits longer
  each time, up to six hours, and tries at once when Wi-Fi returns. It keeps the newest pictures up
  to the library limit, removes pictures deleted from the album, and skips videos.
- If the saved album record cannot be read at start, the frame has no album and removes the
  album's pictures, as `DELETE` would; phone and email pictures stay.
- A sync, a status change or an error each bump `rev` once. `PUT` returns before the first
  sync finishes; `name` is `""` until it has. `DELETE` with no album is `200`; `sync` with no
  album is `409`.

Bridge additions: dashboard → native `icloudStatus()` (the object above or `null`),
`icloudConnect(url)` → `{"ok":true}` or `{"ok":false,"error":"…"}`, `icloudDisconnect()` → boolean,
`icloudSync()`; native → dashboard `SkylitICloud.receive(status)`, plus the existing
`SkylitPhotos.receive(status)` whenever pictures change.

## Dashboard bridge

The dashboard never talks HTTP to the server; it uses the WebView bridge.

Native → dashboard (via `evaluateJavascript`, each guarded with `window.X&&`):

- `SkylitHousehold.receive(snapshot)`: `{rev,people,chores,shopping}` after any change.
- `SkylitPairing.update(state)` whenever pairing changes. `state` is one of
  `{"phase":"idle"}`, `{"phase":"waiting","remaining":<ms>}`,
  `{"phase":"code","remaining":<ms>,"code":"299871","numbers":["07","64","91"]}`,
  `{"phase":"paired","name":"<device name>"}` or
  `{"phase":"cancelled","reason":"decoy"|"frame"|"phone"|"refused"|"expired"|"storage"}`.
  The dashboard titles `expired` "Pairing timed out" ("No phone was paired. Open Pair a phone to
  try again.") and every other reason "Pairing cancelled"; only `refused` (a wrong `nP`) mentions
  that another device may be interfering. `storage` means the right number was tapped but the
  frame could not save the phone; the phone's `result` is `403` and its token does not work. The paired, timed-out and cancelled screens close
  themselves after about six seconds by calling `pairingCancel()`, and the outcome stays as one
  line in Settings → Phone app.
  `remaining` is milliseconds left on the frame's monotonic clock; the dashboard only draws the
  countdown. `numbers` never says which entry is `pick`.
- `SkylitRemote.apply({location?,appearance?})`: a phone changed a setting that lives in
  dashboard `localStorage`. The dashboard applies it and then calls `reportSettings`.
- `SkylitCalendar.receive(...)` and `SkylitPhotos.receive(...)` as today, when the phone
  adds a calendar or photo. A calendar removed from a phone arrives as
  `SkylitCalendar.receive({"id","removed":true,"error":"…"})`.

Dashboard → native (`window.Skylit.*`, all return a JSON string or boolean):

- `householdSnapshot()` → the snapshot above.
- `householdMutate(json)` → `{"ok":true,"snapshot":{…}}` or `{"ok":false,"error":"…"}`. A change
  that cannot be saved is `ok:false` and is not applied; the dashboard shows `error` as a notice.
  `json` is `{"op":"<name>", …fields}` with ops `person.add`, `person.update`,
  `person.remove`, `chore.add`, `chore.update`, `chore.remove`, `chore.done`,
  `item.add`, `item.update`, `item.remove`, `items.clearDone`. Fields match the HTTP bodies,
  plus `id` for update/remove/done.
- `reportSettings(json)`: `{"location":{…}|null,"appearance":{…}}`, called at startup and
  whenever either changes, so `GET /v1/state` can serve them.
- `pairingStatus()` →
  `{"devices":[{"id","name","pairedAt","lastSeen"}],"port":8765,"advertised":true,"address":"192.168.0.12","pairing":{…state above}}`.
  `address` is the frame's private IPv4 address, or `""` when it has none.
- `pairingOpen()` → `{"ok":true,"pairing":{…}}` after opening a 120 s window, or
  `{"ok":false,"error":"…"}` when 20 devices are already paired.
- `pairingTap(number)` → `true` when `number` was `pick` and the device is now paired; anything else
  while a code is shown ends the session and returns `false`.
- `pairingCancel()` → boolean. Cancels an open window or session; on the success or cancelled
  screen it returns pairing to `idle`.
- `pairingRevoke(id)` and `pairingRevokeAll()` → boolean. `false` also when the removal could not be
  saved: the phone is refused until the frame restarts, and the dashboard says it could not remove it.

Thermostats (Honeywell Total Connect Comfort) are reached only through the bridge. The frame's
native code signs in and polls. The phone API carries only the account hand-over
(`/v1/settings/thermostat-account`): a paired phone gives its sign-in to a frame that has none, or
takes the frame's when the phone has none. Any paired device can therefore read the account.

- Native → dashboard: `SkylitThermostat.receive(snapshot)` on every change. `snapshot` is
  `{"configured","status","controllable","polledAt","retryAt","units","outdoor","account","message","signIn","thermostats":[…]}`.
  `status` is `unconfigured`, `loading`, `ok`, `stale`, `unavailable`, `locked_out` or `signed_out`;
  `message` is a plain sentence for it or `null`. `signIn` is `null`, `{"pending":true}` or
  `{"ok":false,"code","error":"<plain sentence>","retryAt":"ISO-8601"|null}`. Each thermostat is
  `{"id":"t1","name","online","units","indoor","humidity","mode","heatAllowed","coolAllowed","setpoint","changing","error","message","heatSetpoint","coolSetpoint","range":{"min","max"}|null,"step","hold":"schedule"|"temporary"|"permanent"|null,"holdUntil":"HH:MM"|null,"running","fan","fanRunning"}`.
  Honeywell's own ids, the password and the session cookie never appear.
- `thermostatSnapshot()` → the snapshot above as a JSON string.
- `thermostatSignIn(email, password)` → `{"ok":true,"pending":true}` at once, or
  `{"ok":false,"error":"…"}` when the fields are unusable or a sign-in is already running. The
  network work runs on a worker thread; the outcome arrives through `receive` in `signIn`. A
  sign-in that fails while an account is already working leaves that account, its saved
  credential and its session untouched.
- `thermostatSignOut()` → boolean; erases the stored account and its key.
- `thermostatStep(id, delta)` → `{"ok":true,"setpoint":N}` or `{"ok":false,"error":"…"}`. One
  step per call in the direction of `delta`, kept inside the thermostat's own range; taps within a
  second are sent to Honeywell as one change. A thermostat following its schedule gets a temporary
  hold until its next schedule period; one already on a temporary or permanent hold keeps that
  hold and its end time. Which of the two it is comes from the hold status of the mode that is
  running (heat or cool) only, and a thermostat that reports no status counts as following its
  schedule. While such a change is pending the snapshot already reports
  `hold:"temporary"` and `holdUntil`, so the tile does not claim to follow the schedule.
- `thermostatMode(id, "heat"|"cool")` and `thermostatResume(id)` → `true` when started; the result
  arrives through `receive` (`changing`, then the new state or `error` and `message`).
- `thermostatWatch(visible)`: poll every 60 s while the Overview is showing, every 5 min otherwise.
  The dashboard calls it on every tab change and once at load when it starts on the Overview. The
  frame itself drops to the 5 min pace while the dashboard is covered by the slideshow, the quiet
  clock or another site, or is in the background.
- Times in the snapshot follow the frame's clock, but polling, staleness and the lock-out are
  counted in elapsed time, so setting the clock (as happens shortly after a start) neither delays
  nor repeats a poll, and `retryAt` and `polledAt` are moved to match the new clock.

The bridge calls Skylit already had are unchanged and are not part of the phone contract:
`calendarList`, `calendarAdd`, `calendarMetadata`, `calendarRemove`, `calendarRefresh`,
`calendarAccept`; `photoStatus`, `photoConnect`, `photoConfigure`, `photoExclude`,
`photoRestoreExcluded`, `photoDelivery`, `photoDeliverySettings`, `photoEraseCache`,
`photoRefresh`, `photoOpen`, `photoBrowse`, `photoDisconnect`, `photoSource`, `localPhotoClosed`;
`configure`, `configureQuiet`, `privacyPause`, `ambientClosed`; `openPhotos`, `openHome`,
`openYouTube`, `openYouTubeLink`, `openCalendar`, `openWifiSettings`, `openDeveloperSettings`,
`openStock`.

Chores and shopping have one source of truth: the native household store. The dashboard's
old `skylit.household` shopping list is migrated into it once, then no longer written.
