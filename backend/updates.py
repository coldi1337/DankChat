"""Read-only release checks against the project's GitHub endpoint."""
import json
from pathlib import Path
import re
import subprocess
import time
import urllib.request

ENDPOINT = 'https://api.github.com/repos/coldi1337/DankChat/releases/latest'
RELEASES = 'https://github.com/coldi1337/DankChat/releases'


def version_tuple(value):
    match = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)', str(value))
    return tuple(map(int, match.groups())) if match else None


class Updates:
    def __init__(self, root, cache):
        self.root, self.cache = Path(root), Path(cache)

    def info(self):
        version = json.loads((self.root / 'plugin.json').read_text())['version']
        info = {'version': version, 'development': False, 'revision': '', 'releasesUrl': RELEASES}
        if (self.root / '.git').exists():
            try:
                def git(*args):
                    return subprocess.run(['git', '-C', str(self.root), *args], capture_output=True, text=True, check=True, timeout=3).stdout.strip()
                info.update(revision=git('rev-parse', '--short', 'HEAD'), development=bool(git('status', '--porcelain', '--untracked-files=normal')))
            except (OSError, subprocess.SubprocessError):
                pass
        return info

    def check(self, force=False):
        info = self.info()
        try:
            data = json.loads(self.cache.read_text())
            if not isinstance(data, dict) or not isinstance(data.get('checkedAt'), (int, float)):
                data = {}
        except (OSError, ValueError):
            data = {}
        if force or not 0 <= time.time() - data.get('checkedAt', 0) < 86400:
            try:
                request = urllib.request.Request(ENDPOINT, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'DankChat/' + info['version']})
                with urllib.request.urlopen(request, timeout=8) as response:
                    payload = json.loads(response.read(1024 * 1024))
                tag = payload.get('tag_name', '')
                if not version_tuple(tag) or payload.get('draft') or payload.get('prerelease'):
                    raise ValueError()
                data = {'latest': tag.lstrip('v'), 'checkedAt': time.time()}
                self.cache.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                temp = self.cache.with_suffix('.tmp'); temp.write_text(json.dumps(data)); temp.replace(self.cache)
            except Exception:
                return {'ok': False, **info, 'error': 'Could not check GitHub for updates. Try again later.'}
        latest = version_tuple(data.get('latest', ''))
        current = version_tuple(info['version'])
        if not latest or not current:
            return {'ok': False, **info, 'error': 'Could not check GitHub for updates. Try again later.'}
        return {'ok': True, **info, **data, 'available': latest > current,
                'releaseUrl': RELEASES + '/tag/v' + data['latest']}
