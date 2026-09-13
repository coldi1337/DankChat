import hashlib
import hmac
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from receipts import record, apply


class ReceiptTests(unittest.TestCase):
    def test_authenticated_receipts_never_downgrade_or_mark_incoming(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'receipts.sqlite'
            def event(kind, signature=True):
                body = json.dumps({'EventType': 'receipt', 'Chat': 'synthetic@g.us', 'MessageIDs': ['one'], 'Type': kind}).encode()
                sig = 'sha256=' + hmac.new(b'test-secret', body, hashlib.sha256).hexdigest() if signature else 'bad'
                return record(path, body, sig, 'test-secret')
            self.assertFalse(event('read', False))
            self.assertFalse(path.exists())
            self.assertTrue(event('read'))
            self.assertTrue(event('delivered'))
            rows = [{'id': 'one', 'from_me': True}, {'id': 'one', 'from_me': False}, {'id': 'old', 'from_me': True}]
            apply(path, 'synthetic@g.us', rows)
            self.assertEqual(rows[0]['delivery_status'], 'read')
            self.assertTrue(rows[0]['delivery_partial'])
            self.assertNotIn('delivery_status', rows[1])
            self.assertNotIn('delivery_status', rows[2])
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            unrelated = [{'id': 'one', 'from_me': True}]
            apply(path, 'different', unrelated)
            self.assertNotIn('delivery_status', unrelated[0])
