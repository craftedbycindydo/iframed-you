# Honeywell Total Connect Comfort thermostats: research note

Desk research, 2026-10-11. No Honeywell account was signed in to and no authenticated Honeywell
endpoint was called. Sources are public documentation, open-source client code read at the cited
lines, and public issue threads. Anything marked **UNCONFIRMED** could not be verified from a
source and must be checked before it is relied on. Source keys such as `[A1]` refer to the list at
the end.

## Recommendation

The owner's two thermostats are classic Total Connect Comfort (TCC) Wi-Fi thermostats, and the only
interface known to reach them is Resideo's unofficial TCC web service at
`mytotalconnectcomfort.com/portal`, the same one Home Assistant's `honeywell` integration uses
[A1][H1]. There is no evidence of a local API, HomeKit or Matter on this family, and the official
Resideo developer API is documented only for Honeywell Home (Lyric/T-series) accounts. Given the
owner's decision that the frame must control the thermostats itself, build option C: a small native
Java TCC client on the frame (no WebView involvement, reached only through the existing JS bridge),
logging in with a **dedicated secondary TCC user** that the owner grants access to the location, so
the owner's own password never touches the frame and the frame's access can be revoked from the
owner's account [T1]. The frame is the single poller and single writer; the iPhone app reads and
controls the thermostats through the frame's local API rather than holding its own Honeywell
session. Setpoint clamps, a change rate limit, a heat/cool/off-only mode list and an audit log live
in the frame's native code, and the limits are set only from a paired phone. These guard rails stop
accidents and a compromised web layer; they do not stop an attacker with root on the frame, who can
read the stored credential and call Honeywell directly. The mitigations that survive root are
outside the frame: the secondary account (revocable, cannot add or remove devices [T1]), TCC's own
temperature alert emails [T1], and any setpoint stops configured on the thermostats themselves
(**UNCONFIRMED** for this model). Schedule editing is not in the first version: no open-source
client implements it and the only description found is a 2013 WSDL. Two facts decide how safe this
can be made and are not yet known: how long a TCC session cookie survives (decides whether the
password must be stored at all) and whether Resideo's EULA clause against automated access is a
risk the owner accepts [T2].

## 1. Which systems and APIs exist, and which applies

### 1.1 What the owner has

Facts supplied by the coordinator (owner screenshots and a read-only look at the home network; not
run by this research):

- The classic "Total Connect Comfort" iOS app, one location, two thermostats ("Level-0",
  "level-1"), Fahrenheit, heat and cool, permanent hold and "Following Schedule" states, a
  four-period day (Wake, Leave, Return, Sleep) with heat and cool setpoints.
- Two Wi-Fi devices with MAC prefix `5C:FC:E1` and DHCP hostnames `gateway` + six hex digits. No
  open port among 24 common ones. No `_hap._tcp`, `_matter._tcp` or `_matterc._udp` advertisement.

What can be said about the hardware:

- `5C:FC:E1` is registered to Resideo [N1].
- The devices are almost certainly the two thermostats themselves, not RedLINK Internet Gateways.
  The RedLINK gateway connects to the router by Ethernet cable [T1], and one gateway serves up to
  four thermostats [T1], so a RedLINK install would normally show one wired device, not two Wi-Fi
  ones. TCC itself calls a Wi-Fi thermostat's network side a "gateway": the portal returns
  `GatewayIsLost` and `GatewayUpgrading` per device [U3], the mobile service has a `RegisterGateway`
  operation [W1], and the FAQ talks of deleting a "thermostat/gateway" identified by MAC ID and CRC
  [T1]. Confidence: high.
- The four periods match the TCC service's own schedule model exactly: `PeriodType` is
  `WakeOcc1`, `LeaveUnocc1`, `ReturnOcc2`, `SleepUnocc2` [W1].
- Exact model: **UNCONFIRMED**. No source was found that documents the `gatewayXXXXXX` hostname for
  a specific model. Candidates are the TCC Wi-Fi families that open-source clients list as working:
  RTH6580WF, RTH8580WF, RTH9580/RTH9585WF, TH6320WF, and the VisionPRO 8000 Wi-Fi (TH8321WF)
  [B1][H1]. A T5/T6 Pro Smart/T9/T10 is unlikely because Resideo's own guides pair those with the
  Resideo or First Alert app, not TCC [R1]. Confidence in "a TCC Wi-Fi thermostat": high. Confidence
  in any one model: low.

How the owner can confirm the model:

1. The TCC mobile service returns a model name per thermostat (`ModelTypeName`, read by
   homebridge-tcc [B2]); the first working client build can simply log it.
2. The TCC portal's location settings page lists each device's MAC ID and CRC [T1]; matching the
   MAC to the router's client list confirms which network device is which thermostat.
3. The model number printed on the thermostat (commonly on the back of the faceplate once it is
   pulled off the wall plate) and on the MAC ID/CRC card that shipped with it. **UNCONFIRMED** from
   a cited source; this is general knowledge about Honeywell thermostats.

### 1.2 The systems

| System | Reach | Applies here |
| --- | --- | --- |
| TCC web portal, `mytotalconnectcomfort.com/portal` (US) | Wi-Fi and RedLINK thermostats registered in TCC [T1]. Unofficial JSON calls behind the web UI [A1] | **Yes. This is the one.** |
| TCC mobile SOAP service, `TCCNA.resideo.com/ws/MobileV2.asmx` | Same accounts, used by the TCC phone app; homebridge-tcc speaks it [B3] | Yes, as an alternative transport and the only place schedule operations are described [W1] |
| TCC International / Evohome, `international.mytotalconnectcomfort.com` | Non-US heating and hot-water systems; OAuth password grant with an app ID embedded in the client; 30-minute access tokens [E1][E2] | No. US app, Fahrenheit, heat and cool |
| Official Resideo developer API, `api.honeywellhome.com/v2` | "A Honeywell Home account with a connected/installed device" [D2]; T-series ("LCC-" IDs) and the Honeywell Home Round ("TCC-" IDs) [D1][D3] | Not shown to reach TCC-app accounts; see 1.3 |
| Resideo app private API (Azure B2C login, `lyric.alarmnet.com`) | Devices in the Resideo/Honeywell Home app; one Go client implements it as a separate provider with separate credentials from TCC [U1][U5] | No |

### 1.3 Can the official developer API reach these thermostats?

Not established, and the evidence leans no.

- The official documentation describes two device ID prefixes: `"LCC-" == T-Series, "TCC-" ==
  Honeywell Home Round` [D1]. The "TCC-" prefix there names the Round, a Honeywell Home app device,
  not thermostats registered in the Total Connect Comfort app.
- The getting-started guide requires "A Honeywell Home account" [D2]. TCC and Honeywell
  Home/Resideo are separate logins: the one open-source client that supports both takes two
  credential pairs [U1].
- Users report that a Honeywell Home / Resideo link does not show thermostats that live in TCC;
  only the TCC-specific login does [C1].
- Against that: homebridge-resideo, which uses the developer API, lists "Some Total Comfort Control
  thermostats" with the caveat "Pushing commands may not be supported on some" [B4]. It does not
  say which, or under what account.

Status: **UNCONFIRMED either way**. The cheap test belongs to the owner: create a free developer
account, authorise it with their TCC email, and see whether `/v2/locations` lists the two devices.
If it does, section 3 becomes a real alternative; until then, plan on the unofficial service.

### 1.4 App landscape and deprecation

- Resideo's support page lists the Total Connect Comfort app as a live, separately monitored
  service [R1], and the status page lists "My Total Connect Comfort Application" as a component
  with a completed maintenance window on 2026-09-29 [R2].
- Resideo is moving users to a "First Alert" app: "Existing Total Connect 2.0, Resideo or Honeywell
  Home app users can still control their devices via their current mobile app until they are
  migrated to the new First Alert App" [R1]. That sentence does not name TCC.
- No announced retirement date for TCC was found. Absence of an announcement is **UNCONFIRMED**
  as evidence of anything; a migration of TCC accounts would break every client in section 2.
- The mobile service host used by homebridge-tcc is now on `resideo.com` [B3], and the main Python
  client dropped the `www.` prefix in October 2025 after a certificate failure on it [A4]. The
  service is being maintained and occasionally moved.

### 1.5 Local options

| Option | Finding |
| --- | --- |
| Local API on the thermostat | None documented. Every open-source client goes through Resideo's cloud [A1][B3][P1][U2]. The coordinator's 24-port scan found nothing open. A full port scan was not done, so "no local listener at all" is **UNCONFIRMED**, but nothing suggests one |
| RedLINK gateway | Not what is installed (1.1). The gateway is itself a cloud bridge to the same portal [T1] |
| HomeKit | Native HomeKit is listed for T5, T6, T9, T10 and the Round [B4]. No source lists it for the TCC Wi-Fi families, and nothing on the network advertises `_hap._tcp` |
| Matter | No source found for Matter on any TCC thermostat; nothing advertised. **UNCONFIRMED** as a negative for every model |
| Replace the thermostats | Swapping both for a HomeKit or Matter model is the only route that removes the cloud and the stored credential entirely. Hardware cost and installation, and it is the owner's call |

## 2. The unofficial TCC web service

Two transports exist. The portal JSON calls are the better-maintained path and the recommended one.

| Client | Language | Transport | Last push | Notes |
| --- | --- | --- | --- | --- |
| AIOSomecomfort [A1] | Python | Portal JSON | 2026-10-09 | Used by Home Assistant (`AIOSomecomfort==0.0.38`) [H3]; 0.0.38 released 2026-07-09 |
| somecomfort [S1] | Python | Portal JSON | 2022-12-26 | The original; superseded |
| Home Assistant `honeywell` [H2] | Python | via AIOSomecomfort | current | Polls every 30 s [H2] |
| pyhtcc [P1] | Python | Portal JSON | 2024-08-11 | Shows the "TooManyAttempts" redirect |
| unixpickle/tcc [U1] | Go | Portal JSON + HTML | 2026-10-03 | Re-logs in every 12 h |
| homebridge-tcc [B1] | JavaScript | Mobile SOAP | 2026-02-06 | Default poll 10 min |
| gotwalt/redlink [W1] | Ruby | Mobile SOAP | 2013-10-15 | Archived WSDL with schedule operations |

No Swift or Kotlin TCC client was found.

### 2.1 Portal JSON calls

Base `https://mytotalconnectcomfort.com` [A1 `__init__.py:15,54`]. Common headers on every call:
`X-Requested-With: XMLHttpRequest`, `Accept: */*`, `Connection: keep-alive`,
`Accept-Encoding: gzip, deflate` [A1 `__init__.py:47-52`]. No special User-Agent is set by
AIOSomecomfort; no client sends or parses an anti-forgery token.

**Login.** `POST /portal`, `Content-Type: application/x-www-form-urlencoded`, body
`timeOffset=480&UserName=<email>&Password=<password>&RememberMe=false`, with `@` encoded as `%40`
[A1 `__init__.py:94-117`]. The session is the cookie `.ASPXAUTH_TRUEHOME` [A1 `__init__.py:14`].
The server sends it with a malformed `expires` attribute that a strict cookie parser drops, so the
client clears the expiry and stores it by hand [A1 `__init__.py:73-91`]. The server also re-sends
the cookie on later responses and the client stores it each time [A1 `__init__.py:181-183`]. Login
is confirmed by a follow-up `GET /portal`: an empty auth cookie or a 401 there means failure
[A1 `__init__.py:135-158`]. A wrong password does not reliably produce a 401 on the POST
[A1 `__init__.py:122-125`]; pyhtcc instead looks for the text "The email or password provided is
incorrect" in the page [P1 `pyhtcc.py:548-555`]. unixpickle/tcc sends `RememberMe=true` and the
real UTC offset in minutes, and treats a final URL ending in `Zones` as success
[U2 `session.go:98-131`].

- MFA or captcha: no client handles either and none reports being asked for one. **UNCONFIRMED**
  that TCC never challenges.
- Log off: `POST /portal/Account/LogOff` [A1 `__init__.py:165-171`].

**List locations and devices.** `POST /portal/Location/GetLocationListData/?page=<1..4>&filter=`
with the common headers and no body. JSON array per page; each element has `LocationID` and
`Devices`, each device has `DeviceID`, `MacID`, `Name` [A1 `__init__.py:218-257`]
[A2 `location.py:17-22`] [A3 `device.py:51-53`].

**Read one thermostat.** `GET /portal/Device/CheckDataSession/<DeviceID>?_=<increasing integer>`
[A1 `__init__.py:264-268`]. Response:

```json
{
  "success": true,
  "deviceLive": true,
  "communicationLost": false,
  "latestData": {
    "hasFan": true,
    "uiData": { "DispTemperature": 74, "HeatSetpoint": 71, "CoolSetpoint": 78, "...": "..." },
    "fanData": { "fanMode": 0, "fanIsRunning": false, "...": "..." },
    "drData": {}
  }
}
```

Field shape from [A3 `device.py:63-77`]; the numbers are illustrative. A second call,
`POST /portal/Device/Menu/GetData?deviceID=<id>`, returns humidifier and dehumidifier data and is
only needed for those [A1 `__init__.py:259-262`].

| What the TCC app shows | Field | Source |
| --- | --- | --- |
| Indoor temperature | `uiData.DispTemperature` | [A3 `device.py:299-301`] |
| Units | `uiData.DisplayUnits` (`F` or `C`) | [A3 `device.py:396-398`] |
| Heat / cool setpoint | `uiData.HeatSetpoint`, `uiData.CoolSetpoint` | [A3 `device.py:163-196`] |
| Allowed setpoint range | `uiData.HeatLowerSetptLimit`, `HeatUpperSetptLimit`, `CoolLowerSetptLimit`, `CoolUpperSetptLimit`, `Deadband` | [A3 `device.py:169-172,200-203`] |
| System mode | `uiData.SystemSwitchPosition`: 0 em heat, 1 heat, 2 off, 3 cool, 4 and 5 auto | [A3 `device.py:9,133-140`] |
| Which modes are allowed | `uiData.SwitchHeatAllowed`, `SwitchCoolAllowed`, `SwitchOffAllowed`, `SwitchAutoAllowed`, `SwitchEmergencyHeatAllowed` | [A3 `device.py:148-156`] |
| Hold state | `uiData.StatusHeat`, `uiData.StatusCool`: 0 following schedule, 1 temporary, 2 permanent | [A3 `device.py:10,228-240`] |
| Temporary hold end | `uiData.HeatNextPeriod`, `CoolNextPeriod`: quarter-hours since midnight, 0 to 95 | [A3 `device.py:16-24`] [U4] |
| Fan mode | `fanData.fanMode`: 0 auto, 1 on, 2 circulate, 3 follow schedule; per-mode `fanMode<Mode>Allowed` | [A3 `device.py:8,106-130`] |
| Fan running | `fanData.fanIsRunning` | [A3 `device.py:100-104`] |
| Equipment running | `uiData.EquipmentOutputStatus`: 0 off or fan, 1 heating, 2 cooling; `null` on models that never report it | [A3 `device.py:11,363-379`] |
| Indoor humidity | `uiData.IndoorHumidity`, valid only if `IndoorHumiditySensorAvailable` and `IndoorHumiditySensorNotFault` | [A3 `device.py:353-361`] |
| Outdoor temperature / humidity | `uiData.OutdoorTemperature`, `OutdoorHumidity`, valid only if `OutdoorTemperatureAvailable`, `OutdoorHumidityAvailable` | [A3 `device.py:381-393`] |
| Online | `deviceLive` and not `communicationLost` | [A3 `device.py:94-97`] |

Where the outdoor numbers come from: the portal's control page carries a separate weather block
(`weatherTemperature`, `weatherHumidity`, `weatherPhrase`, `weatherHasStation`) alongside
`outdoorTemp` and `outdoorHumidity` [U3 `zone_info.go:38-39,61-65`], and the mobile service returns
a per-location `CurrentWeather` and has a `GetWeatherForecast` operation [W1]. That is consistent
with cloud weather for the location's postal code when no outdoor sensor is wired; the exact source
for the owner's thermostats is **UNCONFIRMED**. The frame already has Open-Meteo weather, so the
"5-Day" forecast link need not be replicated.

**Change anything.** `POST /portal/Device/SubmitControlScreenChanges`,
`Content-Type: application/json`, body always carries all nine keys, with `null` for "leave as is"
[A1 `__init__.py:280-302`]:

```json
{"DeviceID": 1234567, "SystemSwitch": null, "HeatSetpoint": 71, "CoolSetpoint": 78,
 "HeatNextPeriod": null, "CoolNextPeriod": null, "StatusHeat": 1, "StatusCool": 1, "FanMode": null}
```

Success is `{"success": 1}`; anything else is a rejection [A1 `__init__.py:301-302`].

| Action | Fields to send | Source |
| --- | --- | --- |
| Heat setpoint | `HeatSetpoint` = new value, `CoolSetpoint` = current value (or new + `Deadband` if they would cross); if currently following schedule also `StatusHeat` = `StatusCool` = 1 | [A3 `device.py:198-226`] |
| Cool setpoint | Mirror image | [A3 `device.py:167-191`] |
| Temporary hold until a time | `StatusHeat` = `StatusCool` = 1, `HeatNextPeriod` = `CoolNextPeriod` = quarter-hour index, optionally the setpoint | [A3 `device.py:254-261`] |
| Permanent hold | `StatusHeat` = `StatusCool` = 2 | [A3 `device.py:244-248`] |
| Resume schedule | `StatusHeat` = `StatusCool` = 0 | [A3 `device.py:249-253`] |
| System mode | `SystemSwitch` = 1 heat, 2 off, 3 cool (0 em heat, 4 auto) after checking the matching `Switch…Allowed` flag | [A3 `device.py:142-160`] [U2 `session.go:56-62`] |
| Fan | `FanMode` = 0, 1, 2 or 3 after checking `fanMode…Allowed` | [A3 `device.py:117-130`] |

Clients validate the range and deadband themselves before posting [A3 `device.py:174-181`]; whether
the server also rejects out-of-range values is **UNCONFIRMED**.

**Errors as the clients see them** [A1 `__init__.py:187-210`]:

| Response | Meaning in the client |
| --- | --- |
| 200 with JSON | Success |
| 401 or 403 | Session expired; log in again |
| 500, 502, 503, or any redirect in the chain | Service unavailable. The portal answers some failures with a 302 to `/portal/Error?aspxerrorpath=…` [A5] |
| 200 without JSON | Unexpected response; skip this poll |
| Login redirect URL containing `TooManyAttempts` | Login throttled [P1 `pyhtcc.py:559-562`] |
| Empty `.ASPXAUTH_TRUEHOME` after login | Login failed or site down [A1 `__init__.py:141-145`] |

### 2.2 Mobile SOAP calls (alternative transport)

`POST https://TCCNA.resideo.com/ws/MobileV2.asmx`, `Content-Type: text/xml;charset=UTF-8`, a
`soapAction` header of `http://services.alarmnet.com/Services/MobileV2/<Operation>`, and the TCC
iOS app's User-Agent `TCCStageC/1092 CFNetwork/1125.2 Darwin/19.4.0` [B3 `tcc.js:36-46`].

- `AuthenticateUserLogin{username, password, applicationID, applicationVersion: "2",
  uiLanguage: "Default"}` returns `SessionID`. The application ID is a fixed GUID copied from the
  phone app [B2 `tccMessage.js:35-45`].
- `GetLocations{sessionID}` returns every location with every thermostat's full `UI` and `Fan`
  blocks and the location's weather in one call [B3 `tcc.js:294-320`] [W1].
- `ChangeThermostatUI{sessionID, thermostatID, changeSystemSwitch, systemSwitch,
  changeHeatSetpoint, heatSetpoint, changeCoolSetpoint, coolSetpoint, changeHeatNextPeriod,
  heatNextPeriod, changeCoolNextPeriod, coolNextPeriod, changeStatusHeat, statusHeat,
  changeStatusCool, statusCool}` returns a `CommTaskID`, which is then polled with
  `GetCommTaskState` [B2 `tccMessage.js:60-82`] [B3 `tcc.js:92-111`].
- Result codes include `Success`, `AuthenticationFailed`, `InvalidSessionID`,
  `InvalidApplicationOrVersion`, `PermissionDenied`, `CannotControlSchedule`, `TooManyAttempt` [W1].
- The WSDL also lists `KeepAlive{sessionID}`, `ChangeThermostatFan`, `GetWeatherForecast` and
  `LogOff` [W1].

The WSDL is a 2013 copy in a third-party repository. The live service was deliberately not
queried, so whether each operation still exists is **UNCONFIRMED**, except the five homebridge-tcc
uses.

### 2.3 Weekly schedule: reading and writing

Stated plainly: **schedule editing is undocumented in practice.** None of AIOSomecomfort,
somecomfort, the Home Assistant integration, pyhtcc, unixpickle/tcc or homebridge-tcc reads or
writes the weekly schedule. The portal's own schedule page requests are not documented in any
source found. The FAQ adds "Not all thermostats support remote scheduling" [T1].

The only description found is the archived mobile WSDL [W1]:

- `GetSchedule{sessionID, thermostatID}` returns `ScheduleInfo{ScheduledPeriods[],
  MaxNumberOfPeriodsInDay, DisplayedUnits}`.
- Each `ScheduledPeriodInfo` is `{Day (Monday…Sunday), PeriodType (WakeOcc1, LeaveUnocc1,
  ReturnOcc2, SleepUnocc2), StartTime (int), IsCancelled, IsModified, HeatSetpoint, CoolSetpoint,
  FanSwitch}`. This matches the owner's Schedule screen field for field.
- Writing is a three-step edit: `ChangeSchedule{sessionID, thermostatID, scheduleInfo}`, then
  `SubmitScheduleChanges{sessionID, thermostatID}` (returns a `CommTaskID`), or
  `CancelScheduleChanges`.
- Per thermostat, `CanControlSchedule` and `WillSupportSchedule` say whether it is allowed.

**UNCONFIRMED**: the unit of `StartTime` (minutes or quarter-hours), whether these operations still
work, and their behaviour on error. No open-source code calling them was found. The read-only
values the portal does expose are the current period's scheduled setpoints, `schedHeatSp` and
`schedCoolSp` [U3 `zone_info.go:40-41,116-117`], enough to show "schedule says 70" but not the week.

The realistic way to settle this is for the owner to record their own browser's requests while
saving a schedule on the TCC website and hand over the request shapes with secrets removed.

### 2.4 Session lifetime, rate limits and lock-outs

Resideo publishes no numbers. What maintainers encode or report:

| Evidence | Number |
| --- | --- |
| AIOSomecomfort stops logging in for 10 minutes after 3 failed logins | `MIN_LOGIN_TIME = 10 min`, `MAX_LOGIN_ATTEMPTS = 3` [A1 `__init__.py:16-17,64-71`] |
| The same guard when first added (0.0.16, August 2023) | "limits login attempts to 5 minutes after 3 tries" [H4] |
| Cause of that fix | A bug logged in once per thermostat every 30 s; the user's own browser login then failed with "Too many attempts", asking them to wait a few minutes [H4] |
| Home Assistant poll interval | 30 s per thermostat [H2 `climate.py:87`], marked unavailable after 3 consecutive failures [H5] |
| Maintainer on polling volume | The TCC web app itself polls about every 5 s; "Since moving to asyncIO I have not seen a rate limit" [H6] |
| unixpickle/tcc | At most one login per 10 minutes, a forced re-login every 12 hours, re-login after 3 consecutive timeouts [U6 `backend.go:16-18`] |
| pyhtcc | Exponential backoff `2^i` seconds on `TooManyAttempts` [P1 `pyhtcc.py:487-501`] |
| homebridge-tcc (SOAP) | Default poll 600 s: "Lower than 10 minutes triggers request rate limiter on Honeywell site" [B5 `index.js:39`] |
| International variant, for comparison | Recommended minimum 180 s, default 300 s [E1] |

Reading of this: the portal throttles **logins** hard (three or so quick attempts earn a lock of
minutes) and tolerates frequent data polls; the SOAP service appears to throttle polls much
sooner. The duration of a lock-out and whether it is per account or per IP are **UNCONFIRMED**. A
lock-out on a shared account also locks the human out of the TCC website [H4], which is one more
reason for a dedicated secondary user.

Session lifetime: **UNCONFIRMED**. No client documents it. Every client keeps the password and
re-logs in on 401/403 [H2 `climate.py:539-566`] [U6 `backend.go:272-290`]; one re-logs in every
12 hours without waiting to be refused [U6]; one user watching the web app saw what looked like a
cookie refresh roughly every half hour [A6]. The server re-issues the auth cookie on ordinary
responses [A1 `__init__.py:181-183`], which is how a sliding session behaves, but nobody has shown
that polling alone keeps a session alive indefinitely. Plan on needing the password; measure before
assuming otherwise (section 6.2).

### 2.5 How fragile it has been

- August 2023: login storm and lock-outs; library fix released the same day it was diagnosed [H4].
- November 2023 to February 2024: recurring 401s and non-JSON "error page" responses from
  Honeywell's side; several library releases over about a week, then "roughly 1–5 errors per day"
  remained [H6][A5].
- June 2025: the library's cookie handling leaked Honeywell cookies into other integrations'
  requests; reported 2025-06-24, closed 2025-06-29 [H7].
- October 2025: the certificate on `www.mytotalconnectcomfort.com` failed; the library switched to
  the bare domain the same day [A4].
- Home Assistant's own documentation: "Due to the instability of the Honeywell total connect
  system, actions within automations should repeat until success" [H1].
- 2026-09-29: TCC scheduled maintenance of five to nine hours with the service unavailable [R2].

Summary: the call shapes have been stable for years; the service itself has routine short
failures, and the login and cookie handling needs occasional maintenance. Fixes from the main
maintainer have landed within days. A hand-written Java client will not get those fixes for free:
someone has to notice and port them.

### 2.6 Regional differences

The US portal and the international one are different services with different authentication
[E1][E2]. homebridge-tcc states it "does not work with the International Honeywell Total Connect
Comfort site" [B1]. Only the US service is relevant.

## 3. The official Resideo developer API

Relevant only if the test in 1.3 shows the owner's devices.

- **Sign-up**: a developer account at `developer.honeywellhome.com`, then "My Apps" → new app with
  a name and a callback URL; "The app will be approved automatically"; the app gets a consumer key
  and secret [L1]. The API is free: "Use Rights to and basic support … for the API are provided at
  no charge" [D4].
- **Flow**: authorization code. Browser to `https://api.honeywell.com/oauth2/authorize`; the user
  signs in and consents; redirect to the registered URI with `code=`. "The Redirect URI must match
  [what] is defined in your Application config." Exchange at `POST
  https://api.honeywell.com/oauth2/token` with `Authorization: Basic base64(key:secret)`; refresh
  at the same URL with the same header [D5]. Every data call also carries `?apikey=` [D2].
- **Token lifetime**: the sample response shows `"expires_in": "3599"` [D5]. Refresh token
  lifetime is not documented; the sample's `refresh_token_expires_in` is `"0"` with no explanation
  [D5]. **UNCONFIRMED**.
- **Rate limit**: "The number of Calls to our API is limited to 250 per hour unless otherwise
  agreed to in writing"; each HTTP request counts; exceeding it can lead to suspension [D4].
- **Terms**: the Developer License Agreement is written for a company shipping a product ("Company
  Offerings", end-user contracts, audit rights, security obligations) and lets Resideo "terminate
  this Agreement at any time for any reason or no reason" [D4]. Nothing in it singles out personal
  projects, for or against.
- **iPhone**: workable in principle with `ASWebAuthenticationSession`. Two catches. The token
  exchange needs the client secret in a Basic header and no PKCE variant is documented [D5], so the
  secret ships inside the app. Whether the portal accepts a custom-scheme redirect URI is
  **UNCONFIRMED**; an HTTPS redirect to a page the owner hosts is the fallback.
- **Frame**: a poor fit. The frame would hold the client key, the client secret and a refresh
  token, has no trustworthy browser for the consent step, and gains nothing in safety over a TCC
  secondary-user password: both are long-lived secrets that control the thermostats.

## 4. Terms and risk

- **Resideo's consumer EULA forbids this.** "Do not use automated means to access the System", "Do
  not circumvent or reverse engineer the System", and do not "flood" it with requests. Resideo "has
  the right to deny access to, and to suspend or terminate your access to, the System … at any time
  and for any reason" [T2]. Every client in section 2, including Home Assistant's, operates against
  those sentences. No report of an account being closed for using one was found (**UNCONFIRMED** as
  a guarantee). The owner should decide this knowingly.
- **Realistic consequences**: temporary login lock-outs that also block the human (2.4); breakage
  when Resideo changes the site or migrates TCC accounts (1.4, 2.5); in the worst case, account
  suspension, which would also disable the official app for those thermostats.
- **Account responsibility**: "you are fully responsible for all activities that occur under your
  password, account or any subaccount" [T2].
- **Credential handling**: TCC has no token or scope system. The credential is an email and
  password, a granted user "can change the settings on a thermostats and change the thermostat
  Alerts" [T1], and there is no documented read-only grant. Whatever holds the credential holds
  full control of heating and cooling in the house.

## 5. Architecture options

The owner has decided the frame must control the thermostats itself, so C is the design. The other
options are evaluated because the security review's concern does not go away, and because some of
them become the fallback if C proves unworkable.

| | A. Phone talks to Honeywell, frame displays | B. A plus frame requests relayed by phone | C. Frame talks to Honeywell (chosen) | D. Always-on bridge (Home Assistant or a small server) | E. HomeKit / Matter |
| --- | --- | --- | --- | --- | --- |
| Where the credential lives | iOS Keychain | iOS Keychain | Frame, sealed with an Android Keystore key | The bridge | Nowhere |
| Frame can control | No | Only while a phone is home with the app in the foreground | Yes, always | Yes, always | Not available |
| What root on the frame gains | A stale temperature reading | The ability to ask a phone for changes, clamped by the phone | The secondary account's password: full thermostat control from anywhere, until revoked | A token for a narrow, clamped bridge API | — |
| Reliability | Tile goes stale whenever no phone is home and awake | Same, and touch control mostly does not work: iOS suspends the app in the background and gives no way to wake it from a LAN request | As good as TCC itself; one poller | Best; Home Assistant's integration is maintained by others | — |
| Effort | Swift TCC client | Swift client plus a relay protocol | Java TCC client, bridge, local API, phone UI | Depends entirely on whether the machine exists | Replace two thermostats |
| Meets the owner's requirement | No | No | Yes | Yes | Would, with new hardware |

Notes on each:

- **A** is the safest design that needs no new hardware and remains the right fallback if the
  owner later decides the stored credential is not worth it. It fails the stated requirement.
- **B** should not be built. A phone app cannot reliably serve requests while backgrounded, so the
  frame's buttons would work only sometimes, which is worse than not having them.
- **C** is specified in section 6.
- **D** is the better design **if** the owner already runs Home Assistant or has an always-on
  machine: the Honeywell password would sit on a patched machine instead of the frame, clamps would
  be enforced somewhere a root attacker on the frame cannot reach, and Home Assistant's integration
  already exists [H1]. The owner has not said whether they have either. If they do, keep everything
  in section 6 above the "TCC client" layer (bridge calls, local API, data model, UI) and point the
  native layer at the bridge instead of at Honeywell. If they do not, D means buying and running a
  new machine, which the owner has not asked for.
- **E** is very likely unavailable: nothing on the network advertises HomeKit or Matter and no
  source lists either for TCC Wi-Fi thermostats (1.5). It becomes real only by replacing the
  thermostats, after which the phone would use the HomeKit framework and the frame would still need
  something to talk to, since Android 6 has no HomeKit client.

### On the record: where the "outbound only" reasoning is incomplete

The owner accepts the risk because the frame only makes outbound connections and an attacker would
have to be inside the home network. Two gaps. First, "inside the home network" includes every other
device on it: any compromised camera, plug, TV or guest phone is already inside and can reach the
frame's open ADB-with-root and local API. Second, the frame's own outbound browsing is a way in
that needs no inbound access: it renders third-party sites (YouTube, Google Photos, Home) in a
WebView 106 on a 2016 Android patch level, and a malicious page or ad that escapes the renderer
lands on a device with passwordless root.

## 6. Design for option C

### 6.1 Shape

```
dashboard (WebView, web/)  ──JS bridge──►  ThermostatService (native Java, one instance)
iPhone app  ──pinned TLS local API──────►        │  HttpsURLConnection, cookies by hand
                                                 ▼
                                   mytotalconnectcomfort.com/portal
```

- All Honeywell HTTP runs in native Java with `HttpsURLConnection`, following the pattern already
  used for iCloud: fixed host allowlist, redirects off, bounded reads, explicit timeouts
  (`android/src/com/wesbos/homehq/ICloudHttp.java:17-35`). The allowlist is exactly
  `mytotalconnectcomfort.com`. Redirects stay off because the portal signals errors and throttling
  through redirects (2.1); the client reads the `Location` header instead of following it.
- The dashboard never sees the password, the cookie, or a Honeywell URL. It gets a snapshot and can
  submit three kinds of change through the bridge. `connect-src` in `web/index.html:2` stays as it
  is (Open-Meteo only).
- The phone does **not** hold a Honeywell session. It reads and controls through the frame. One
  poller and one login for the whole household is what keeps TCC's login throttle (2.4) from
  being hit, gives one place for clamps and one audit log, and means the phone app needs no TCC
  client at all. The cost: thermostat control from the phone works only on the home Wi-Fi, like the
  rest of the app. Away from home the owner still needs the TCC app. A direct phone-to-Honeywell
  mode can be added later for that case; it should not be in the first version because two
  independent sessions double the lock-out exposure.
- TLS: the portal negotiates TLS 1.2 with `ECDHE-RSA-AES256-GCM-SHA384` and chains to "IdenTrust
  Commercial Root CA 1" (observed from the public handshake on 2026-10-11). Whether Android 6.0.1's
  trust store on this frame contains that root is **UNCONFIRMED** and must be checked on the device
  first. If it does not, ship the root in the APK and trust exactly it for this host. Never disable
  certificate checking.

### 6.2 What is stored on the frame

| Item | Stored | Why |
| --- | --- | --- |
| Secondary user's email | Private preferences | Needed to log in |
| Secondary user's password | Sealed with an Android Keystore AES-GCM key, email as associated data | Needed for unattended re-login (2.4) |
| Session cookie `.ASPXAUTH_TRUEHOME` | Memory only | Re-obtained by login; nothing gained by persisting it |
| Limits, device IDs, audit log | Private preferences / app-private file | |

The existing `MailSecret` (`android/src/com/wesbos/homehq/MailSecret.java:14-38`) is the right
mechanism to copy: a non-exportable Keystore AES key, GCM, the account name bound as associated
data (`:27`, `:35`), and a `forget()` that deletes the key (`:38`). Use a separate alias so
revoking the thermostat credential does not disturb mail. What it buys, honestly: the password is
not readable from a copied preferences file, a backup, or a storage dump. What it does not buy:
anything against root. A root process can run as the app's user and ask the Keystore to decrypt,
or read the password from the app's memory. Whether this chipset's Keystore is hardware-backed is
**UNCONFIRMED**, and it would not change that conclusion.

A stricter variant, worth building only if measurement supports it: store **no** password, keep
only the session cookie, and have the phone log in and hand the frame a fresh cookie when the
session dies. That works only if a polled session survives for days, and if the cookie is not tied
to the client that obtained it. Both are **UNCONFIRMED**. Measure first: log, on the first working
build, the time between login and the first 401. If sessions last longer than the household's
longest absence, switch to cookie-only; a stolen cookie can be killed by removing the secondary
user, and no reusable password is exposed.

### 6.3 Least privilege on Honeywell's side

TCC supports a second user per location, documented in its FAQ [T1]:

- Grant: My Account → "Add User under the My User List heading", giving the new user's email
  address, zip code and the location.
- Rights: "A granted user can change the settings on a thermostats and change the thermostat
  Alerts. They do not have the ability add/remove devices from a location or change the location
  settings."
- Revoke: My Account → Settings next to the user → Delete; "the user will no longer have access".

So the frame should log in as a dedicated secondary user created for it with its own email address
and its own password. That gives: the owner's main login never touches the frame; revocation
without changing the owner's password; no ability to remove the thermostats from the account or
re-register them. It does **not** give read-only or setpoint-only access; none is documented, and a
granted user can change thermostat settings, which may include the schedule and does include the
alerts (**UNCONFIRMED** which settings exactly). The mobile service's per-location `CanControl`
flag [W1] hints at a finer permission, but nothing shows how to set it. Whether a granted user can
see or alter the owner's account details, and whether the new user must already have a TCC account,
are **UNCONFIRMED**; the owner will see both when adding the user.

### 6.4 Guard rails in native code

These are enforced in `ThermostatService`, below both the bridge and the local API, so a change
from either path passes through them. They stop mistakes, a child holding the + button, and a
compromised dashboard or web layer. They do not stop an attacker with root, who can skip the
service and call Honeywell with the stored credential.

| Rule | Default | Changeable |
| --- | --- | --- |
| Heat setpoint range | 60–76 °F | Phone only |
| Cool setpoint range | 68–85 °F | Phone only |
| Also inside the thermostat's own `…SetptLimit` values and respecting `Deadband` | always | no |
| Whole degrees Fahrenheit only | always | no |
| Modes that can be set | heat, cool, off; never auto or emergency heat | `allowOff` from phone |
| Hold actions | temporary hold (to the next schedule period), permanent hold, resume schedule | no |
| Changes per thermostat | at most 6 in 10 minutes and 30 in a day; excess is refused with `rate_limited` | Phone only |
| Schedule, fan, alerts, account, humidifier | no code path exists | no |
| Audit log | last 200 changes: time, source (`frame` or device ID), thermostat, before, after, result | Read by phone |

The defaults are proposals. They bracket the owner's current schedule for heat (62–70) but the
cool lower bound of 68 is above the schedule's Sleep value of 64; the owner should set the numbers.
`off` is the dangerous one in winter (frozen pipes); the proposal is to allow it but require a
confirmation tap on the frame, and to let the phone disable it for the season.

Protection that survives a rooted frame has to sit elsewhere:

- The dedicated secondary user (6.3), so access can be cut from the owner's account.
- TCC temperature alerts by email, to as many as six addresses per location [T1], so an abnormal
  indoor temperature is reported by Honeywell regardless of what the frame says.
- Setpoint range stops configured on the thermostat itself. The API exposes per-thermostat
  `HeatLowerSetptLimit` … `CoolUpperSetptLimit` [A3], and Resideo's documentation for its other
  thermostats calls the equivalent limits "Configurable locally; not changeable remotely" [D1].
  Whether the owner's model has such an installer setting and whether the cloud honours it is
  **UNCONFIRMED**; it is worth checking in the model's installer manual because it is the only
  clamp an attacker with the password cannot move.
- The phone app showing the audit log and the frame's last-poll time, so unexpected changes made
  outside the frame (which will not be in the log) show up as a setpoint nobody recorded.

### 6.5 Data model

One snapshot, used unchanged by the bridge, the local API and the phone:

```json
{
  "configured": true,
  "status": "ok",
  "polledAt": "2026-10-11T18:04:10Z",
  "nextPollAt": "2026-10-11T18:05:10Z",
  "units": "F",
  "limits": {"heatMin": 60, "heatMax": 76, "coolMin": 68, "coolMax": 85, "allowOff": true},
  "thermostats": [
    {
      "id": "t1",
      "name": "Level-0",
      "online": true,
      "indoor": 74,
      "humidity": null,
      "mode": "heat",
      "modes": ["heat", "cool", "off"],
      "setpoint": 71,
      "heatSetpoint": 71,
      "coolSetpoint": 78,
      "range": {"min": 60, "max": 76},
      "hold": "permanent",
      "holdUntil": null,
      "scheduledSetpoint": 70,
      "running": "idle",
      "fanRunning": false
    }
  ],
  "outdoor": {"temperature": 77, "humidity": 25}
}
```

- `status`: `ok`, `stale` (last good poll older than 10 minutes), `signed_out` (credential rejected
  or revoked), `locked_out` (login throttled; `nextPollAt` says when it will retry), `unavailable`
  (Honeywell errors), `unconfigured`.
- `id` is a frame-local alias. Honeywell's `DeviceID` and `LocationID` stay in native storage and
  are never sent to the dashboard or the phone.
- `setpoint` and `range` are for the active mode, already intersected with the limits, so a UI can
  draw its up/down control without knowing the rules. `mode: "off"` has `setpoint: null`.
- `hold`: `schedule`, `temporary`, `permanent`; `holdUntil` is `"HH:MM"` for temporary.
- `running`: `heating`, `cooling`, `idle`, or `null` when the model does not report it [A3].
- `humidity` and `outdoor` fields are `null` when the `…Available` flags are false.
- The email address appears nowhere in the snapshot.

### 6.6 Calls per poll and polling plan

Per poll: one `CheckDataSession` per thermostat, so two requests. `GetLocationListData` runs once
after each login. A login is two requests.

| Situation | Cadence |
| --- | --- |
| Thermostat tile or page visible on the frame, or a phone has read the state in the last 2 minutes | every 60 s |
| Idle (slideshow, quiet clock, another page) | every 5 minutes |
| After a successful change | once after 5 s, once after 30 s, then back to the cadence |
| 401/403 on a poll | one login, provided the last login attempt was more than 10 minutes ago |
| Login refused, page says credentials are wrong | stop; `signed_out`; no retry until the phone sets the account again |
| Login throttled (`TooManyAttempts`, or an empty auth cookie) | `locked_out`; retry after 30 minutes, doubling to 6 hours |
| 5xx, error redirect, timeout, non-JSON | keep the last snapshot; retry after 1, 2, 5, then every 10 minutes; `unavailable` after three in a row |
| Frame offline | no requests; resume on reconnect with one poll |

That is at most 120 requests an hour while visible and 24 an hour idle, well under what Home
Assistant sends per thermostat (30 s interval [H2]) and far under the web app's own rate [H6]. Add
a few seconds of random jitter so polls are not on the minute. Like the existing mail and iCloud
checks, this runs while the activity exists; it is not a background service
(`MainActivity.java:47` for the existing minute timer).

What the UI shows:

- `ok`: values as normal.
- `stale` or `unavailable`: the last values dimmed with "as of 6:04 PM"; the up/down and mode
  controls disabled, because a change sent blind may fight a change made at the thermostat.
- `locked_out`: "Honeywell is refusing sign-in. Trying again at 6:40 PM." Controls disabled.
- `signed_out`: "Thermostat access was removed. Set it up again from the phone app."
- A change in flight shows the requested value as pending; if `{"success":1}` does not come back
  or the next poll disagrees, revert the display and say the change did not take.

### 6.7 Proposed additions to docs/local-api.md (not applied)

New error codes: `502 upstream_failed` (Honeywell refused or errored), `503 thermostat_unavailable`
(status is not `ok`), plus the existing `400`, `404`, `409`, `429`.

`GET /v1/state` gains `"thermostat"`: the snapshot from 6.5, or `null` when unconfigured. `rev` is
bumped when a displayed value, `status` or `limits` changes, not on every poll.

| Call | Auth | Body | Result |
| --- | --- | --- | --- |
| `PUT /v1/thermostat/account` | token | `{"email","password"}` | `{"rev":N}` after one login and device discovery succeed; `400` if Honeywell rejects the credentials; `502` otherwise. Never returned, logged or shown again |
| `DELETE /v1/thermostat/account` | token | | `{"rev":N}`; logs off, deletes the sealed password and its Keystore key, clears device IDs |
| `PUT /v1/thermostat/limits` | token | `{"heatMin","heatMax","coolMin","coolMax","allowOff"}` | `{"rev":N,"limits":{…}}`; `400` unless 45 ≤ min < max ≤ 95 |
| `GET /v1/thermostat` | token | | The snapshot; also marks a phone as watching for 2 minutes |
| `POST /v1/thermostat/refresh` | token | | `204`; one poll now, at most once per 30 s (`429` otherwise) |
| `POST /v1/thermostats/{id}/setpoint` | token | `{"value":72,"hold":"temporary"\|"permanent"}` | `{"rev":N,"thermostat":{…}}`; `400` outside limits; `429` over the change rate; `503`; `502` |
| `POST /v1/thermostats/{id}/mode` | token | `{"mode":"heat"\|"cool"\|"off"}` | as above; `400` if the thermostat or `allowOff` does not permit it |
| `POST /v1/thermostats/{id}/resume` | token | | as above; returns the thermostat to its schedule |
| `GET /v1/thermostat/log` | token | | `[{"at","source","thermostat","action","from","to","result"}]`, newest first, 200 at most |

`value` applies to the active mode's setpoint. There is no endpoint for the schedule, fan, alerts
or the Honeywell account beyond set and delete.

Bridge additions.

Dashboard → native (`window.Skylit.*`):

- `thermostatSnapshot()` → the snapshot as a JSON string, or `null`.
- `thermostatChange(json)` → `{"ok":true}` when accepted for sending, or
  `{"ok":false,"error":"…"}`. `json` is `{"op":"setpoint","id","value","hold"}`,
  `{"op":"mode","id","mode"}` or `{"op":"resume","id"}`. The outcome arrives by `receive`.
- `thermostatWatch(visible)` → boolean; the dashboard reports whether a thermostat view is on
  screen, which selects the polling cadence.

Native → dashboard: `SkylitThermostat.receive(snapshot)` after every poll that changes something
and after every change attempt, guarded with `window.SkylitThermostat&&` like the others.

Deliberately absent from the bridge: setting or deleting the account, changing limits, reading the
audit log. Those are phone-only, so page script cannot widen its own limits.

### 6.8 Smallest first version

1. On the device, confirm the frame trusts the portal's certificate chain (6.1).
2. Native TCC client: login, discover, read, the three changes, with the error handling in 2.1.
   Log the model name and the observed session lifetime.
3. Guard rails and audit log (6.4), with unit tests on the desktop JVM like the existing native
   tests.
4. Bridge and a dashboard tile: both thermostats, indoor temperature, setpoint up/down,
   heat/cool/off, hold state with "Resume schedule", stale and locked-out states.
5. Local API endpoints (6.7) and the iPhone screens in section 7, including account setup,
   revocation and limits.

Not in the first version: schedule viewing or editing, fan control, humidity control, the 5-day
forecast, alerts, control away from home, emergency heat and auto modes.

## 7. What the thermostat part of the iPhone app needs

Derived from the owner's TCC screenshots; these are the screens and controls being replaced.

| TCC screen or control | In iFramed You |
| --- | --- |
| Locations list | Not needed: one location. Go straight to the thermostat list |
| Home list: two thermostats with name, indoor temperature, system mode, hold status | A "Thermostats" section with one card per thermostat: name, indoor °F, mode, setpoint, hold state, heating/cooling indicator where reported, "as of" time |
| Detail: indoor temperature | Large current temperature |
| Detail: heat (or cool) setpoint with up/down | Stepper bounded by `range`; sends on pause, not on every tap, to respect the change rate limit |
| Detail: "Press for Options" (hold options) | Choice when changing a setpoint: "Until next schedule change" (temporary) or "Until I change it" (permanent); and a "Resume schedule" button when holding |
| Detail: hold status ("Permanent Hold", "Following Schedule") | Status line; for temporary holds, "Hold until 6:00 PM" |
| System tab (heat / cool / off…) | Segmented control built from `modes`; confirmation before "Off" |
| Fan tab | Later. Read-only "fan running" indicator in the first version |
| Outdoor temperature and humidity, "5-Day" link | Optional line from `outdoor`; the forecast already exists in the app's weather |
| Schedule tab: day selector, Wake/Leave/Return/Sleep with heat and cool setpoints, "Guide Me Through Scheduling", "View Individual Days" | Later, and only if section 2.3 is resolved. First version shows "Schedule says 70°" from `scheduledSetpoint` and keeps schedule editing in the TCC app |
| "Find Rebates" | Dropped |
| Settings | New, app-specific: connect the frame's Honeywell access (email and password of the secondary user, sent to the frame), remove it, set heat and cool limits, allow or forbid "Off", view the change log, see connection status |

States every thermostat screen must handle: not set up, loading, ok, stale, Honeywell unavailable,
sign-in refused (lock-out with retry time), access removed, thermostat offline, change pending,
change failed, change refused by limits, and "not on home Wi-Fi" (frame unreachable).

## 8. Open questions for the owner

1. Exact thermostat model numbers (from the units, or from the first client build's log).
2. Do you run Home Assistant, or have any always-on computer at home? If yes, option D replaces the
   bottom layer of this design and keeps the password off the frame.
3. Resideo's EULA says not to use automated means to access the service [T2]. Is that acceptable,
   knowing the worst case is losing the account?
4. Will you create a second TCC user for the frame, with its own email address, and grant it the
   location? (Needs a second email address.)
5. The limits: lowest and highest heat setpoint, lowest and highest cool setpoint, and whether the
   frame may turn the system off.
6. Is "phone controls only on home Wi-Fi" acceptable for the first version, with the TCC app kept
   for away-from-home?
7. Is schedule editing required, or is keeping it in the TCC app acceptable? If required, are you
   willing to record your browser's requests while saving a schedule on the TCC website?
8. Will you try the official developer API test in 1.3? It is the only way to learn whether a
   supported API reaches these thermostats.
9. Do the thermostats have a setpoint-limit setting in their installer menu, and will you set it?
10. Turn on TCC high and low temperature alert emails for both thermostats, independent of this
    project.

## 9. What was and was not verified

- Read in this session: the client source files cited by line; the developer documentation pages;
  the Developer License Agreement; the consumer EULA; the TCC FAQ; the repository's `README.md`,
  `docs/architecture.md`, `docs/local-api.md`, `MailSecret.java`, the head of `ICloudHttp.java`.
- Not done: no code was run against Honeywell; no call shape in section 2 was tested. They are as
  the cited clients implement them.
- Supplied by the coordinator, not checked here: the screenshots' contents and the network scan.
- Line numbers refer to the default branch as fetched on 2026-10-11 and will drift.

## Sources

Open-source clients

- [A1] AIOSomecomfort `aiosomecomfort/__init__.py` — https://github.com/mkmer/AIOSomecomfort/blob/main/aiosomecomfort/__init__.py
- [A2] AIOSomecomfort `location.py` — https://github.com/mkmer/AIOSomecomfort/blob/main/aiosomecomfort/location.py
- [A3] AIOSomecomfort `device.py` — https://github.com/mkmer/AIOSomecomfort/blob/main/aiosomecomfort/device.py
- [A4] AIOSomecomfort PR 10, "Update DOMAIN variable to remove 'www.' prefix", 2025-10-27 — https://github.com/mkmer/AIOSomecomfort/pull/10
- [A5] AIOSomecomfort issue 6, "302 found ...?" — https://github.com/mkmer/AIOSomecomfort/issues/6
- [A6] AIOSomecomfort issue 5, "Possible cause of occasional session errors with server" — https://github.com/mkmer/AIOSomecomfort/issues/5
- [S1] somecomfort `client.py` — https://github.com/kk7ds/somecomfort/blob/master/somecomfort/client.py
- [P1] pyhtcc `pyhtcc.py` — https://github.com/csm10495/pyhtcc/blob/master/pyhtcc/pyhtcc.py
- [U1] unixpickle/tcc README — https://github.com/unixpickle/tcc
- [U2] unixpickle/tcc `tcc/session.go` — https://github.com/unixpickle/tcc/blob/main/tcc/session.go
- [U3] unixpickle/tcc `tcc/zone_info.go` — https://github.com/unixpickle/tcc/blob/main/tcc/zone_info.go
- [U4] unixpickle/tcc `tcc/period.go` — https://github.com/unixpickle/tcc/blob/main/tcc/period.go
- [U5] unixpickle/tcc `resideo/auth.go` — https://github.com/unixpickle/tcc/blob/main/resideo/auth.go
- [U6] unixpickle/tcc `tcc/backend.go` — https://github.com/unixpickle/tcc/blob/main/tcc/backend.go
- [B1] homebridge-tcc README — https://github.com/NorthernMan54/homebridge-tcc
- [B2] homebridge-tcc `src/lib/tccMessage.js` — https://github.com/NorthernMan54/homebridge-tcc/blob/main/src/lib/tccMessage.js
- [B3] homebridge-tcc `src/lib/tcc.js` — https://github.com/NorthernMan54/homebridge-tcc/blob/main/src/lib/tcc.js
- [B4] homebridge-resideo README — https://github.com/homebridge-plugins/homebridge-resideo
- [B5] homebridge-tcc `src/index.js` — https://github.com/NorthernMan54/homebridge-tcc/blob/main/src/index.js
- [W1] Archived TCC mobile WSDL in gotwalt/redlink (2013) — https://github.com/gotwalt/redlink/blob/master/wsdl/MobileV2.xml
- [E2] evohome-async `auth.py` — https://github.com/zxdavb/evohome-async/blob/master/src/evohomeasync2/auth.py

Home Assistant

- [H1] Honeywell Total Connect Comfort (US) integration page — https://www.home-assistant.io/integrations/honeywell
- [H2] `honeywell/climate.py` — https://github.com/home-assistant/core/blob/dev/homeassistant/components/honeywell/climate.py
- [H3] `honeywell/manifest.json` — https://github.com/home-assistant/core/blob/dev/homeassistant/components/honeywell/manifest.json
- [H4] core issue 98763 (login lock-out, August 2023) — https://github.com/home-assistant/core/issues/98763
- [H5] `honeywell/const.py` (`RETRY = 3`) — https://github.com/home-assistant/core/blob/dev/homeassistant/components/honeywell/const.py
- [H6] core issue 104269 (rate limit and 401 errors, November 2023) — https://github.com/home-assistant/core/issues/104269
- [H7] core issue 147395 (cookie leak, June 2025) — https://github.com/home-assistant/core/issues/147395
- [L1] Honeywell Lyric integration page — https://www.home-assistant.io/integrations/lyric
- [E1] Honeywell Total Connect Comfort (Europe) integration page — https://www.home-assistant.io/integrations/evohome/

Resideo

- [T1] My Total Connect Comfort FAQ — https://mytotalconnectcomfort.com/portal/Home/FAQs
- [T2] Resideo End User License Agreement — https://www.resideo.com/us/en/corporate/legal/eula/en-us/
- [R1] Resideo app help and support — https://www.resideo.com/us/en/support/apps/
- [R2] Resideo status page — https://status.resideo.com/
- [D1] Developer site, Lyric API documentation — https://developer.honeywellhome.com/lyric/apis
- [D2] Developer site, "What Can I Do With the Honeywell Home Thermostat API?" — https://developer.honeywellhome.com/node/72
- [D3] Developer site, T-Series Thermostat Getting Started Guide — https://developer.honeywellhome.com/node/99
- [D4] Resideo Developer License Agreement — https://developer.honeywellhome.com/legal
- [D5] Developer site, Authorization (OAuth2) — https://developer.honeywellhome.com/authorization-oauth2/apis
- [D6] Developer site, API method list — https://developer.honeywellhome.com/api-methods

Other

- [C1] SmartThings community, "Honeywell Resideo Linked Services Help Request" — https://community.smartthings.com/t/honeywell-resideo-linked-services-help-request/263393
- [N1] MAC prefix 5C:FC:E1 registration — https://api.maclookup.app/v2/macs/5CFCE1
