"""Local, authenticated receipt cache. No message bodies are accepted or stored."""
from contextlib import closing
import hashlib
import hmac
import json
from pathlib import Path
import sqlite3

RANKS = {'delivered': 1, 'read': 2, 'played': 2}


def record(path, payload, signature, secret):
    expected = 'sha256=' + hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(signature, expected):
        return False
    event = json.loads(payload)
    if isinstance(event, dict) and event.get('EventType') == 'chat_presence':
        from presence import record_event
        return record_event(path, event)
    if not isinstance(event, dict) or event.get('EventType') != 'receipt':
        return False
    rank = RANKS.get(event.get('Type'))
    chat = event.get('Chat')
    ids = event.get('MessageIDs')
    if not rank or not isinstance(chat, str) or len(chat) > 256 or not isinstance(ids, list) or len(ids) > 1000:
        return False
    ids = [ident for ident in ids if isinstance(ident, str) and 0 < len(ident) <= 256]
    with closing(sqlite3.connect(path)) as db, db:
        db.execute('CREATE TABLE IF NOT EXISTS receipts (chat TEXT, message TEXT, rank INTEGER, updated INTEGER, PRIMARY KEY(chat,message))')
        db.executemany("INSERT INTO receipts VALUES (?, ?, ?, unixepoch()) ON CONFLICT(chat,message) DO UPDATE SET rank=MAX(rank,excluded.rank), updated=excluded.updated", [(chat, ident, rank) for ident in ids])
        db.execute('DELETE FROM receipts WHERE rowid IN (SELECT rowid FROM receipts ORDER BY updated DESC LIMIT -1 OFFSET 50000)')
    Path(path).chmod(0o600)
    return True


def apply(path, chat, rows):
    if not Path(path).is_file():
        return
    try:
        with closing(sqlite3.connect(Path(path).as_uri() + '?mode=ro', uri=True)) as db:
            known = dict(db.execute('SELECT message, rank FROM receipts WHERE chat=?', (chat,)))
        for row in rows:
            if not row.get('from_me'):
                continue
            rank = known.get(str(row.get('id')))
            if rank:
                row['delivery_status'] = 'read' if rank >= 2 else 'delivered'
                row['delivery_partial'] = chat.endswith('@g.us')
    except sqlite3.Error:
        pass
