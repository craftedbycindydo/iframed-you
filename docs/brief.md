# Product brief

- Intended for a family frame, with legible text and generous touch targets.
- Warm, friendly, harmonious colors: beige, terracotta, olive; optional dark cocoa.
- Six tabs: Weather, Photos, Calendar, Home, YouTube, Settings.
- No demo chores, agents, shopping, or simulated calendar data.
- User-selected weather location; real clock in the selected city's timezone.
- Family Google Photos album as both an intentional photo view and idle display.
- Default idle timeout two minutes, configurable; touch returns to dashboard.
- Google Home is the actual household platform. Its web UI exposes thermostat and
  light controls. An independent frame login is necessary for account access.
- Later: parents say a shopping-list request to their Google Home speakers; a shared
  list appears in a future dashboard tab. Do not add a fake shopping list now.

## Shopping-list feasibility

Google documents voice notes/lists using Google Keep on supported Home devices:
https://support.google.com/googlehome/answer/16722557
https://support.google.com/assistant/answer/14171370

The official Google Keep API is documented for enterprise administration, not a
simple consumer dashboard integration:
https://developers.google.com/workspace/keep/api/guides

Next step: verify the parents' actual Keep note and speaker account behavior, then
try the authenticated Keep website on the frame. A direct API consumer integration
is not promised. No private Keep notes or speaker settings have been accessed or
changed during this phase.
