# Photos and Calendar review

October 10, 2026. This review describes the 2.8 implementation and separates code
verification from household/device verification.

## Architecture

**Problem found:** The shared-album mode depends on Google's web slideshow and
cannot provide Skylit's own timing, transitions or offline playback. The new email
source keeps pictures locally and gives Skylit its own full-screen controls. It
retains the shared-album source for households that prefer its simpler setup.

**Boundary kept:** Calendar's private iCal URL stays in native storage. Inviter
addresses are parsed from feed events and filtered in the local dashboard; the
rule applies to both Calendar and Overview. It does not introduce a server,
Google Contacts authorization, or a Google Cloud project. Remote WebViews receive
neither the native bridge nor the photo cache. HTTPS host and local image path
checks remain exact.

**Privacy and capacity:** Email access uses a dedicated account's app password,
encrypted with Android Keystore. Mail is opened read-only; only resized JPEGs are
saved. Limits on image bytes, dimensions, scan size, count and age bound storage
and processing. Switching to a different account clears the prior account's
pictures; disconnect erases the credential and cache. All normal APKs have empty
household configuration.

**Remaining risk:** The app password can authorize broader mail access than this
importer's read-only behavior; a dedicated mailbox and revocation path matter.
The importer has compiled but has not authenticated against the actual household
account or run on the physical frame in this pass. The mail library is pinned and
license notices ship in the APK, but WebView 95 and Android mail MIME behavior need
on-device checks with real images. Google may change sign-in support. The calendar
feed may omit organizer addresses for some event types; the review rule hides
those by default and explains the exception.

## Usability

**Problem found:** A first version of the email Photos screen repeated setup text
across four cards and left a disabled slideshow action as the main focus. The
revised Photos page makes the source visible at the top. With no pictures, the
primary action opens setup or checks mail; cached pictures expose a simple gallery
and playback. The account form clears the typed app password after submission,
does not show it again, and distinguishes a saved credential from verified mail
access. Disconnect needs two taps. A manual slideshow has previous, next, pause
and close controls; idle mode has a first-touch return.

**Calendar decision:** The inviter panel labels its scope as “Who appears on this
frame.” It requires the calendar account address before review is enabled, so
the account's own events remain visible. Pending organizers are grouped by exact
address; approving or removing them updates both views immediately. Events with
missing organizer data have a separate switch. The panel does not pretend to
change Google Contacts or accept invitations in the Google account.

**Remaining usability work:** Test long-running import and several image formats
on the real frame. Confirm whether Google includes organizer addresses in this
household's private feed. Test the first-use setup with the owner, including Google
2-Step Verification and a real sent picture; the agent should never receive the
app password. Consider an optional trusted-sender rule for incoming pictures only
after the basic importer is stable; today anyone who can email the dedicated
account can send an image to the frame.

## Verification bar

JavaScript model/calendar tests, native policy and MIME parsing tests, a signed APK build and the
public-data scanner cover deterministic behavior and packaging. The synthetic
preview covers layout, not Gmail authentication or physical touch. The full feature
should be called household-verified only after an in-place install, a real email
image import and slide advance, age/removal, idle-return, plus a real calendar
invitation from an unapproved organizer followed by approval, removal and
cancelled-event refresh. Record only results and undo steps in the private setup
record, without credentials, links, event details or pictures.
