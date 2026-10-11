# Photos by email

Skylit can play either a Google Photos shared album or a private slideshow made from
pictures mailed to a dedicated Gmail account. Choose the source in **Settings → Photos → Photo source**. The
shared-album route remains the default and requires no extra account setup.

## Set up email delivery on the frame

1. Use a dedicated Gmail account for pictures meant to appear on the frame. Anyone
   who can send it a picture can put that picture on the display. Avoid using a
   personal inbox with private mail.
2. On a trusted phone or computer, enable [Google 2-Step Verification](https://support.google.com/accounts/answer/185839)
   and create an [app password](https://support.google.com/accounts/answer/185833).
   Google may not offer app passwords for every account or security configuration.
3. On the frame, open **Photos → Photo settings → Photo source → Pictures sent by email**, then **Delivery**. Enter the
   Gmail address and 16-character app password there. Never
   put either credential in chat, source code, screenshots or the setup record.
4. Tap **Connect and check mail**. The app stores the credential first, then checks
   Gmail via encrypted IMAP. A saved credential is not proof of successful sign-in:
   wait for a last-checked time, an error, or a received picture.
5. Send a JPEG, PNG, WebP or HEIC image to the account. Tap **Check now** and confirm
   the picture appears in the Photo library and advances in the full-screen slideshow.
   Tap a thumbnail to browse, use Next/Previous, and tap Zoom to inspect it. Choose
   **Soft fade**, **Falling prints**, or **Photo collage** in Photo settings. Set
   **Show photos after** to the desired idle time. The first touch exits idle mode.

Slideshow controls use the current palette and fade after four seconds without
interaction. Touch, pointer movement or a key brings them back. The three styles
apply to emailed pictures; a Google Photos shared album uses Google's own player.

Google says personal Gmail accounts have IMAP access enabled. Its ordinary account
password is not accepted by this route; the app password requires 2-Step
Verification. [Gmail client guidance](https://support.google.com/mail/answer/7126229)
recommends Google sign-in when available; this optional local-only integration uses
an app password because it requires no hosted OAuth service or Google developer
project. An app password grants mail access beyond just picture attachments, so use
a dedicated account and revoke its app password in Google Account settings if the
frame is lost or retired.

## What Skylit stores

The Android app checks the inbox read-only when opened and on the selected
15-minute, hourly or daily schedule (daily remains the upgrade/default value).
Only one check runs at a time. Automatic failures back off from five minutes to
one hour; the last good cache is retained. **Check now** starts an immediate check. It scans recent inbox
messages, accepts image parts with sane dimensions and size, resizes them to at most
2400 pixels on the long edge, removes EXIF metadata by re-encoding, and keeps a
private cache of the newest 5–50 unique pictures from the chosen 30- or 90-day
window. The default is 30 pictures from 30 days. Email bodies and sender data are
not saved. Other mail folders and cloud photo albums are not scanned. A picture
deleted from email may remain until its retention window expires or the user
disconnects. When offline, the last saved pictures remain playable.

The app password is encrypted using Android Keystore with the address bound as
authenticated data. Backups are disabled. **Disconnect email and erase saved
pictures** removes the saved credential and local photo cache; revoke the app
password in Google as well to terminate its account authorization. Upgrading with
the same signing key retains settings; uninstalling removes the private cache.

## Presentation, local choices and delivery policy

**Photo settings** opens the shared Photos category with a return route. Presentation
contains style, speed, shuffle, repeat, favourites-only playback and an Overview
favourite preference. These apply to cached emailed pictures; a shared album uses
Google's player. Open **Settings → Photos → Local picture choices**, select a
picture, and favourite/hide it, choose **Fit** (the default, whole image) or **Fill**,
or add a local caption. Received dates appear there; Skylit does not infer capture
dates or identify people. The photo viewer has only Previous, Play/Pause, Zoom/Fit,
Next and Close, each shown as an icon with an accessible name.

Hidden pictures stay out of every slideshow and Overview. Undo a hide in Photos,
or use **Photo settings → Local picture choices** to show/restore hidden items.
Choices use deduplicated picture IDs and survive refresh/reordering; expired pictures
are pruned from local choices. Changing the Gmail account or erasing/disconnecting
its cache clears choices. These actions never delete email messages.

Delivery's optional trusted-sender list accepts up to 50 exact addresses. When
switched on, all From addresses must match before attachments are saved. Empty or
unknown senders are skipped. Counts are coarse; sender data and email bodies are
not saved with pictures. Changing the rule preserves existing pictures; **Erase
saved pictures only** clears the cache while retaining the connection. Disconnect
also removes the credential. Both erase routes require a second tap; revoke the
app password in Google separately. Connection fields remain empty when reopened.

The new schedule/filter code has automated policy checks and a signed build. Its
real selected-window delivery, failure recovery and long-term pruning still require
physical-frame acceptance; do not describe those as verified from a browser demo.

## Limits and verification

This is a one-way picture importer, not a general email client. It does not send
mail, manage labels or import Google Photos albums. An optional exact-address
sender rule is available; it does not establish cryptographic sender identity.
Checks require network access and may take time in a large inbox. The implementation
limits a pass to 1,000 recent messages, 100 image parts, 12 MiB per source image
and 4 MiB per saved JPEG. It reports a generic network or sign-in error without
logging message contents or credentials. Google can change its IMAP/app-password
support. The downloaded Android mail libraries are pinned and credited in
[credits](credits.md).

Before calling household email delivery verified, test sign-in, a real sent
picture, browser/zoom and slideshow advance, offline playback, idle entry and return
on the physical frame. Age pruning needs a separate aged-message test. A
desktop preview only checks layout and browser logic. See [verification](verification.md).
