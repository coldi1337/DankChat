"""Immediate, confirmed send results with private previews independent of clipboard cleanup."""
from collections import OrderedDict
from datetime import datetime
import mimetypes
from pathlib import Path
import shutil
import tempfile
import time
import threading
import weakref
from functools import wraps

# Every account keeps its own entries, but the preview copies share one budget:
# a limit per account would multiply with each added account.
MAX_ENTRIES = 128
MAX_BYTES = 256 * 1024 * 1024
LOCK = threading.RLock()
INSTANCES = weakref.WeakSet()


def synchronized(fn):
    @wraps(fn)
    def wrapped(self, *args, **kwargs):
        with LOCK:
            return fn(self, *args, **kwargs)
    return wrapped


def preview_size(row):
    path = row['mediaPath']
    try:
        return Path(path).stat().st_size if path else 0
    except OSError:
        return 0


from model import message


class SentMessages:
    def __init__(self, root):
        self.root = Path(root)
        self.lock = LOCK
        self.directory = None
        self.entries = OrderedDict()
        INSTANCES.add(self)

    @synchronized
    def remember(self, provider, target, result, request):
        item = (result.get('items') or [result])[0]
        ident = item.get('message_id') if provider == 'telegram' else item.get('id')
        if not isinstance(ident, (str, int)) or not str(ident):
            return None
        ident = str(ident)
        key = (str(target.get('account', '')), str(target['id']), ident)
        path = request.get('path', '')
        mime = item.get('mime_type') or mimetypes.guess_type(path)[0] or ''
        kind = item.get('media_type') or ('image' if mime.startswith('image/') else 'video' if mime.startswith('video/') else 'audio' if mime.startswith('audio/') else 'document') if path else ''
        preview = ''
        if path:
            # Preview caching must never turn a confirmed send into a failure.
            try:
                if self.directory is None:
                    self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
                    self.directory = tempfile.TemporaryDirectory(prefix='sent-', dir=self.root)
                with tempfile.NamedTemporaryFile(dir=self.directory.name, suffix=Path(path).suffix, delete=False) as output:
                    preview = output.name
                    with open(path, 'rb') as source:
                        shutil.copyfileobj(source, output)
            except OSError:
                if preview:
                    Path(preview).unlink(missing_ok=True)
                preview = ''
        now = time.time()
        row = message(provider, {'id': ident, 'text': request.get('text', ''),
            'out': True, 'from_me': True, 'timestamp': now, 'time': datetime.fromtimestamp(now).strftime('%H:%M'),
            'media_type': kind, 'mime_type': mime, 'filename': Path(path).name if path else '',
            'media_path': preview, 'local_path': preview,
            'reply_to_msg_id': request.get('replyId', ''), 'quoted_id': request.get('replyId', '')})
        self.entries[key] = (row, now)
        self.entries.move_to_end(key)
        self._evict(row)
        return row

    @staticmethod
    def _evict(newest):
        """Bound memory and private disk copies across all accounts; keep the newest result."""
        while True:
            owners = [cache for cache in list(INSTANCES) if cache.entries]
            count = sum(len(cache.entries) for cache in owners)
            size = sum(preview_size(row) for cache in owners for row, _ in cache.entries.values())
            if count <= MAX_ENTRIES and size <= MAX_BYTES:
                return
            candidates = [(next(iter(cache.entries.values()))[1], cache) for cache in owners
                          if next(iter(cache.entries.values()))[0] is not newest]
            if not candidates:
                return
            _, cache = min(candidates, key=lambda item: item[0])
            _, (old, _) = cache.entries.popitem(last=False)
            if old['mediaPath']:
                Path(old['mediaPath']).unlink(missing_ok=True)

    @synchronized
    def merge(self, target, rows, include_pending=True):
        result = [dict(row) for row in rows]
        indexed = {row['id']: row for row in result}
        prefix = (str(target.get('account', '')), str(target['id']))
        for key, (sent, created) in list(self.entries.items()):
            if key[:2] != prefix:
                continue
            current = indexed.get(key[2])
            if current is not None:
                if not current.get('mediaPath') and sent['mediaPath'] and Path(sent['mediaPath']).is_file():
                    current['mediaPath'] = sent['mediaPath']
            elif include_pending and time.time() - created < 120:
                result.append(dict(sent))
        return sorted(result, key=lambda row: row['timestamp'])

    @synchronized
    def forget(self, target, ident):
        entry = self.entries.pop((str(target.get('account', '')), str(target['id']), str(ident)), None)
        if entry and entry[0]['mediaPath']:
            Path(entry[0]['mediaPath']).unlink(missing_ok=True)

    @synchronized
    def close(self):
        self.entries.clear()
        if self.directory:
            self.directory.cleanup()
            self.directory = None
