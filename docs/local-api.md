# Local phone API

The frame runs a small HTTP server on the home network so a paired phone can manage
chores, the shopping list, photos and frame setup. No cloud service is involved.
This file is the contract between the Android viewer, the dashboard and the iOS app.

## Discovery

- Bonjour/NSD service type `_skylit._tcp`, service name = frame name.
- Port `8765`; if taken, any free port. Clients must use the advertised port.
- TXT: `v=1`, `id=<frameId>`.
- The frame's IP changes on every reboot, so clients store `frameId`, never an address.

## Transport and errors

- HTTP/1.1, JSON bodies, UTF-8. `Connection: close` on every response.
- Request body limit 64 KiB, except photo upload (15 MiB).
- Errors: `{"error":{"code":"<slug>","message":"<text>"}}` with status
  400 `bad_request`, 401 `unauthorized`, 404 `not_found`, 409 `conflict`,
  413 `too_large`, 429 `rate_limited`.
- Every authenticated request carries `Authorization: Bearer <token>`.

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
- `GET /v2/info` (no token) returns `{"v":2,"frameId","name","pairing":true|false}`.

## Pairing (v2)

Pairing proves the frame to the phone, and needs a tap on the frame that only the paired phone can
guide.

All hex on the wire is lowercase; receivers reject anything but `[0-9a-f]` of the exact length.
`nP`, `nF`, `commit` and `tokenHash` are 32 bytes (64 hex); `session` is 16 random bytes (32 hex).

1. On the frame, Settings → Phone app → **Pair a phone** opens a pairing window for 120 s, timed with
   a monotonic clock. Pairing calls are `409` at any other time.
2. The phone generates fresh random `nP` and a fresh random 32-byte `token`, and sends
   `POST /v2/pair/start`
   `{"commit":"<SHA-256 of nP>","tokenHash":"<SHA-256 of token>","deviceName":"Karan's iPhone"}` →
   `{"session","nF"}`. `nF` is fresh per call. The first `start` after the window opens consumes
   the window whether or not it goes further; every later `start` is `409` with code `pairing_busy`
   until the person opens a new window. The phone records `fp` from this call's TLS handshake and
   every later pairing call must be on a connection with the same `fp`, checked before any bytes
   are sent.
3. `POST /v2/pair/reveal` `{"session","nP"}` → `204`, sent at most once. The frame checks
   `SHA-256(nP) == commit` (`400` and the session ends otherwise).
4. Both sides compute
   `D = HMAC-SHA256(key = nP ‖ nF (64 raw bytes), message = ASCII "skylit-pair-v2" (14 bytes) ‖ 0x00 ‖ fpRaw)`
   (47 message bytes), `code = u32be(D[0..3]) mod 1000000` printed as six digits with leading zeros,
   and `pick = u32be(D[4..7]) mod 100` printed as two digits. `u32be` is unsigned. The frame uses its
   own `fpRaw`; the phone uses the one from its handshake.
   Test vector: `nP` = `000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f`, `nF` = `202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f`, `fpRaw` = `404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f` gives `commit` = `630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd`, `D` = `526438df18ab2fc054b103a87964836abe6e20d4118d11b6a6e50ebbca57d7af`, `code` = `299871`, `pick` = `64`.
5. The frame shows the six-digit code, three two-digit buttons (`pick` and two different random
   decoys, shuffled) and Cancel, with: "Type this code into your phone. Your phone will then show a
   number. Tap that number here. If your phone shows no number, tap Cancel."
6. The person types the code into the phone. The phone never displays its own value and allows three
   entries. On a match the pin becomes permanent and the phone shows "Tap NN on the frame". On three
   misses, or a `409` at `start`, it shows "This phone did not pair. Another device may be trying.
   Tap Cancel on the frame; do not tap a number." and calls `POST /v2/pair/cancel` `{"session"}`.
7. Tapping `pick` on the frame approves the session and stores `tokenHash` as a paired device. A
   decoy, Cancel, `cancel` or expiry ends it.
8. The phone polls `GET /v2/pair/result?session=<hex>`: `202` while waiting, `200`
   `{"deviceId","frameId","name"}` after approval, `403` after a decoy or Cancel, `410` after
   expiry. The token never travels: the phone already holds it. The phone rejects a result whose
   `frameId` is not the first 32 hex characters of its pinned `fp`.

The phone never restarts pairing by itself; a new attempt needs the person to ask and the frame to
open a new window. There is no lock-out: each attempt already needs someone at the frame.

Device names are 1–40 characters after trimming, with control and direction-override characters
refused, and are shown as plain text. They are chosen by the device, so the frame never treats a
name as proof of anything.

What this gives: a device in the middle makes the phone and the frame compute different codes
except by a one-in-a-million chance per window, and a device that starts its own session leaves the
person with nothing to tap, because only the phone that typed the right code can name the number.
It does not protect against someone who can read the frame's screen and touch it.

## Devices

| Call | Auth | Result |
| --- | --- | --- |
| `GET /v1/devices` | token | `[{"id","name","pairedAt","lastSeen","self":true|false}]` |
| `DELETE /v1/devices/{id}` | token | `204` only for the caller's own device; `403` otherwise |

- The frame stores only `tokenHash`. Tokens do not expire; `lastSeen` is recorded at most once a day
  per device so the owner can spot and remove stale ones.
- The frame's Settings list shows each device with its paired and last-seen dates and can remove any
  device or all of them.
- Up to 20 devices can be paired, each with its own token.

## State

`GET /v1/state` (token) returns everything the phone renders:

```json
{
  "rev": 42,
  "people": [{"id":"p1","name":"Maya","color":"#00A36C"}],
  "chores": [{"id":"c1","title":"Make bed","emoji":"🛏️","personId":"p1","days":[1,2,3,4,5],"done":["2026-10-11"]}],
  "shopping": [{"id":"s1","name":"Milk","qty":2,"note":"","done":false}],
  "settings": {
    "location": {"name":"Calgary","latitude":51.05,"longitude":-114.07,"timezone":"America/Edmonton"},
    "appearance": {"palette":"linen","mode":"auto"}
  },
  "calendars": [{"id":"k1","name":"Family","color":"#2D5BFF"}],
  "photos": {"count": 12}
}
```

- `rev` increases by one on every change, from any source. `GET /v1/state?since=42`
  returns `304` when `rev` is still 42.
- `personId` is `null` for a chore anyone can do. `days` uses 0 = Sunday … 6 = Saturday;
  an empty list means every day. `done` holds local dates (`YYYY-MM-DD`, frame timezone);
  the frame keeps the last 14 days.
- `settings.location` is `null` until a city is chosen. Calendar feed URLs are never returned.

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
| `PUT /v1/chores/{id}/done` | `{"date":"YYYY-MM-DD","done":true}` |
| `POST /v1/shopping` | `{"name","qty"?,"note"?}` |
| `PATCH /v1/shopping/{id}` | any of `name`, `qty`, `note`, `done` |
| `DELETE /v1/shopping/{id}` | |
| `POST /v1/shopping/clear-done` | Removes every ticked item. |
| `PUT /v1/settings/location` | `{"name","latitude","longitude","timezone"?}` |
| `PUT /v1/settings/appearance` | `{"palette","mode"}`; values are those `web/appearance.js` accepts. |
| `POST /v1/calendars` | `{"name","color","url"}`; same validation as on-frame entry. |
| `DELETE /v1/calendars/{id}` | |

Limits: 12 people, 100 chores, 200 shopping items, 6 calendars; names and titles
1–80 characters after trimming; `qty` 1–99; colours `#RRGGBB`. Violations are `400`.

## Photos

| Call | Notes |
| --- | --- |
| `GET /v1/photos` | `[{"id":"<64 hex>","addedAt":"ISO-8601"}]`, newest first |
| `POST /v1/photos` | Body is one JPEG, `Content-Type: image/jpeg`. Returns `{"rev","photo":{"id","addedAt"}}`. The same bytes uploaded twice return the existing photo. |
| `GET /v1/photos/{id}` | The stored JPEG |
| `DELETE /v1/photos/{id}` | `204` |

Uploaded photos join the frame's local picture library and its slideshow.

## iCloud shared album

The frame can mirror one public iCloud Shared Album (an album with "Public Website" on).
The frame downloads from Apple itself; no phone needs to stay online and no Apple ID is used.
This relies on the unofficial `sharedstreams` web endpoints Apple's own album page calls.

| Call | Body | Result |
| --- | --- | --- |
| `PUT /v1/settings/icloud-album` | `{"url":"https://www.icloud.com/sharedalbum/#<token>"}` | `{"rev":N}`; a first sync starts |
| `DELETE /v1/settings/icloud-album` | | `{"rev":N}`; album pictures are removed, phone and email pictures stay |
| `POST /v1/settings/icloud-album/sync` | | `204`; starts a sync now |

- Only `https://www.icloud.com/sharedalbum/#<token>` links are accepted (an optional locale
  segment such as `/sharedalbum/en-gb/` is allowed); anything else, including
  `https://share.icloud.com/photos/…` links, is `400` with an explanatory message. The link is a credential: it is stored
  privately on the frame and never returned, logged or shown again.
- `GET /v1/state` gains `settings.icloudAlbum`: `null`, or
  `{"name":"Family","count":24,"lastSync":"ISO-8601"|null,"syncing":false,"error":null|"<text>"}`.
- The frame syncs on connect, on start, and every 30 minutes. It keeps the newest pictures up
  to the library limit, removes pictures deleted from the album, and skips videos.
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
  `{"phase":"cancelled","reason":"decoy"|"frame"|"phone"|"refused"|"expired"}`.
  `remaining` is milliseconds left on the frame's monotonic clock; the dashboard only draws the
  countdown. `numbers` never says which entry is `pick`.
- `SkylitRemote.apply({location?,appearance?})`: a phone changed a setting that lives in
  dashboard `localStorage`. The dashboard applies it and then calls `reportSettings`.
- `SkylitCalendar.receive(...)` and `SkylitPhotos.receive(...)` as today, when the phone
  adds a calendar or photo.

Dashboard → native (`window.Skylit.*`, all return a JSON string or boolean):

- `householdSnapshot()` → the snapshot above.
- `householdMutate(json)` → `{"ok":true,"snapshot":{…}}` or `{"ok":false,"error":"…"}`.
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
- `pairingRevoke(id)` and `pairingRevokeAll()` → boolean.

Thermostats (Honeywell Total Connect Comfort) are reached only through the bridge. The frame's
native code signs in and polls; there are no thermostat routes in the phone API.

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
  network work runs on a worker thread; the outcome arrives through `receive` in `signIn`.
- `thermostatSignOut()` → boolean; erases the stored account and its key.
- `thermostatStep(id, delta)` → `{"ok":true,"setpoint":N}` or `{"ok":false,"error":"…"}`. One
  step per call in the direction of `delta`, kept inside the thermostat's own range; taps within a
  second are sent to Honeywell as one change, as a temporary hold.
- `thermostatMode(id, "heat"|"cool")` and `thermostatResume(id)` → `true` when started; the result
  arrives through `receive` (`changing`, then the new state or `error` and `message`).
- `thermostatWatch(visible)`: poll every 60 s while the Overview is showing, every 5 min otherwise.

Chores and shopping have one source of truth: the native household store. The dashboard's
old `skylit.household` shopping list is migrated into it once, then no longer written.
