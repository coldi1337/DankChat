"""Locate a DMS source tree without starting or changing the running shell."""
import os
from pathlib import Path


def find_source(environ=None, system_source=Path('/usr/share/quickshell/dms')):
    env = os.environ if environ is None else environ
    configured = env.get('DANKCHAT_DMS_SOURCE')
    if configured:
        path = Path(configured).expanduser()
        candidates = [path.parent if path.name == 'shell.qml' else path]
    else:
        runtime = Path(env.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
        shells = []
        for name in ('dms-shell', 'danklinux-shell'):
            for path in (runtime / name).glob('*/shell.qml'):
                try:
                    shells.append((path.stat().st_mtime_ns, path))
                except OSError:
                    # A runtime extraction may disappear while DMS restarts.
                    continue
        candidates = [path.parent for _, path in sorted(shells, reverse=True)]
        candidates.append(Path(system_source))
    return next((path for path in candidates
                 if (path / 'shell.qml').is_file() and (path / 'Widgets').is_dir()), None)
