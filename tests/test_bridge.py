import asyncio
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, Mock, patch
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
from bridge import Bridge, ProviderError, Telegram, WhatsApp
from model import chat, key, message, messages


class ModelTests(unittest.TestCase):
    def test_both_providers_put_latest_message_at_the_bottom(self):
        for provider in ("telegram", "whatsapp"):
            rows = [{"id": "3", "timestamp": 30}, {"id": "2", "timestamp": 20}, {"id": "1", "timestamp": 20}]
            self.assertEqual([m["id"] for m in messages(provider, rows)], ["1", "2", "3"])

    def test_telegram_chat_order_retains_time_of_day(self):
        self.assertEqual(chat("telegram", {"id": 1, "last_message": {"date": "2026-09-13", "timestamp": 12345}})["timestamp"], 12345)

    def test_provider_and_account_isolate_equal_chat_ids(self):
        keys = {key("telegram", "", "123"), key("whatsapp", "", "123"),
                key("whatsapp", "a", "123"), key("whatsapp", "b", "123")}
        self.assertEqual(len(keys), 4)
        self.assertNotEqual(key("whatsapp", "a:b", "c"), key("whatsapp", "a", "b:c"))

    def test_telegram_ids_and_literal_content_survive_normalization(self):
        row = chat("telegram", {"id": -1001234567890, "title": "<b>Team</b>",
            "unread_count": 2, "last_message": {"date": "2026-09-13T12:00:00+00:00", "text": "$(touch nope)"}})
        self.assertEqual(row["id"], "-1001234567890")
        self.assertEqual(row["name"], "<b>Team</b>")
        self.assertEqual(row["preview"], "$(touch nope)")
        self.assertGreater(row["timestamp"], 0)

    def test_whatsapp_badge_uses_notification_unread(self):
        row = chat("whatsapp", {"jid": "synthetic", "account": "one", "unread": 9, "notification_unread": 0})
        self.assertEqual(row["unread"], 0)

    def test_pinned_chat_state_survives_both_adapters(self):
        self.assertTrue(chat("telegram", {"id": "1", "pinned": True})["pinned"])
        self.assertTrue(chat("whatsapp", {"jid": "synthetic", "pinned": 1})["pinned"])

    def test_message_media_and_reply_are_shared(self):
        tg = message("telegram", {"id": 4, "text": "hello", "out": True, "media_type": "photo", "media_path": "/tmp/demo.png", "reply_to_text": "previous", "reply_to_msg_id": "original"})
        wa = message("whatsapp", {"id": "4", "text": "hello", "from_me": True, "media_type": "photo", "local_path": "/tmp/demo.png", "quoted_text": "previous", "quoted_id": "original"})
        self.assertEqual(tg, wa)
        self.assertEqual(tg["replyId"], "original")


class RoutingTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.bridge = Bridge()
        self.provider = AsyncMock()
        self.provider.call.return_value = {"ok": True}
        self.bridge.providers["telegram"] = self.provider

    async def test_disabled_provider_cannot_send(self):
        with self.assertRaises(ProviderError):
            await self.bridge.dispatch({"provider": "whatsapp", "action": "send", "text": "hello"})
        self.provider.call.assert_not_called()

    async def test_wrong_provider_rejected_for_read_and_write(self):
        for action in ("messages", "send", "file", "read", "pin", "download", "export", "context"):
            with self.assertRaises(ProviderError):
                await self.bridge.dispatch({"provider": "telegram", "action": action,
                    "chat": {"provider": "whatsapp", "id": "synthetic"}, "text": "hello"})
        self.provider.call.assert_not_called()

    async def test_failed_send_is_never_retried(self):
        self.provider.call.side_effect = TimeoutError
        with self.assertRaises(TimeoutError):
            await self.bridge.dispatch({"provider": "telegram", "action": "send",
                "chat": {"provider": "telegram", "id": "123"}, "text": "hello"})
        self.assertEqual(self.provider.call.await_count, 1)

    async def test_disabling_provider_disconnects_it(self):
        await self.bridge.dispatch({"action": "configure", "enabled": []})
        self.provider.close.assert_awaited_once()
        self.assertEqual(self.bridge.providers, {})

    async def test_empty_or_oversized_messages_rejected(self):
        for text in ("  ", "a" * 4097, ["hello"]):
            with self.assertRaises(ProviderError):
                await self.bridge.dispatch({"provider": "telegram", "action": "send",
                    "chat": {"provider": "telegram", "id": "123"}, "text": text})
        self.provider.call.assert_not_called()

    async def test_telegram_messages_do_not_send_read_receipts(self):
        provider = Telegram()
        provider.connect = AsyncMock()
        provider.daemon = AsyncMock()
        provider.daemon.client.is_user_authorized.return_value = True
        provider.daemon.dialogs_cache = [{"id": 123}]
        provider.daemon.execute_command.return_value = {"success": True, "messages": []}
        await provider.call("messages", {"chat": {"id": "123"}})
        provider.daemon.execute_command.assert_awaited_once_with({"action": "messages", "chat_id": "123", "limit": 100})

    async def test_explicit_telegram_mark_read(self):
        provider = Telegram()
        provider.connect = AsyncMock()
        provider.daemon = AsyncMock()
        provider.daemon.client.is_user_authorized.return_value = True
        provider.daemon.dialogs_cache = [{"id": 123}]
        provider.daemon.execute_command.return_value = {"success": True}
        self.assertTrue((await provider.call("read", {"chat": {"id": "123"}}))["ok"])
        provider.daemon.execute_command.assert_awaited_once_with({"action": "mark_read", "chat_id": "123"})

    async def test_explicit_whatsapp_read_uses_server_chat_action(self):
        provider = WhatsApp()
        backend = Mock()
        provider.backend = Mock(return_value=backend)
        backend.chat_action.return_value = {"ok": True}
        self.assertTrue((await provider.call("read", {"chat": {"id": "synthetic", "account": "one"}}))["ok"])
        provider.backend.assert_called_once_with("one")
        backend.chat_action.assert_called_once_with("synthetic", "read")
        backend.acknowledge_notifications.assert_not_called()
        backend.chat_action.return_value = {"ok": False}
        with self.assertRaises(ProviderError):
            await provider.call("read", {"chat": {"id": "synthetic"}})

    async def test_telegram_pin_limit_is_specific_and_other_errors_propagate(self):
        class PinnedDialogsTooMuchError(Exception):
            pass
        provider = Telegram()
        provider.connect = AsyncMock()
        client = AsyncMock()
        client.is_user_authorized.return_value = True
        provider.daemon = SimpleNamespace(client=client, dialogs_cache=[{"id": 123}])
        request = Mock()
        modules = {
            "telethon.tl": SimpleNamespace(functions=SimpleNamespace(messages=SimpleNamespace(ToggleDialogPinRequest=request)), types=SimpleNamespace(InputDialogPeer=lambda peer: peer)),
            "telethon.errors": SimpleNamespace(PinnedDialogsTooMuchError=PinnedDialogsTooMuchError),
        }
        with patch.dict(sys.modules, modules):
            client.side_effect = PinnedDialogsTooMuchError()
            with self.assertRaisesRegex(ProviderError, "5 pinned chats without Premium"):
                await provider.call("pin", {"chat": {"id": "123"}, "pinned": True})
            self.assertEqual(client.await_count, 1)
            client.side_effect = RuntimeError("network unavailable")
            with self.assertRaises(RuntimeError):
                await provider.call("pin", {"chat": {"id": "123"}, "pinned": True})
            client.side_effect = None
            self.assertTrue((await provider.call("pin", {"chat": {"id": "123"}, "pinned": False}))["ok"])
            self.assertFalse(request.call_args.kwargs["pinned"])

    async def test_unknown_telegram_target_is_rejected(self):
        provider = Telegram()
        provider.connect = AsyncMock()
        provider.daemon = AsyncMock()
        provider.daemon.client.is_user_authorized.return_value = True
        provider.daemon.dialogs_cache = [{"id": 123}]
        with self.assertRaises(ProviderError):
            await provider.call("send", {"chat": {"id": "456"}, "text": "hello"})
        provider.daemon.execute_command.assert_not_called()


class TransportTests(unittest.TestCase):
    def test_real_stdio_transport_and_private_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ)
            for keyname in ("XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR"):
                env[keyname] = str(Path(directory) / keyname)
                Path(env[keyname]).mkdir()
            request = '{"requestId":1,"action":"configure","enabled":[]}\n'
            request += '{"requestId":2,"provider":"telegram","action":"status"}\n'
            result = subprocess.run([sys.executable, str(ROOT / "backend/bridge.py")],
                input=request, text=True, capture_output=True, env=env, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            replies = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual([r["requestId"] for r in replies], [1, 2])
            self.assertTrue(replies[0]["ok"])
            self.assertFalse(replies[1]["ok"])
            self.assertEqual(result.stderr, "")
            self.assertEqual((Path(env["XDG_STATE_HOME"]) / "dankchat").stat().st_mode & 0o777, 0o700)


if __name__ == "__main__":
    unittest.main()
