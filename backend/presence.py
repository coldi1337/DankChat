"""Short-lived incoming activity. Never infer presence from message timestamps."""
from contextlib import closing
from pathlib import Path
import sqlite3
import time

TTL = 8


def telegram_status(status):
    kind = type(status).__name__
    if kind == 'UserStatusOnline':
        expiry = int(status.expires.timestamp())
        return {'status': 'online', 'expiresAt': expiry} if expiry > time.time() else {}
    if kind == 'UserStatusOffline':
        return {'status': 'offline', 'lastSeen': int(status.was_online.timestamp())}
    value = {'UserStatusRecently': 'recently', 'UserStatusLastWeek': 'last_week', 'UserStatusLastMonth': 'last_month'}.get(kind)
    return {'status': value} if value else {}


def record_event(path, event):
    chat, sender, state = event.get('Chat'), event.get('Sender'), event.get('State')
    if not all(isinstance(v, str) and 0 < len(v) <= 256 for v in (chat, sender)) or state not in ('composing', 'paused'):
        return False
    now = int(time.time())
    with closing(sqlite3.connect(path)) as db, db:
        db.execute('CREATE TABLE IF NOT EXISTS activity (chat TEXT, sender TEXT, kind TEXT, expires INTEGER, PRIMARY KEY(chat,sender))')
        db.execute('DELETE FROM activity WHERE expires <= ?', (now,))
        if state == 'paused':
            db.execute('DELETE FROM activity WHERE chat=? AND sender=?', (chat, sender))
        else:
            kind = 'recording' if event.get('Media') == 'audio' else 'typing'
            db.execute('INSERT OR REPLACE INTO activity VALUES (?,?,?,?)', (chat, sender, kind, now + TTL))
        db.execute('DELETE FROM activity WHERE rowid IN (SELECT rowid FROM activity ORDER BY expires DESC LIMIT -1 OFFSET 1000)')
    Path(path).chmod(0o600)
    return True


def whatsapp_activity(path, chat):
    if not Path(path).is_file():
        return {}
    try:
        with closing(sqlite3.connect(Path(path).as_uri() + '?mode=ro', uri=True)) as db:
            row = db.execute('SELECT kind,expires FROM activity WHERE chat=? AND expires>? ORDER BY expires DESC LIMIT 1', (chat, int(time.time()))).fetchone()
        return {'activity': row[0], 'activityExpiresAt': row[1]} if row else {}
    except sqlite3.Error:
        return {}
