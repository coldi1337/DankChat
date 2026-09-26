import asyncio
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from request_runner import RequestRunner
from bridge import Telegram
from model import chat


class SyncTests(unittest.IsolatedAsyncioTestCase):
    async def test_clipboard_and_reads_complete_during_a_slow_download(self):
        runner = RequestRunner()
        entered, release = asyncio.Event(), asyncio.Event()
        async def dispatch(request):
            if request['action'] == 'download':
                entered.set(); await release.wait()
            return {'ok': True}
        download = asyncio.create_task(runner.run({'provider': 'telegram', 'action': 'download'}, dispatch))
        await entered.wait()
        try:
            for action in ['clipboard_image', 'chats', 'presence']:
                self.assertTrue((await asyncio.wait_for(runner.run({'provider': 'telegram', 'action': action}, dispatch), .5))['ok'])
            self.assertFalse(download.done())
        finally:
            release.set(); await download

    async def test_logout_waits_for_transfer_and_diagnostics_omit_content(self):
        runner = RequestRunner()
        entered, release = asyncio.Event(), asyncio.Event()
        calls = []
        async def dispatch(request):
            calls.append(request['action'])
            if request['action'] == 'download': entered.set(); await release.wait()
            return {'ok': True}
        download = asyncio.create_task(runner.run({'provider': 'whatsapp', 'action': 'download', 'chat': 'PRIVATE'}, dispatch))
        await entered.wait()
        logout = asyncio.create_task(runner.run({'provider': 'whatsapp', 'action': 'logout', 'text': 'SECRET'}, dispatch))
        await asyncio.sleep(.02)
        self.assertEqual(calls, ['download'])
        release.set(); await asyncio.gather(download, logout)
        self.assertEqual(calls, ['download', 'logout'])
        self.assertNotIn('PRIVATE', str(runner.diagnostics)); self.assertNotIn('SECRET', str(runner.diagnostics))
        for row in runner.diagnostics: self.assertEqual(set(row), {'provider', 'action', 'outcome', 'durationMs'})

    async def test_telegram_subscribes_to_reads_from_own_other_clients(self):
        handlers = []
        class Read:
            def __init__(self, inbox=False): self.inbox = inbox
        class Client:
            connect = AsyncMock()
            disconnect = AsyncMock()
            def on(self, event):
                def decorate(handler): handlers.append((event, handler)); return handler
                return decorate
        events = SimpleNamespace(MessageRead=Read, NewMessage=object(), MessageEdited=object(), MessageDeleted=object(), UserUpdate=object())
        daemon = SimpleNamespace(client=Client(), messages_cache={'old': []})
        provider = Telegram(); provider.on_update = Mock()
        with patch.dict(sys.modules, {'telethon': SimpleNamespace(events=events), 'qrcode': SimpleNamespace()}), patch('bridge.load_module', return_value=SimpleNamespace(TelegramBackend=lambda: daemon)):
            await provider.connect()
        read_handlers = [(event, handler) for event, handler in handlers if isinstance(event, Read)]
        self.assertEqual({event.inbox for event, _ in read_handlers}, {True, False})
        for event, handler in read_handlers:
            await handler(SimpleNamespace(inbox=event.inbox))
        self.assertFalse(daemon.messages_cache)
        self.assertEqual(provider.on_update.call_count, 2)

    def test_whatsapp_other_client_read_overrides_local_notification_snapshot(self):
        raw = {'jid': 'synthetic', 'unread': 4, 'notification_unread': 0, 'muted': True}
        self.assertEqual(chat('whatsapp', raw)['unread'], 0)
        raw.update(unread=0, notification_unread=4)
        self.assertEqual(chat('whatsapp', raw)['unread'], 0)

    def test_whatsapp_badge_tracks_dismissal_new_messages_and_remote_read(self):
        raw = {'jid': 'synthetic', 'unread': 3, 'notification_unread': 3}
        self.assertEqual(chat('whatsapp', raw)['unread'], 3)
        raw['notification_unread'] = 0
        self.assertEqual(chat('whatsapp', raw)['unread'], 0)
        raw.update(unread=4, notification_unread=1)
        self.assertEqual(chat('whatsapp', raw)['unread'], 1)
        raw['unread'] = 0
        self.assertEqual(chat('whatsapp', raw)['unread'], 0)

    def test_whatsapp_badge_without_notification_metadata_uses_server_unread(self):
        self.assertEqual(chat('whatsapp', {'jid': 'synthetic', 'unread': 2})['unread'], 2)
