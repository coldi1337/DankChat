from pathlib import Path
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from bridge import Bridge, Telegram, WhatsApp, ProviderError


class Channel: pass


class DeletionTests(unittest.IsolatedAsyncioTestCase):
    async def test_scope_and_chat_are_required(self):
        bridge = Bridge()
        provider = AsyncMock()
        bridge.providers['telegram'] = provider
        valid = dict(provider='telegram', action='delete', chat={'provider': 'telegram', 'id': '123'}, messageId='7', forMe=True)
        for fields in ({'forMe': None}, {'forMe': 'false'}, {'messageId': ''}, {'messageId': '-1'}, {'chat': {'provider': 'whatsapp', 'id': '123'}}):
            with self.assertRaises(ProviderError):
                await bridge.dispatch(dict(valid, **fields))
        provider.call.assert_not_awaited()
        provider.call.return_value = {'ok': True}
        await bridge.dispatch(valid)
        provider.call.assert_awaited_once_with('delete', valid)

    async def test_telegram_scopes_and_wrong_chat_guard(self):
        provider = Telegram()
        provider.connect = AsyncMock()
        client = SimpleNamespace(is_user_authorized=AsyncMock(return_value=True), get_entity=AsyncMock(return_value=object()), get_messages=AsyncMock(return_value=SimpleNamespace(chat_id=123)), delete_messages=AsyncMock())
        provider.daemon = SimpleNamespace(client=client, dialogs_cache=[{'id': 123}], messages_cache={'123_80': [], '456_80': []}, chat_messages_cache={123: [], 456: []}, refresh_dialogs_cache=AsyncMock())
        with patch.dict(sys.modules, {'telethon.tl.types': SimpleNamespace(Channel=Channel)}):
            for for_me in (True, False):
                await provider.call('delete', {'chat': {'id': '123'}, 'messageId': '7', 'forMe': for_me})
                self.assertEqual(client.delete_messages.call_args.kwargs, {'revoke': not for_me})
            self.assertIn('456_80', provider.daemon.messages_cache)
            self.assertNotIn('123_80', provider.daemon.messages_cache)
            client.delete_messages.reset_mock()
            client.get_messages.return_value.chat_id = 456
            with self.assertRaisesRegex(ProviderError, 'no longer exists'):
                await provider.call('delete', {'chat': {'id': '123'}, 'messageId': '7', 'forMe': True})
            client.delete_messages.assert_not_awaited()
            client.get_entity.return_value = Channel()
            with self.assertRaisesRegex(ProviderError, 'only supports'):
                await provider.call('delete', {'chat': {'id': '123'}, 'messageId': '7', 'forMe': True})
            client.delete_messages.assert_not_awaited()

    async def test_telegram_failure_never_retries_with_other_scope(self):
        provider = Telegram()
        provider.connect = AsyncMock()
        provider.daemon = AsyncMock()
        provider.daemon.dialogs_cache = [{'id': 123}]
        provider.daemon.client.get_messages.return_value = SimpleNamespace(chat_id=123)
        provider.daemon.client.delete_messages.side_effect = RuntimeError('synthetic denied')
        with patch.dict(sys.modules, {'telethon.tl.types': SimpleNamespace(Channel=Channel)}):
            with self.assertRaises(ProviderError):
                await provider.call('delete', {'chat': {'id': '123'}, 'messageId': '7', 'forMe': False})
        provider.daemon.client.delete_messages.assert_awaited_once()

    async def test_whatsapp_routes_both_scopes_and_reports_failure(self):
        provider = WhatsApp()
        backend = Mock()
        backend.delete_message.return_value = {'ok': True}
        provider.backend = Mock(return_value=backend)
        for for_me in (True, False):
            await provider.call('delete', {'chat': {'id': 'synthetic', 'account': 'fixture'}, 'messageId': '7', 'forMe': for_me})
            backend.delete_message.assert_called_with('synthetic', '7', for_me)
        backend.delete_message.side_effect = provider.module.WhatsAppError('synthetic too old')
        with self.assertRaisesRegex(ProviderError, 'time limit'):
            await provider.call('delete', {'chat': {'id': 'synthetic'}, 'messageId': '7', 'forMe': False})
