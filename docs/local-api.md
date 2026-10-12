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

## Pairing

| Call | Auth | Body | Result |
| --- | --- | --- | --- |
| `GET /v1/info` | none | | `{"v":1,"frameId":"…","name":"…"}` |
| `POST /v1/pair/start` | none | | `204`. The frame shows a 6-digit code for 120 s. |
| `POST /v1/pair/finish` | none | `{"code":"123456","deviceName":"Karan's iPhone"}` | `{"token":"…","frameId":"…","name":"…"}` |
| `GET /v1/devices` | token | | `[{"id":"…","name":"…","pairedAt":"ISO-8601"}]` |
| `DELETE /v1/devices/{id}` | token | | `204` |

- A code is single-use. Five wrong attempts or expiry invalidate it (`429` after the fifth).
- `pair/start` is limited to one active code; a new call replaces it.
- Tokens are 32 random bytes, hex. The frame stores only their SHA-256.
- The frame can also revoke every device from Settings.

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
- `SkylitPairing.show({code,expiresAt})` and `SkylitPairing.hide()`.
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
- `pairingStatus()` → `{"devices":[{"id","name","pairedAt"}],"port":8765,"advertised":true}`.
- `pairingRevoke(id)` and `pairingRevokeAll()` → boolean.

Chores and shopping have one source of truth: the native household store. The dashboard's
old `skylit.household` shopping list is migrated into it once, then no longer written.
