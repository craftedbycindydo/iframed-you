# Design review — 2.6

The dashboard should read clearly at arm's length and say what a control does.
Momo supplies personality; functional screens do not need marketing copy.

## Calendar critique and changes

| Finding | Change |
| --- | --- |
| A large slogan and empty decoration displaced useful information | Plain Calendar heading; concise connection instructions |
| Dates blended together and event text was difficult to scan | Visible weekday/grid boundaries, larger event and agenda type |
| Overflow count was clipped along with an event title | Independent +N badge; full count in the date's accessible label |
| Today and selection were easy to confuse | Today has a filled circle; selected date has an outlined cell |
| Event details did not look interactive | Explicit Details disclosure; generous summary touch targets |
| Month navigation could affect an overview summary | Overview stays anchored to today independently of the browsed month |
| Short tabs jumped vertically | Consistent top alignment across all tabs |

The six-row month fits the frame's 1280×720 effective viewport. Long titles still
truncate in cells: select the date to read complete titles and details in the agenda.
Agenda scrolls independently on the frame and stacks below the month on narrow
screens. This is a read-only calendar, so there are no misleading create/edit controls.

## Colour and hierarchy

Linen, Sage, Stone, Ocean, Plum and High contrast each have light and dark variants.
Automatic switches at the configured city's sun horizon without fetching weather.
Settings explains the location and next transition. The frame is left in Automatic.

Regular palettes use soft text and subtle dividers. Following owner feedback in
2.6.1, Linen and Sage light return to their original colours; Linen dark returns
to the original Cocoa colours. The newer palettes have similarly restrained text
and borders. Layout, typography, navigation and calendar improvements remain.

The optional **High contrast** palette keeps the stronger treatment. Its normal,
secondary and accent text are tested at 4.5:1 against background, panel, rail and
selected surfaces, as is button text. Control borders meet 3:1 against background
and panel. These checks apply to High contrast only, not a full accessibility claim
for the regular palettes or every possible rendered state.

Palette and mode are independent: Linen + Dark is warm brown; Ocean + Dark is blue.
Browser settings belong to that browser origin (including its port). The installed
frame has its own local settings. They do not sync. Matching palette and resolved
Light/Dark mode uses the same colour tokens in both deployments. Automatic can
resolve differently if location, device time or the synthetic demo date differs.

Kept: warm surfaces, restrained serif headings, clear touch controls, Momo.
Removed: repetitive “a little…” slogans, invented inspirational copy, giant
illustrations unrelated to an action, and placeholder home-status cards. The sidebar
has navigation, Momo and connection status; time/date live on Overview.

## Public screenshots

Run `python3 scripts/preview.py` and use the separate localhost demo. It contains
made-up events and a fixed forecast/date. Screenshots in `docs/screenshots` show this
fixture, visibly labelled DEMO DATA. Never screenshot private feed addresses, real
calendar contents, family photos, account identities or household setup records for
publication. Screenshots demonstrate layout, not authenticated service operation.

## Overview refinement — 2.7

The prior overview looked like a stack of shortcuts: the clock was subordinate and
the weather summary lost the illustration already used by Weather. Replaced that
structure with an oversized clock, a separate quiet day-period label, full date,
and two columns: illustrated forecast and a borderless agenda. Rain, wind and
sunset sit under the existing day/night landscape. Text stays outside the artwork.

Photos, Home, YouTube and Settings shortcuts are removed from Overview; the sidebar
handles navigation. Weather and calendar retain contextual drill-down arrows. No
palette or contrast changes. At 1280×720 the clock, forecast and five typical events
fit; long event titles can extend the page naturally. The columns stack on smaller
screens. No generated replacement asset, framework or new API request was needed.

## Card layout — 2.7.1

Clock/date, illustrated weather and upcoming events each occupy a matching card.
Shared panel colour, subtle borders, rounded corners and consistent gaps group the
information without increasing contrast. The large clock and weather artwork remain;
no duplicate service shortcuts were reintroduced.

## Overview hierarchy — 2.7.2

The first card layout spread the date too far from the clock and stretched the
weather card to match a dense agenda. Clock and date now share a compact card above
the weather, with Upcoming alongside both. Weather sizes to its contents. At frame
resolution the three cards fit comfortably with room below.

Events are grouped by Today, Tomorrow or date, with a separate Ongoing group.
Times and supporting text are larger; a single calendar's name is not repeated on
every row. Multiple-calendar names remain visible. Normal refresh timestamps stay
in the detailed tabs; Overview shows only missing, stale or offline status. Existing
palettes, artwork, Momo and drill-down controls are preserved.

## Photos and inviter controls — 2.8

Photos now exposes its source in the page heading. The email mode starts with one
clear setup/check action; cache details and thumbnails appear when useful. A
manual slideshow has large touch controls and a calm crossfade, while idle mode
hides controls and returns on first touch. Reduced-motion preference removes the
crossfade. The Google Photos shared-album mode remains familiar and available.

Calendar keeps the month and agenda prominent. Inviter review opens on demand,
with a clear frame-only scope, exact-address approval and a separate choice for
events missing organizer information. This avoids implying that the UI changes
Google Contacts or accepts events in Google Calendar. The detailed architecture,
usability critique and remaining validation are in [feature review](feature-review.md).

## First-run guide — 2.9

A new owner previously landed on an empty Overview and had to discover setup forms
across multiple tabs. The guide puts city, photos and calendar in a short sequence,
with a direct action for each. It uses existing settings forms rather than copying
credential fields into another screen. Calendar and Home can wait, so the guide is
easy to leave and reopen. A previous settings record suppresses auto-opening on
upgrade. Cards use the current palette, large buttons and plain status labels;
no decorative slogan or personal example data is shown.
