"""Local account identities; existing sessions retain their original directories."""
import json
import os
from pathlib import Path
import re
import uuid


def validate_id(value):
    if not isinstance(value, str) or (value and not re.fullmatch(r'[a-f0-9]{32}', value)):
        raise ValueError('Invalid account.')
    return value


def instance_key(provider, account=''):
    if provider not in ('telegram', 'whatsapp'):
        raise ValueError('Invalid service.')
    return provider + (':' + validate_id(account) if account else '')


class Accounts:
    def __init__(self, path):
        self.path = Path(path)

    def rows(self):
        try:
            rows = json.loads(self.path.read_text())
        except FileNotFoundError:
            return [{'provider': p, 'id': '', 'label': 'Telegram' if p == 'telegram' else 'WhatsApp'} for p in ('telegram', 'whatsapp')]
        if not isinstance(rows, list) or len(rows) > 20:
            raise ValueError('The account configuration could not be read.')
        keys = set()
        for row in rows:
            key = instance_key(row['provider'], row['id'])
            if key in keys or not isinstance(row['label'], str):
                raise ValueError('The account configuration could not be read.')
            keys.add(key)
        return rows

    def save(self, rows):
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary = self.path.with_suffix('.tmp')
        temporary.write_text(json.dumps(rows)); temporary.chmod(0o600)
        os.replace(temporary, self.path)

    def add(self, provider, label):
        instance_key(provider)
        rows = self.rows()
        if len(rows) >= 20:
            raise ValueError('Up to 20 accounts are supported.')
        row = {'provider': provider, 'id': uuid.uuid4().hex, 'label': self.label(label)}
        self.save(rows + [row])
        return row

    def rename(self, provider, account, label):
        key = instance_key(provider, account); rows = self.rows()
        row = next((r for r in rows if instance_key(r['provider'], r['id']) == key), None)
        if row is None:
            raise ValueError('Invalid account.')
        row['label'] = self.label(label); self.save(rows)

    @staticmethod
    def label(value):
        if not isinstance(value, str) or not value.strip() or len(value.strip()) > 48 or any(ord(c) < 32 for c in value):
            raise ValueError('Enter an account name of up to 48 characters.')
        return value.strip()
