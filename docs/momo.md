# Momo

Momo replaces the left-rail logo and wordmark. He is drawn with the Canvas 2D API,
including every accessory, with no image sprites, external service or animation dependency.
The chosen concept is saved in `design/robot-concepts/momo-reference.png`; implementation
adds an outlined amber shell, cream trim, olive ears and terracotta accents.

Tap Momo to cycle 13 reactions: hello, curious, wink, delighted, stretch, sneeze,
dance, peek, proud, puzzled, sleepy, surprised and yawn. Daytime idle reactions are randomized;
quiet stretches lead to sleepy eyes. Touch/mouse attention and scrolling move his
gaze and tilt. Animation never generates touch events or resets the photo timer.

Use the hanger button to open his wardrobe in Settings. Choose a fixed accessory,
no accessory, automatic changes roughly every 90 seconds, or New clothes every day.
Accessories: beret, beanie, bucket hat, cap, party hat, crown, flower clip,
headphones, bow, nightcap and wizard hat.

Playful, Gentle and Still preferences persist in `skylit.momo` localStorage.
System reduced motion overrides movement. Still/reduced mode draws on changes
without a continuous animation loop. Active animation is capped near 30 fps;
canvas backing resolution is capped at 2x. The native app explicitly pauses Momo
when remote views cover the dashboard or the activity leaves the foreground.
Page visibility also stops animation. No firmware or original-app changes.

## Verification

- `node --test tests/momo*.test.cjs`: twelve tests pass, covering finite drawing
  geometry for all hats/reactions, pause/resume, reduced motion, rapid still-mode
  changes, persistence, invalid preferences, idle sleep and automatic wardrobe.
- Chrome: wardrobe controls, every accessory, preferences after reload, reaction
  button, theme switch and Weather navigation exercised; no captured console errors.
- Physical Android 12 / WebView 95 frame: signed v2.3 installed over paired TLS ADB,
  mascot rendered, wardrobe shortcut reached its Settings section.
- Long-term unattended animation and battery/thermal profiling are not measured.

## Undo

This is an application update, not a system change. The preceding source release is
commit ab8de78. Rebuilding that release with a higher version code and the existing
local signing key restores the previous UI while retaining application data.
Do not uninstall or clear app data to remove the mascot. Choosing Still stops motion;
choosing Just Momo removes the accessory.


## Daily rhythm (implemented in 2.3)

Uses the dashboard city's timezone (Richmond Hill: America/Toronto). Clock is checked
at most every 30 seconds while visible and immediately on native resume. No changes
to the OS clock, weather preferences or photo timeout.

| Local time | Routine |
| --- | --- |
| 22:00–06:00 | Closed eyes, slow breathing/nodding; no random dancing. A user reaction briefly overrides sleep, then he settles again. |
| 06:00–09:00 | Drowsy resting eyes; yawns, stretches, occasional curious looks. |
| 09:00–20:00 | Usual playful idle pool; sleepy after prolonged inactivity. |
| 20:00–22:00 | Drowsy eyes, yawns and stretches to wind down. |

Settings can disable the schedule with Playful at any hour. Still/reduced-motion
retains an appropriate static resting expression. These routines apply only while
the dashboard is visible; the normal photo screensaver can still cover Momo.

## Gallery and daily clothes (implemented in 2.3)

Twelve native-canvas previews: eleven accessories plus Just Momo. Tapping a tile
selects a fixed look. The outlined/ticked tile marks the currently worn accessory.
New clothes every day chooses from the eleven accessories using the local calendar
date, remaining stable across reload/restart and changing at local midnight (within
the next 30-second clock check, or on return to the dashboard). It cycles without
adjacent-day repeats. Existing fixed and 90-second rotating choices remain available.
No external scheduling service or account is involved.

Verified gallery selection and persisted daily choice in Chrome; native gallery and
selected daily mode confirmed on the physical frame. Tests cover daypart boundaries,
Toronto midnight, another timezone, the repeated daylight-saving hour, gallery
selection, night/morning transitions, and daily changes in Still mode.

## Ideas for a future pass (not implemented)

- First touch each morning: one special sleepy greeting, then perk up gradually.
- Weather: hat fluttering in wind, a tiny umbrella in rain, beanie shiver in snow.
  React only to current valid weather data, not a failed or stale fetch.
- Morning ritual: imaginary coffee sip and a contented blink.
- Weekend personality: a later wake-up schedule and a relaxed cap.
- Attention: two quick taps make him giggle; a long press produces a curious squint.
- Photos: a fond look before the slideshow and a welcome-back blink afterward.
- Home controls: nod after a confirmed successful light/thermostat action; never
  imply a device operation succeeded before the integration confirms it.
- Connectivity: a mildly puzzled look while offline; relief when the connection returns.
- Celebrations: birthday crown or seasonal outfits when explicitly configured.
- Rare surprises: catch a falling hat, balance it, or peek from the edge of the rail.
- Bedtime: automatically change into a nightcap, then restore the daily outfit in the morning.
- Personal schedule: configurable bedtime/wake-up hours rather than the initial fixed defaults.
