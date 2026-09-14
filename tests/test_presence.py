import hashlib
import hmac
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from datetime import datetime, timezone
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from presence import telegram_status, whatsapp_activity
from receipts import record

class PresenceTests(unittest.TestCase):
    def test_telegram_exact_coarse_and_hidden_status(self):
        def status(kind, **attrs): return type(kind, (), attrs)()
        with patch('presence.time.time', return_value=100):
            self.assertEqual(telegram_status(status('UserStatusOnline', expires=datetime.fromtimestamp(110,timezone.utc))), {'status':'online','expiresAt':110})
            self.assertEqual(telegram_status(status('UserStatusOnline', expires=datetime.fromtimestamp(90,timezone.utc))), {})
        self.assertEqual(telegram_status(status('UserStatusRecently')), {'status':'recently'})
        self.assertEqual(telegram_status(status('UserStatusLastWeek')), {'status':'last_week'})
        self.assertEqual(telegram_status(status('UserStatusLastMonth')), {'status':'last_month'})
        self.assertEqual(telegram_status(None), {})
        self.assertEqual(telegram_status(status('UserStatusOffline',was_online=datetime.fromtimestamp(80,timezone.utc)))['lastSeen'],80)

    def test_signed_typing_pause_actor_isolation_expiry_and_no_fake_online(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'events.sqlite'
            def event(sender='one', state='composing', media='', valid=True):
                body=json.dumps({'EventType':'chat_presence','Chat':'group','Sender':sender,'State':state,'Media':media}).encode()
                signature='sha256='+hmac.new(b'secret',body,hashlib.sha256).hexdigest() if valid else 'bad'
                return record(path,body,signature,'secret')
            with patch('presence.time.time',return_value=100):
                self.assertFalse(event(valid=False)); self.assertFalse(path.exists())
                self.assertTrue(event()); self.assertEqual(whatsapp_activity(path,'group')['activity'],'typing')
                self.assertEqual(whatsapp_activity(path,'other'), {})
                self.assertNotIn('lastSeen',whatsapp_activity(path,'group'))
                self.assertTrue(event('two',media='audio'))
                self.assertTrue(event('one',state='paused'))
                self.assertEqual(whatsapp_activity(path,'group')['activity'],'recording')
                self.assertFalse(event(state='unknown'))
            with patch('presence.time.time',return_value=109): self.assertEqual(whatsapp_activity(path,'group'),{})
