"""Manage only downloaded media, never account databases or user originals."""
from pathlib import Path
import shutil
import time

STAGING_AGE = 3600


class Storage:
    def __init__(self, cache, state):
        self.cache, self.state = Path(cache), Path(state)

    def roots(self):
        roots = [self.cache / 'telegram/media', self.state / 'whatsapp/helper/media-downloads']
        roots += list((self.cache / 'telegram').glob('*/media'))
        roots += list((self.state / 'whatsapp').glob('*/helper/media-downloads'))
        return roots

    def files(self):
        files = []
        for root in self.roots():
            if root.is_symlink():
                continue
            for path in root.glob('*'):
                if path.is_file() and not path.is_symlink():
                    try:
                        stat = path.stat(); files.append((path, stat.st_size, stat.st_mtime))
                    except OSError:
                        pass
        return files

    def info(self):
        rows = self.files()
        return {'ok': True, 'bytes': sum(row[1] for row in rows), 'files': len(rows)}

    def stale_staging(self):
        """Partial downloads left behind by an interrupted bridge."""
        stale = []
        for root in self.roots():
            if root.is_symlink() or not root.is_dir():
                continue
            for path in root.glob('.download-*'):
                try:
                    if path.is_dir() and not path.is_symlink() and path.stat().st_mtime < time.time() - STAGING_AGE:
                        stale.append(path)
                except OSError:
                    pass
        return stale

    def clean(self, limit_mb=512, days=30, clear=False, protect=()):
        for path in self.stale_staging():
            shutil.rmtree(path, ignore_errors=True)
        rows = sorted(self.files(), key=lambda row: row[2]); total = sum(r[1] for r in rows)
        protected = {str(Path(p)) for p in protect if p}
        removed = 0
        for path, size, modified in rows:
            if str(path) in protected or (not clear and total <= limit_mb * 1048576 and modified >= time.time() - days * 86400):
                continue
            try:
                path.unlink(); total -= size; removed += 1
            except OSError:
                pass
        return {**self.info(), 'removed': removed}
