"""Regression tests for the v0.5.1 review: refresh load, read state, previews and hardening."""
import asyncio
import io
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
import bridge
from bridge import Bridge, Telegram, WhatsApp, ProviderError
import sent_messages
from sent_messages import SentMessages
import whatsapp_sync
from whatsapp_login import WhatsAppLogin


def dialog(ident):
    return {'id': ident, 'title': 'Synthetic ' + str(ident), 'unread_count': 0, 'last_message': {}}


def telegram(rows):
    provider = Telegram()
    provider.connect = AsyncMock()
    refresh = AsyncMock(side_effect=lambda limit, raise_errors=False: list(rows))
    client = SimpleNamespace(is_user_authorized=AsyncMock(return_value=True), send_read_acknowledge=AsyncMock())
    provider.daemon = SimpleNamespace(client=client, dialogs_cache=[], messages_cache={}, refresh_dialogs_cache=refresh)
    return provider, refresh


class TelegramChatListTests(unittest.IsolatedAsyncioTestCase):
    async def test_write_invalidates_chat_list_after_a_concurrent_refresh(self):
        provider, refresh = telegram([dialog(1)])
        await provider.call('chats', {})
        started, finish = asyncio.Event(), asyncio.Event()
        async def read(*args, **kwargs):
            started.set()
            await finish.wait()
        provider.daemon.client.send_read_acknowledge.side_effect = read
        work = asyncio.create_task(provider.call('read', {'chat': {'id': '1'}, 'messageId': '5'}))
        await started.wait()
        provider.chats_fetched -= bridge.CHATS_MAX_AGE
        await provider.call('chats', {})
        self.assertFalse(provider.dialogs_dirty)
        finish.set()
        await work
        self.assertTrue(provider.dialogs_dirty)

    async def test_cancelled_chat_fetch_remains_dirty(self):
        provider, refresh = telegram([dialog(1)])
        await provider.call('chats', {})
        provider.dialogs_dirty = True
        provider.chats_fetched -= bridge.CHATS_MIN_INTERVAL
        refresh.side_effect = asyncio.CancelledError()
        with self.assertRaises(asyncio.CancelledError):
            await provider.call('chats', {})
        self.assertTrue(provider.dialogs_dirty)

    async def test_chat_list_is_served_from_cache_until_an_update_or_write(self):
        provider, refresh = telegram([dialog(1), dialog(2)])
        first = await provider.call('chats', {})
        self.assertEqual([row['id'] for row in first['chats']], ['1', '2'])
        self.assertTrue(first['checkedAt'] > 0)
        await provider.call('chats', {})
        self.assertEqual(refresh.await_count, 1)
        refresh.assert_awaited_with(200, raise_errors=True)
        # An update marks the list dirty, but full fetches stay rate-limited.
        provider.dialogs_dirty = True
        await provider.call('chats', {})
        self.assertEqual(refresh.await_count, 1)
        provider.chats_fetched -= bridge.CHATS_MIN_INTERVAL
        await provider.call('chats', {})
        self.assertEqual(refresh.await_count, 2)
        # Writes invalidate the cached list as well.
        await provider.call('read', {'chat': {'id': '1'}, 'messageId': '5'})
        self.assertTrue(provider.dialogs_dirty)
        # Without updates, the list is still refetched periodically.
        provider.dialogs_dirty = False
        provider.chats_fetched -= bridge.CHATS_MAX_AGE
        await provider.call('chats', {})
        self.assertEqual(refresh.await_count, 3)

    async def test_failed_refresh_is_reported_instead_of_stale_success(self):
        provider, refresh = telegram([])
        refresh.side_effect = RuntimeError('flood wait')
        with self.assertRaisesRegex(ProviderError, 'could not be refreshed'):
            await provider.call('chats', {})
        self.assertTrue(provider.dialogs_dirty)
        with self.assertRaisesRegex(ProviderError, 'could not be refreshed'):
            await provider.call('chats', {})
        self.assertEqual(refresh.await_count, 1)
        provider.chats_retry_at = 0
        refresh.side_effect = None; refresh.return_value = []
        self.assertTrue((await provider.call('chats', {}))['ok'])

    async def test_flood_wait_is_respected_between_chat_refreshes(self):
        provider, refresh = telegram([])
        failure = RuntimeError('rate limited'); failure.seconds = 120
        refresh.side_effect = failure
        with self.assertRaises(ProviderError): await provider.call('chats', {})
        self.assertGreater(provider.chats_retry_at - __import__('time').monotonic(), 119)

    async def test_known_chats_survive_a_shrunken_dialog_cache(self):
        provider, _ = telegram([dialog(i) for i in range(1, 61)])
        await provider.call('chats', {})
        # The vendored client may refresh its cache with a smaller limit.
        provider.daemon.dialogs_cache = [{'id': i} for i in range(1, 41)]
        await provider.call('read', {'chat': {'id': '55'}, 'messageId': '7'})
        provider.daemon.client.send_read_acknowledge.assert_awaited_once_with(55, max_id=7)
        with self.assertRaisesRegex(ProviderError, 'existing Telegram chat'):
            await provider.call('read', {'chat': {'id': '999'}, 'messageId': '7'})

    async def test_updates_name_the_account_and_chat(self):
        events = []
        instance = Bridge.__new__(Bridge)
        instance.providers = {}
        instance.on_event = events.append
        account = 'a' * 32
        provider = instance.make_provider('telegram', account)
        provider.on_update('-100123')
        self.assertEqual(events, [{'event': 'provider_changed', 'provider': 'telegram', 'account': account, 'chat': '-100123'}])

    async def test_telegram_event_marks_list_dirty_and_passes_chat(self):
        handlers = []
        class Read:
            def __init__(self, inbox=False): self.inbox = inbox
        class Client:
            connect = AsyncMock()
            def on(self, event):
                def decorate(handler): handlers.append(handler); return handler
                return decorate
        events = SimpleNamespace(MessageRead=Read, NewMessage=object(), MessageEdited=object(), MessageDeleted=object(), UserUpdate=object())
        daemon = SimpleNamespace(client=Client(), messages_cache={})
        provider = Telegram(); provider.on_update = Mock(); provider.dialogs_dirty = False
        with patch.dict(sys.modules, {'telethon': SimpleNamespace(events=events), 'qrcode': SimpleNamespace()}), patch('bridge.load_module', return_value=SimpleNamespace(TelegramBackend=lambda: daemon)):
            await provider.connect()
        await handlers[0](SimpleNamespace(chat_id=-100123))
        provider.on_update.assert_called_once_with('-100123')
        self.assertTrue(provider.dialogs_dirty)


class TelegramUpdateTests(unittest.IsolatedAsyncioTestCase):
    async def connect(self):
        handlers = []
        class Read:
            def __init__(self, inbox=False): self.inbox = inbox
        class Raw:
            def __init__(self, types=None): self.types = types
        class Client:
            connect = AsyncMock()
            def on(self, event):
                def decorate(handler): handlers.append((event, handler)); return handler
                return decorate
        class Reactions:
            pass
        events = SimpleNamespace(MessageRead=Read, Raw=Raw, NewMessage=object(), MessageEdited=object(), MessageDeleted=object(), UserUpdate=object())
        daemon = SimpleNamespace(client=Client(), messages_cache={'1_0': []}, dialogs_cache=[{'id': -100123, 'read_outbox_max_id': 5}])
        provider = Telegram(); provider.on_update = Mock()
        modules = {'telethon': SimpleNamespace(events=events), 'qrcode': SimpleNamespace(),
                   'telethon.tl.types': SimpleNamespace(UpdateMessageReactions=Reactions),
                   'telethon.utils': SimpleNamespace(get_peer_id=lambda peer: peer)}
        with patch.dict(sys.modules, modules), patch('bridge.load_module', return_value=SimpleNamespace(TelegramBackend=lambda: daemon)):
            await provider.connect()
        return provider, daemon, handlers, Reactions

    async def test_message_cache_lives_longer_because_updates_clear_it(self):
        _, daemon, _, _ = await self.connect()
        self.assertEqual(daemon.messages_cache_ttl, bridge.MESSAGES_CACHE_TTL)

    async def test_reactions_by_others_refresh_the_conversation(self):
        provider, daemon, handlers, Reactions = await self.connect()
        raw = next((event, handler) for event, handler in handlers if getattr(event, 'types', None))
        self.assertEqual(raw[0].types, [Reactions])
        await raw[1](SimpleNamespace(peer=-100123))
        self.assertFalse(daemon.messages_cache)
        provider.on_update.assert_called_once_with('-100123')

    async def test_outbox_read_updates_delivery_state_before_reload(self):
        provider, daemon, handlers, _ = await self.connect()
        await handlers[0][1](SimpleNamespace(chat_id=-100123, outbox=True, max_id=9))
        self.assertEqual(daemon.dialogs_cache[0]['read_outbox_max_id'], 9)
        await handlers[0][1](SimpleNamespace(chat_id=-100123, outbox=True, max_id=7))
        self.assertEqual(daemon.dialogs_cache[0]['read_outbox_max_id'], 9)


class StagingCleanupTests(unittest.TestCase):
    def test_interrupted_download_stages_are_removed_after_an_hour(self):
        from storage import Storage
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory); media = base / 'cache/telegram/media'; media.mkdir(parents=True)
            old, fresh = media / '.download-old', media / '.download-new'
            old.mkdir(); fresh.mkdir(); (old / 'media').write_bytes(b'partial')
            os.utime(old, (0, 0))
            outside = base / 'outside'; outside.mkdir(); os.utime(outside, (0, 0))
            (media / '.download-link').symlink_to(outside)
            Storage(base / 'cache', base / 'state').clean()
            self.assertFalse(old.exists()); self.assertTrue(fresh.exists()); self.assertTrue(outside.exists())

class WhatsAppStatusTests(unittest.IsolatedAsyncioTestCase):
    async def test_logout_waits_for_an_upload_after_its_request_times_out(self):
        provider, _ = self.provider()
        release, started = asyncio.Event(), asyncio.Event()
        calls = []
        async def action(name, data):
            calls.append(name)
            if name == 'file':
                started.set()
                await release.wait()
            return {'ok': True}
        provider._call = action
        upload = asyncio.create_task(provider.call('file', {}))
        await started.wait()
        upload.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await upload
        logout = asyncio.create_task(provider.call('logout', {}))
        for _ in range(4): await asyncio.sleep(0)
        self.assertEqual(calls, ['file'])
        release.set()
        await logout
        self.assertEqual(calls, ['file', 'logout'])

    async def test_close_waits_for_a_detached_upload_before_cleaning_previews(self):
        provider, _ = self.provider()
        release, started = asyncio.Event(), asyncio.Event()
        async def action(name, data):
            started.set()
            await release.wait()
            return {'ok': True}
        provider._call = action
        provider.sent.close = Mock()
        upload = asyncio.create_task(provider.call('file', {}))
        await started.wait()
        upload.cancel()
        with self.assertRaises(asyncio.CancelledError): await upload
        close = asyncio.create_task(provider.close())
        for _ in range(4): await asyncio.sleep(0)
        provider.sent.close.assert_not_called()
        provider.sync.assert_not_called()
        release.set()
        await close
        provider.sent.close.assert_called_once()
        self.assertEqual(provider.maintenance, 0)

    async def test_cancelled_queued_write_never_runs_later(self):
        provider, _ = self.provider()
        provider._call = AsyncMock(return_value={'ok': True})
        await provider.write_lock.acquire()
        work = asyncio.create_task(provider.call('send', {}))
        for _ in range(4): await asyncio.sleep(0)
        work.cancel()
        with self.assertRaises(asyncio.CancelledError): await work
        provider.write_lock.release()
        for _ in range(4): await asyncio.sleep(0)
        provider._call.assert_not_called()
        self.assertFalse(provider.write_tasks)

    async def test_reconfigure_keeps_clipboard_until_detached_upload_finishes(self):
        provider, _ = self.provider()
        release, started = asyncio.Event(), asyncio.Event()
        async def action(name, data):
            started.set()
            await release.wait()
            return {'ok': True}
        provider._call = action
        upload = asyncio.create_task(provider.call('file', {}))
        await started.wait()
        upload.cancel()
        with self.assertRaises(asyncio.CancelledError): await upload
        instance = Bridge.__new__(Bridge)
        instance.providers = {'whatsapp': provider}
        instance.accounts = SimpleNamespace(rows=lambda: [{'provider': 'whatsapp', 'id': ''}])
        instance.clipboard = SimpleNamespace(close=Mock())
        instance.voice = SimpleNamespace(discard=AsyncMock())
        configure = asyncio.create_task(instance.dispatch({'action': 'configure', 'enabled': ['whatsapp']}))
        for _ in range(4): await asyncio.sleep(0)
        instance.clipboard.close.assert_not_called()
        release.set()
        await configure
        instance.clipboard.close.assert_called_once()

    def provider(self, sync_active=True):
        provider = WhatsApp(); provider.binary = Path(__file__); provider.version_checked = True
        backend = SimpleNamespace(status=Mock(return_value={'ok': True, 'authenticated': True, 'online': True, 'sync_active': sync_active}))
        provider.backend = Mock(return_value=backend)
        provider.sync = AsyncMock()
        return provider, backend

    async def test_health_check_is_cached_and_invalidated_by_writes(self):
        provider, backend = self.provider()
        with patch('pathlib.Path.exists', return_value=True):
            for _ in range(3):
                self.assertTrue((await provider.status())['authorized'])
            self.assertEqual(backend.status.call_count, 1)
            provider._call = AsyncMock(return_value={'ok': True})
            await provider.call('pin', {})
            await provider.status()
            self.assertEqual(backend.status.call_count, 2)

    async def test_inactive_sync_is_rechecked_sooner(self):
        provider, backend = self.provider(sync_active=False)
        with patch('pathlib.Path.exists', return_value=True):
            await provider.status()
        self.assertLessEqual(provider.status_cache[0] - __import__('time').monotonic(), bridge.STATUS_RETRY_TTL)

    async def test_timed_out_write_keeps_maintenance_until_the_work_ends(self):
        provider, _ = self.provider()
        release = asyncio.Event()
        async def slow(action, data):
            await release.wait()
            return {'ok': True}
        provider._call = slow
        provider.on_update = Mock()
        with self.assertRaises(asyncio.TimeoutError):
            await asyncio.wait_for(provider.call('send', {'chat': {'id': 'jid'}}), 0.05)
        # The worker thread cannot be stopped; sync must not restart meanwhile.
        self.assertEqual(provider.maintenance, 1)
        release.set()
        for _ in range(5):
            await asyncio.sleep(0)
        self.assertEqual(provider.maintenance, 0)
        provider.on_update.assert_called_once_with('jid')


class SentPreviewBudgetTests(unittest.TestCase):
    def test_previews_share_one_budget_across_accounts(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(sent_messages, 'MAX_BYTES', 25):
            base = Path(directory); source = base / 'file.bin'; source.write_bytes(b'0123456789')
            one, two = SentMessages(base / 'sent'), SentMessages(base / 'sent')
            first = one.remember('telegram', {'id': 'a', 'account': ''}, {'message_id': 1}, {'path': str(source)})
            two.remember('telegram', {'id': 'b', 'account': 'x'}, {'message_id': 2}, {'path': str(source)})
            three = two.remember('telegram', {'id': 'b', 'account': 'x'}, {'message_id': 3}, {'path': str(source)})
            # The oldest preview of another account is evicted first.
            self.assertFalse(Path(first['mediaPath']).exists())
            self.assertFalse(one.entries)
            self.assertTrue(Path(three['mediaPath']).exists())
            self.assertTrue(three['mediaPath'].startswith(str(base / 'sent')))
            one.close(); two.close()

    def test_bridge_keeps_previews_out_of_the_runtime_directory(self):
        self.assertEqual(bridge.SENT, bridge.CACHE / 'sent')
        self.assertEqual(Telegram().sent.root, bridge.SENT)


class WebhookPeerTests(unittest.TestCase):
    def test_peer_owner_is_read_from_the_socket_table(self):
        table = ('  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n'
                 '   0: 0100007F:1F90 0100007F:A000 01 00000000:00000000 00:00000000 00000000  1000        0 1 1\n')
        with tempfile.NamedTemporaryFile('w') as handle:
            handle.write(table); handle.flush()
            destination = ('127.0.0.1', 0xA000)
            self.assertEqual(whatsapp_sync.peer_uid(('127.0.0.1', 0x1F90), destination, handle.name), 1000)
            self.assertIsNone(whatsapp_sync.peer_uid(('127.0.0.1', 1), destination, handle.name))
            self.assertIsNone(whatsapp_sync.peer_uid(('10.0.0.1', 0x1F90), destination, handle.name))
            self.assertIsNone(whatsapp_sync.peer_uid(('127.0.0.1', 0x1F90), ('127.0.0.1', 1), handle.name))

    def test_own_loopback_connection_is_recognized(self):
        import socket
        server = socket.socket(); server.bind(('127.0.0.1', 0)); server.listen(1)
        client = socket.create_connection(server.getsockname())
        peer, address = server.accept()
        try:
            self.assertEqual(whatsapp_sync.peer_uid(address, server.getsockname()), os.getuid())
        finally:
            peer.close(); client.close(); server.close()


class LoginTimeoutTests(unittest.IsolatedAsyncioTestCase):
    async def test_expired_whatsapp_login_is_reported_as_expired(self):
        login = WhatsAppLogin('/bin/true', '/tmp', tempfile.gettempdir(), None)
        with patch('asyncio.create_subprocess_exec', AsyncMock(side_effect=asyncio.TimeoutError())):
            await login.run()
        self.assertEqual(login.state, 'expired')


class BridgeLockTests(unittest.IsolatedAsyncioTestCase):
    async def test_second_bridge_reports_a_busy_predecessor(self):
        import fcntl
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            paths = {name: base / name for name in ('STATE', 'CACHE', 'CONFIG', 'RUNTIME')}
            paths['RUNTIME'].mkdir(mode=0o700)
            holder = (paths['RUNTIME'] / 'bridge.lock').open('w')
            fcntl.flock(holder, fcntl.LOCK_EX)
            output = io.StringIO()
            try:
                with patch.multiple(bridge, LOCK_WAIT=0.3, **paths), patch.object(sys, 'stdout', output):
                    self.assertEqual(await bridge.main(), 1)
            finally:
                holder.close()
            self.assertEqual(json.loads(output.getvalue()), {'event': 'bridge_busy'})


class TranslationCoverageTests(unittest.TestCase):
    def test_backend_errors_and_ui_strings_have_german_translations(self):
        german = json.loads((ROOT / 'translations/de.json').read_text())
        strings = set()
        for path in ROOT.glob('*.qml'):
            strings |= set(re.findall(r'trFor\("dankChat",\s*"((?:[^"\\]|\\.)*)"\)', path.read_text()))
        for path in [*ROOT.glob('backend/*.py')]:
            text = path.read_text()
            strings |= set(re.findall(r'ProviderError\(\s*"((?:[^"\\]|\\.)*)"\s*\)', text))
            strings |= set(re.findall(r"raise ValueError\(\s*'((?:[^'\\]|\\.)*)'\s*\)", text))
            strings |= set(re.findall(r'"error": "((?:[^"\\]|\\.)*)"', text))
        strings |= set(re.findall(r'error = "((?:[^"\\]|\\.)*)"', (ROOT / 'backend/bridge.py').read_text()))
        missing = sorted(value for value in strings if value not in german)
        self.assertEqual(missing, [])


if __name__ == '__main__':
    unittest.main()
