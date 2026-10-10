"""Stage only reviewed dashboard files; personal configuration is opt-in."""
from pathlib import Path
import shutil

PUBLIC_ASSETS = ('suncalc.js', 'suncalc-LICENSE.txt', 'appearance.js', 'overview-model.js', 'index.html', 'app.js', 'photos-model.js', 'photos.js', 'style.css', 'momo.js', 'momo-routine.js', 'ical.js', 'ical-LICENSE.txt', 'calendar-model.js', 'calendar-policy.js', 'calendar-worker.js', 'calendar.js')
MAIL_NOTICES = tuple(f'assets/{artifact}-{notice}' for artifact in ('android-mail-1.6.7','android-activation-1.6.7') for notice in ('LICENSE.md','NOTICE.md'))
EMPTY_CONFIG = 'window.SKYLIT_LOCAL = {};\n'


def stage_assets(source, destination, personal=False):
    source, destination = Path(source), Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    for name in PUBLIC_ASSETS:
        shutil.copyfile(source / name, destination / name)
    local = source / 'local-config.js'
    if personal and local.exists():
        shutil.copyfile(local, destination / 'local-config.js')
    else:
        (destination / 'local-config.js').write_text(EMPTY_CONFIG)
