import asyncio
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from bridge import Telegram, ProviderError
from whatsapp_login import WhatsAppLogin


class AccountTests(unittest.IsolatedAsyncioTestCase):
    async def test_telegram_logout_failure_preserves_session(self):
        account = Telegram()
        account.connect = AsyncMock()
        account.daemon = SimpleNamespace(client=SimpleNamespace(log_out=AsyncMock(return_value=False)))
        with patch('bridge.shutil.rmtree') as remove:
            with self.assertRaises(ProviderError):
                await account.call('logout', {})
            remove.assert_not_called()
        self.assertIsNotNone(account.daemon)

    async def test_telegram_logout_clears_state_only_after_success(self):
        account = Telegram()
        account.connect = AsyncMock()
        account.daemon = SimpleNamespace(client=SimpleNamespace(log_out=AsyncMock(return_value=True)))
        account.downloads['synthetic'] = 'synthetic'
        with patch('bridge.shutil.rmtree') as remove:
            self.assertTrue((await account.call('logout', {}))['ok'])
            remove.assert_called_once()
        self.assertIsNone(account.daemon)
        self.assertEqual(account.downloads, {})

    async def test_whatsapp_qr_rotation_cleanup_and_event_filter(self):
        with TemporaryDirectory() as directory:
            def render(value):
                return SimpleNamespace(save=lambda path: Path(path).write_text(value))
            login = WhatsAppLogin('unused', 'unused', directory, render)
            login.event(json.dumps({'event': 'qr_code', 'data': {'code': 'synthetic-one'}}))
            first = Path(login.qr.path)
            self.assertEqual(first.stat().st_mode & 0o777, 0o600)
            login.event('not-json')
            login.event(json.dumps({'event': 'qr_code', 'data': 'malformed'}))
            self.assertTrue(first.exists())
            login.event(json.dumps({'event': 'qr_code', 'data': {'code': 'synthetic-two'}}))
            self.assertFalse(first.exists())
            login.event(json.dumps({'event': 'connected'}))
            self.assertEqual(login.state, 'authorized')
            self.assertEqual(list(Path(directory).iterdir()), [])
            login.event(json.dumps({'event': 'qr_code', 'data': {'code': 'stale'}}))
            self.assertEqual(login.qr.path, '')

    async def test_whatsapp_cancel_stops_child_and_removes_qr(self):
        with TemporaryDirectory() as directory:
            login = WhatsAppLogin('unused', 'unused', directory, None)
            path = Path(directory) / 'qr.png'; path.write_text('synthetic')
            login.qr.path = str(path)
            login.process = SimpleNamespace(returncode=None, terminate=lambda: None, wait=AsyncMock(return_value=0))
            async def pending():
                try:
                    await asyncio.sleep(100)
                finally:
                    await login.stop_process()
            login.task = asyncio.create_task(pending())
            await asyncio.sleep(0)
            await login.cancel()
            self.assertFalse(path.exists())
            login.process.wait.assert_awaited()
