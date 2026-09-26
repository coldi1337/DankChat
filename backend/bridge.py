#!/usr/bin/env python3
"""Private JSON-lines transport owned by the DMS daemon, with no shell expansion."""
from __future__ import annotations

import asyncio
import contextlib
import importlib.util
import importlib.machinery
import json
import os
from pathlib import Path
import re
import signal
import time
import shutil
import tempfile
import sys

from request_runner import RequestRunner
from sent_messages import SentMessages
from updates import Updates
from library import telegram_browse
from storage import Storage
from notifications import deliver as notify_desktop
from accounts import Accounts, instance_key, validate_id
from wacli_compat import check as check_wacli
from voice import VoiceRecorder
from presence import telegram_status, whatsapp_activity, TTL
from clipboard_image import ClipboardImages
from model import chat, messages, key as chat_key
from qr_login import QrLogin
from whatsapp_login import WhatsAppLogin
from receipts import apply as apply_receipts

ROOT = Path(__file__).resolve().parents[1]
MAX_REQUEST = 65536


def xdg(name, fallback):
    path = Path(os.environ.get(name, str(fallback)))
    return path if path.is_absolute() else fallback


STATE = xdg("XDG_STATE_HOME", Path.home() / ".local/state") / "dankchat"
CACHE = xdg("XDG_CACHE_HOME", Path.home() / ".cache") / "dankchat"
CONFIG = xdg("XDG_CONFIG_HOME", Path.home() / ".config") / "dankchat"
RUNTIME = xdg("XDG_RUNTIME_DIR", Path(f"/run/user/{os.getuid()}")) / "dankchat"


def load_module(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    loader.exec_module(module)
    return module


def export_media(source, destination):
    source, destination = Path(source), Path(destination)
    if not source.is_file() or not destination.is_absolute() or not destination.parent.is_dir():
        raise ProviderError("Choose a valid destination for the downloaded media.")
    if source.resolve() == destination.resolve():
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".dankchat-", dir=destination.parent, delete=False) as output:
            temporary = Path(output.name)
            with source.open("rb") as content:
                shutil.copyfileobj(content, output)
        os.replace(temporary, destination)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


class ProviderError(Exception):
    pass


class Telegram:
    def __init__(self, account=""):
        self.account = validate_id(account)
        self.config = CONFIG / "telegram" / account if account else CONFIG / "telegram"
        self.cache = CACHE / "telegram" / account if account else CACHE / "telegram"
        self.runtime = RUNTIME / "telegram" / account if account else RUNTIME / "telegram"
        self.daemon = None
        self.qr_task = None
        self.qr = None
        self.auth_state = "disconnected"
        self.downloads = {}
        self.sent = SentMessages(RUNTIME)
        self.connection_lock = asyncio.Lock()
        self.on_update = lambda: None
        self.activity = {}
        self.user_status = {}

    async def connect(self):
        async with self.connection_lock:
            await self._connect()

    async def _connect(self):
        if self.daemon:
            if not self.daemon.client.is_connected():
                await self.daemon.client.connect()
            return
        os.environ["DANKCHAT_TELEGRAM_CONFIG"] = str(self.config)
        os.environ["DANKCHAT_TELEGRAM_CACHE"] = str(self.cache)
        os.environ["DANKCHAT_TELEGRAM_RUNTIME"] = str(self.runtime)
        try:
            import telethon
            import qrcode
        except ImportError:
            raise ProviderError("Telegram dependencies are missing. Run python3 scripts/setup.")
        module = load_module("dankchat_telegram_" + self.account, ROOT / "vendor/telegram/telegram_client.py")
        daemon = module.TelegramBackend()
        daemon.automatic_media_downloads = False
        try:
            await daemon.client.connect()
        except Exception:
            await daemon.client.disconnect()
            raise
        self.daemon = daemon

        @daemon.client.on(telethon.events.NewMessage)
        @daemon.client.on(telethon.events.MessageEdited)
        @daemon.client.on(telethon.events.MessageDeleted)
        @daemon.client.on(telethon.events.MessageRead(inbox=True))
        @daemon.client.on(telethon.events.MessageRead(inbox=False))
        async def invalidate(event):
            daemon.messages_cache.clear()
            self.on_update()

        @daemon.client.on(telethon.events.UserUpdate)
        async def presence_update(event):
            now = time.time()
            if event.status is not None:
                self.user_status = {k: v for k, v in self.user_status.items() if now - v[1] < 60}
                self.user_status[str(event.sender_id)] = (telegram_status(event.status), now)
            if event.action is not None:
                self.activity = {k: v for k, v in self.activity.items() if v[1] > now}
                key = (str(event.chat_id), str(event.sender_id))
                kind = type(event.action).__name__
                value = {'SendMessageTypingAction': 'typing', 'SendMessageRecordAudioAction': 'recording', 'SendMessageRecordVideoAction': 'recording', 'SendMessageRecordRoundAction': 'recording'}.get(kind)
                if value:
                    self.activity[key] = (value, int(now) + TTL)
                else:
                    self.activity.pop(key, None)

    async def status(self):
        if not self.daemon and not (self.config / "telegram.session").exists():
            return {"ok": True, "authorized": False, "authState": self.auth_state}
        await self.connect()
        authorized = await self.daemon.client.is_user_authorized()
        return {"ok": True, "authorized": authorized, "authState": "authorized" if authorized else self.qr.state if self.qr else self.auth_state,
                "qrPath": self.qr.path if self.qr else ""}

    async def call(self, action, data):
        await self.connect()
        client = self.daemon.client
        if action == "logout":
            if self.qr_task:
                self.qr_task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await self.qr_task
            if not await client.log_out():
                raise ProviderError("Telegram sign-out failed. Your local session was preserved.")
            self.daemon = None
            self.qr = None
            self.qr_task = None
            self.auth_state = "disconnected"
            self.downloads.clear()
            self.activity.clear(); self.user_status.clear()
            shutil.rmtree(self.cache / "media", ignore_errors=True)
            return {"ok": True}
        if action == "cancel_login":
            await self.close()
            self.qr = None
            self.auth_state = "disconnected"
            return {"ok": True}
        if action == "login":
            if await client.is_user_authorized():
                return {"ok": True, "authorized": True}
            if self.qr_task:
                self.qr_task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await self.qr_task
            import qrcode
            from telethon.errors import SessionPasswordNeededError
            qr = await client.qr_login()
            self.qr = QrLogin(self.cache, qrcode.make, SessionPasswordNeededError)
            self.qr_task = asyncio.create_task(self.qr.run(qr))
            # Install the update listener before the UI receives the QR image.
            await asyncio.sleep(0)
            return {"ok": True, "qrPath": self.qr.path}
        if action == "password":
            await client.sign_in(password=data["password"])
            self.auth_state = "authorized"
            return {"ok": True}
        if not await client.is_user_authorized():
            raise ProviderError("Sign in to Telegram first.")
        if action == "chats":
            result = await self.daemon.execute_command({"action": "dialogs", "limit": 200})
            self.daemon.messages_cache.clear()
            return {"ok": True, "chats": [chat("telegram", c) for c in result["chats"]]}
        target = data.get("chat", {})
        if action in {"messages", "send", "read", "voice", "file", "download", "pin", "context", "reaction", "presence", "delete", "browse", "edit", "notify"}:
            # Resolve only exact dialogs returned by this account, never a guessed recipient.
            ident = str(target.get("id", ""))
            if not any(str(c["id"]) == ident for c in self.daemon.dialogs_cache):
                raise ProviderError("Select an existing Telegram chat first.")
            if action == "notify":
                rows = await client.get_messages(int(ident), limit=20)
                incoming = [r for r in rows if not r.out and r.date.timestamp() >= data["since"] and (not data.get("mentionsOnly") or r.mentioned)]
                if not incoming:
                    return {"ok": True}
                body = incoming[0].message if data.get("preview") else data["fallback"]
                title = next((c.get("title", "Telegram") for c in self.daemon.dialogs_cache if str(c["id"]) == ident), "Telegram")
                return {"ok": await notify_desktop(title, body or data["fallback"], data.get("sound", False))}
            if action == "browse":
                return await telegram_browse(self, target, data.get("query", ""), data.get("category", ""), data.get("offset", ""))
            if action == "edit":
                entity = await client.get_input_entity(int(ident))
                row = await client.get_messages(entity, ids=int(data["messageId"]))
                if not row or not row.out or str(row.chat_id) != ident:
                    raise ProviderError("Only your own messages can be edited.")
                try:
                    await client.edit_message(entity, row.id, data["text"])
                except Exception as exc:
                    raise ProviderError("This message could not be edited. Check the time limit and your permissions.") from exc
                self.daemon.messages_cache.clear()
                return {"ok": True}
            if action == "delete":
                from telethon.tl.types import Channel
                entity = await client.get_entity(int(ident))
                if data["forMe"] and isinstance(entity, Channel):
                    raise ProviderError("Telegram only supports deleting for everyone in this chat.")
                mid = int(data["messageId"])
                row = await client.get_messages(entity, ids=mid)
                if not row or str(row.chat_id) != ident:
                    raise ProviderError("The message no longer exists in this chat.")
                try:
                    await client.delete_messages(entity, [mid], revoke=not data["forMe"])
                except Exception as exc:
                    raise ProviderError("The message could not be deleted. Check your permissions and the conversation before retrying.") from exc
                for cache_key in list(self.daemon.messages_cache):
                    if cache_key.startswith(ident + "_"):
                        self.daemon.messages_cache.pop(cache_key, None)
                self.daemon.chat_messages_cache.pop(int(ident), None)
                self.downloads.pop((ident, str(mid)), None)
                self.sent.forget(target, mid)
                asyncio.create_task(self.daemon.refresh_dialogs_cache())
                return {"ok": True}
            if action == "presence":
                now = time.time()
                result = {}
                if int(ident) > 0:
                    cached = self.user_status.get(ident)
                    if not cached or now - cached[1] > 30:
                        entity = await client.get_entity(int(ident))
                        cached = (telegram_status(getattr(entity, "status", None)), now)
                        self.user_status[ident] = cached
                    result.update(cached[0])
                active = [value for (chat_id, sender), value in self.activity.items() if chat_id == ident and value[1] > now]
                if active:
                    value = max(active, key=lambda v: v[1])
                    result.update(activity=value[0], activityExpiresAt=value[1])
                return {"ok": True, "presence": result}
            if action == "context":
                rows = await self.daemon.get_messages_for_chat(ident, limit=40, around_id=data["messageId"])
                for row in rows:
                    path = self.downloads.get((ident, str(row["id"])))
                    if path and Path(path).is_file():
                        row["media_path"] = path
                return {"ok": True, "messages": messages("telegram", rows)}
            if action == "reaction":
                result = await self.daemon.execute_command({"action": "send_reaction", "chat_id": ident,
                    "message_id": data["messageId"], "emoticon": data["emoji"].replace("\ufe0f", "")})
                if not result.get("success"):
                    raise ProviderError("Telegram could not apply this reaction. It may be unavailable in this chat or on this message.")
                return {"ok": True}
            if action == "pin":
                from telethon.tl import functions, types
                from telethon.errors import PinnedDialogsTooMuchError
                peer = types.InputDialogPeer(await client.get_input_entity(int(ident)))
                try:
                    await client(functions.messages.ToggleDialogPinRequest(peer=peer, pinned=data["pinned"]))
                except PinnedDialogsTooMuchError as exc:
                    raise ProviderError("Telegram pin limit reached: the main chat list allows 5 pinned chats without Premium (10 with Premium). Unpin another chat first.") from exc
                return {"ok": True}
            if action == "messages":
                result = await self.daemon.execute_command({"action": "messages", "chat_id": ident, "limit": 100})
                for row in result["messages"]:
                    path = self.downloads.get((ident, str(row["id"])))
                    if path and Path(path).is_file():
                        row["media_path"] = path
                return {"ok": True, "messages": self.sent.merge(target, messages("telegram", result["messages"]))}
            if action == "download":
                media_type = data.get("mediaType", "document")
                if media_type not in {"video", "photo", "image", "sticker", "document", "audio", "voice", "gif"}:
                    raise ProviderError("This message has no downloadable attachment.")
                result = await self.daemon.execute_command({"action": "download_media", "chat_id": ident,
                    "message_id": data["messageId"], "media_type": media_type})
                if not result.get("success"):
                    raise ProviderError("The attachment could not be downloaded.")
                self.downloads[(ident, str(data["messageId"]))] = result["file_path"]
                return {"ok": True, "path": result["file_path"]}
            if action == "read" and data.get("messageId"):
                await client.send_read_acknowledge(int(ident), max_id=int(data["messageId"]))
                self.daemon.messages_cache.clear()
                self.on_update()
                return {"ok": True}
            if action == "send":
                result = await self.daemon.execute_command({"action": "send", "chat_id": ident, "text": data["text"], "reply_to": data.get("replyId") or None})
            elif action == "voice":
                result = await self.daemon.send_file_to_chat(ident, data["path"], reply_to=data.get("replyId") or None, voice_note=True, voice_duration=data["duration"])
            elif action == "file":
                result = await self.daemon.execute_command({"action": "send_file", "chat_id": ident, "file_path": data["path"], "caption": data.get("text", ""), "reply_to": data.get("replyId") or None})
            else:
                result = await self.daemon.execute_command({"action": "mark_read", "chat_id": ident})
            if not result.get("success"):
                raise ProviderError("Telegram could not complete the action. Check the conversation before retrying.")
            sent = await asyncio.to_thread(self.sent.remember, "telegram", target, result, data) if action in {"send", "file"} else None
            return {"ok": True, **({"message": sent} if sent else {})}
        raise ProviderError("Unsupported Telegram action.")

    async def close(self):
        self.sent.close()
        self.activity.clear(); self.user_status.clear()
        if self.qr_task:
            self.qr_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.qr_task
        if self.daemon:
            await self.daemon.client.disconnect()
            self.daemon = None


class WhatsApp:
    def __init__(self, account=""):
        self.account = validate_id(account)
        self.unit = "dankchat-whatsapp@" + account + ".service" if account else "dankchat-whatsapp.service"
        self.state = STATE / "whatsapp" / account if account else STATE / "whatsapp"
        sys.path.insert(0, str(ROOT / "vendor/whatsapp/bin"))
        self.module = load_module("dankchat_whatsapp_" + self.account, ROOT / "vendor/whatsapp/bin/whatsapp_client.py")
        self.module.SYNC_UNIT = self.unit
        self.module.SYNC_UNIT_NAME = re.compile(re.escape(self.unit) + r"\Z")
        self.store = self.state / "store"
        self.helper_state = self.state / "helper"
        self.binary = Path.home() / ".local/bin/wacli"
        self.sent = SentMessages(RUNTIME)
        self.version_checked = False
        self.login = None
        self.maintenance = 0

    async def sync(self, start, wait=False):
        process = await asyncio.create_subprocess_exec("systemctl", "--user", *([] if wait else ["--no-block"]), "start" if start else "stop",
            self.unit, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        await process.wait()

    def backend(self, account=""):
        backend = self.module.Backend(store_dir=self.store, state_dir=self.helper_state,
                                      wacli=self.binary, account_config=self.state / "accounts.yaml")
        backend.use_account("" if self.account else account)
        return backend

    async def status(self):
        if not self.binary.is_file():
            return {"ok": True, "authorized": False, "installed": False}
        if not self.version_checked:
            try:
                await check_wacli(self.binary)
            except ValueError as exc:
                raise ProviderError(str(exc)) from exc
            self.version_checked = True
        if self.login and self.login.task and not self.login.task.done():
            return {"ok": True, "authorized": self.login.state == "authorized", "installed": True,
                    "authState": self.login.state, "qrPath": self.login.qr.path, "linking": True}
        if not (self.store / "session.db").exists():
            return {"ok": True, "authorized": False, "installed": True,
                    "authState": self.login.state if self.login else "disconnected"}
        result = await asyncio.to_thread(self.backend().status)
        if result.get("error"):
            raise ProviderError("The service is temporarily unavailable. Please try again.")
        if not self.maintenance and result.get("authenticated") and result.get("online") and not result.get("sync_active"):
            await self.sync(True)
        return {"ok": result.get("ok", False), "authorized": result.get("authenticated", False), "installed": True, "syncActive": bool(result.get("sync_active")),
                "authState": "authorized" if result.get("authenticated") else self.login.state if self.login else "disconnected"}

    async def call(self, action, data):
        writing = action in {"send", "file", "voice", "edit", "delete", "reaction", "read", "pin", "login", "logout"}
        if writing:
            self.maintenance += 1
        try:
            return await self._call(action, data)
        finally:
            if writing:
                self.maintenance -= 1

    async def _call(self, action, data):
        if action == "cancel_login":
            if self.login:
                await self.login.cancel()
                self.login = None
            return {"ok": True}
        if action == "login":
            state = await self.status()
            if state.get("authorized") or state.get("linking"):
                return state
            if not state.get("installed"):
                raise ProviderError("Install wacli 0.17.1 or newer first.")
            try:
                import qrcode
            except ImportError:
                raise ProviderError("QR dependencies are missing. Run python3 scripts/setup.")
            await self.sync(False, wait=True)
            self.store.mkdir(parents=True, exist_ok=True, mode=0o700)
            directory = CACHE / "whatsapp-login" / (self.account or "default")
            directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            self.login = WhatsAppLogin(self.binary, self.store, directory, qrcode.make)
            self.login.task = asyncio.create_task(self.login.run())
            return {"ok": True}
        if action == "logout":
            if self.login:
                await self.login.cancel()
                self.login = None
            await self.sync(False, wait=True)
            process = await asyncio.create_subprocess_exec(str(self.binary), "--store", str(self.store),
                "--timeout", "45s", "auth", "logout", stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
            try:
                code = await asyncio.wait_for(process.wait(), 55)
            except (asyncio.TimeoutError, asyncio.CancelledError):
                with contextlib.suppress(ProcessLookupError):
                    process.kill()
                await process.wait()
                raise
            if code:
                raise ProviderError("WhatsApp sign-out failed. Your local session was preserved; check your connection.")
            shutil.rmtree(self.store)
            if self.helper_state.exists():
                shutil.rmtree(self.helper_state)
            return {"ok": True}
        target = data.get("chat", {})
        backend = self.backend(target.get("account", ""))
        ident = str(target.get("id", ""))
        if action == "chats":
            result = await asyncio.to_thread(backend.chats)
            return {"ok": True, "chats": [chat("whatsapp", c) for c in result["chats"]]}
        if action == "notify":
            if data.get("mentionsOnly"):
                return {"ok": True}
            result = await asyncio.to_thread(backend.messages, ident, limit=20)
            rows = [r for r in result["messages"] if not r.get("from_me") and r.get("timestamp", 0) >= data["since"]]
            if not rows:
                return {"ok": True}
            body = rows[0].get("text", "") if data.get("preview") else data["fallback"]
            return {"ok": await notify_desktop(result["chat"].get("name", "WhatsApp"), body or data["fallback"], data.get("sound", False))}
        if action == "browse":
            offset = int(data.get("offset") or 0)
            result = await asyncio.to_thread(backend.messages, ident, query=data.get("query", ""), limit=51, category=data.get("category", ""), offset=offset)
            rows = result["messages"]
            return {"ok": True, "messages": list(reversed(messages("whatsapp", rows[:50]))), "next": str(offset + 50) if len(rows) > 50 else ""}
        if action == "edit":
            try:
                return await asyncio.to_thread(backend.edit_message, ident, data["messageId"], data["text"])
            except self.module.WhatsAppError as exc:
                raise ProviderError("This message could not be edited. Check the time limit and your permissions.") from exc
        if action == "presence":
            backend._chat(ident)
            return {"ok": True, "presence": await asyncio.to_thread(whatsapp_activity, self.helper_state / "receipts.sqlite", ident)}
        if action == "context":
            result = await asyncio.to_thread(backend.messages, ident, limit=40, around_id=data["messageId"])
            await asyncio.to_thread(apply_receipts, self.helper_state / "receipts.sqlite", ident, result["messages"])
            return {"ok": True, "messages": self.sent.merge(target, messages("whatsapp", result["messages"]), include_pending=action == "messages")}
        if action == "messages":
            result = await asyncio.to_thread(backend.messages, ident)
            await asyncio.to_thread(apply_receipts, self.helper_state / "receipts.sqlite", ident, result["messages"])
            return {"ok": True, "messages": self.sent.merge(target, messages("whatsapp", result["messages"]), include_pending=action == "messages")}
        if action == "download":
            try:
                download = await asyncio.to_thread(backend.download_media, ident, data["messageId"], read_only=True)
            except self.module.WhatsAppError as exc:
                if any(code in str(exc).lower() for code in ("status code 403", "status code 404", "status code 410")):
                    raise ProviderError("WhatsApp rejected this media download. Open it on your phone; if it stays unavailable here, ask for it to be sent again.") from exc
                if "no downloadable media metadata" in str(exc):
                    raise ProviderError("This attachment has no download information on this linked device yet.") from exc
                raise ProviderError("The attachment could not be downloaded. Please try again later.") from exc
            if isinstance(download, dict) and download.get("local_path"):
                return {"ok": True, "path": download["local_path"]}
            result = await asyncio.to_thread(backend.messages, ident, limit=1, around_id=data["messageId"])
            row = next((row for row in result["messages"] if str(row["id"]) == str(data["messageId"])), {})
            return {"ok": True, "path": row.get("local_path", "")}
        if action == "pin":
            await asyncio.to_thread(backend.chat_action, ident, "pin" if data["pinned"] else "unpin")
            return {"ok": True}
        if action == "send":
            result = await asyncio.to_thread(backend.send, ident, data["text"], data.get("replyId", ""))
        elif action == "voice":
            def send_voice():
                path = backend.voice_draft("create")["path"]
                try:
                    shutil.copyfile(data["path"], path)
                    return backend.send_voice(ident, path, data.get("replyId", ""))
                finally:
                    with contextlib.suppress(Exception):
                        backend.voice_draft("discard", path)
            result = await asyncio.to_thread(send_voice)
        elif action == "file":
            result = await asyncio.to_thread(backend.send_files, ident, [data["path"]], data.get("text", ""), data.get("replyId", ""))
        elif action == "delete":
            try:
                result = await asyncio.to_thread(backend.delete_message, ident, data["messageId"], data["forMe"])
            except self.module.WhatsAppError as exc:
                raise ProviderError("The message could not be deleted. Check the deletion time limit, your permissions and the conversation before retrying.") from exc
        elif action == "reaction":
            result = await asyncio.to_thread(backend.react, ident, data["messageId"], data["emoji"])
        elif action == "read":
            result = await asyncio.to_thread(backend.chat_action, ident, "read")
        elif action == "acknowledge":
            result = await asyncio.to_thread(backend.acknowledge_notifications, ident)
        else:
            raise ProviderError("Unsupported WhatsApp action.")
        if not result.get("ok"):
            raise ProviderError("WhatsApp could not complete the action. Check the conversation before retrying.")
        if action == "delete":
            self.sent.forget(target, data["messageId"])
        sent = await asyncio.to_thread(self.sent.remember, "whatsapp", target, result, data) if action in {"send", "file"} else None
        return {"ok": True, **({"message": sent} if sent else {})}

    async def close(self):
        self.sent.close()
        if self.login:
            await self.login.cancel()
        await self.sync(False)


class Bridge:
    def __init__(self):
        self.providers = {}
        self.status_snapshots = {}
        self.accounts = Accounts(CONFIG / "accounts.json")
        self.updates = Updates(ROOT, CACHE / "updates.json")
        self.storage = Storage(CACHE, STATE)
        self.on_event = lambda event: None
        self.clipboard = ClipboardImages(RUNTIME)
        self.voice = VoiceRecorder(RUNTIME)

    def make_provider(self, name, account):
        provider = (Telegram if name == "telegram" else WhatsApp)(account)
        self.providers[instance_key(name, account)] = provider
        provider.on_update = lambda: self.on_event({"event": "provider_changed", "provider": name, "account": account})
        return provider

    async def dispatch(self, request):
        action = request.get("action")
        if action == "storage_info":
            return await asyncio.to_thread(self.storage.info)
        if action == "clean_storage":
            limit, days = request.get("limitMb", 512), request.get("days", 30)
            if type(limit) is not int or not 64 <= limit <= 4096 or type(days) is not int or not 1 <= days <= 365:
                raise ProviderError("Invalid storage limits.")
            protected = request.get("protect", [])
            if not isinstance(protected, list) or len(protected) > 500 or any(not isinstance(p, str) for p in protected):
                raise ProviderError("Invalid storage limits.")
            return await asyncio.to_thread(self.storage.clean, limit, days, request.get("clear") is True, protected)
        if action == "app_info":
            return {"ok": True, **await asyncio.to_thread(self.updates.info)}
        if action == "check_updates":
            return await asyncio.to_thread(self.updates.check, request.get("force") is True)
        if action == "accounts":
            return {"ok": True, "accounts": self.accounts.rows()}
        if action in {"add_account", "rename_account"}:
            try:
                if action == "add_account":
                    row = self.accounts.add(request.get("provider"), request.get("label"))
                    name = row["provider"]
                    if name in self.providers:
                        self.make_provider(name, row["id"])
                else:
                    self.accounts.rename(request.get("provider"), request.get("account", ""), request.get("label"))
            except ValueError as exc:
                raise ProviderError(str(exc)) from exc
            return {"ok": True, "accounts": self.accounts.rows()}
        if action == "configure":
            self.clipboard.close()
            await self.voice.discard()
            enabled = request.get("enabled", [])
            wanted = {instance_key(row["provider"], row["id"]) for row in self.accounts.rows() if row["provider"] in enabled}
            for name in list(self.providers):
                if name not in wanted:
                    await self.providers.pop(name).close()
                    self.status_snapshots.pop(name, None)
            for row in self.accounts.rows():
                if row["provider"] in enabled and instance_key(row["provider"], row["id"]) not in self.providers:
                    self.make_provider(row["provider"], row["id"])
            return {"ok": True, "accounts": self.accounts.rows()}
        name = request.get("provider")
        target = request.get("chat")
        account = request.get("account", target.get("account", "") if isinstance(target, dict) else "")
        try:
            identity = instance_key(name, account)
        except ValueError as exc:
            raise ProviderError(str(exc)) from exc
        if identity not in self.providers:
            raise ProviderError("This service is disabled.")
        provider = self.providers[identity]
        if action == "discard_clipboard":
            paths = request.get("paths", [])
            if not isinstance(paths, list) or len(paths) > 20 or any(not isinstance(p, str) for p in paths):
                raise ProviderError("Invalid clipboard attachments.")
            self.clipboard.discard(paths)
            return {"ok": True}
        if action == "clipboard_image":
            try:
                return await self.clipboard.paste()
            except (ValueError, OSError, asyncio.TimeoutError) as exc:
                raise ProviderError(str(exc) or "The clipboard did not respond.") from exc
        if action in {"voice_start", "voice_stop", "voice_discard"}:
            try:
                if action == "voice_start":
                    return await self.voice.start()
                if action == "voice_stop":
                    return await self.voice.stop()
                await self.voice.discard()
                return {"ok": True}
            except (ValueError, OSError) as exc:
                raise ProviderError(str(exc)) from exc
        if action == "status":
            result = await provider.status()
            self.status_snapshots[identity] = {"provider": name, "authorized": bool(result.get("authorized")), "ok": bool(result.get("ok")), "syncActive": bool(result.get("syncActive")) if name == "whatsapp" else None}
            return result
        if action not in {"chats", "messages", "send", "voice", "file", "read", "acknowledge", "login", "password", "download", "pin", "logout", "cancel_login", "export", "context", "reaction", "presence", "delete", "browse", "edit", "notify"}:
            raise ProviderError("Unsupported action.")
        if action in {"messages", "send", "voice", "file", "read", "acknowledge", "download", "pin", "export", "context", "reaction", "presence", "delete", "browse", "edit", "notify"}:
            target = request.get("chat")
            if not isinstance(target, dict) or target.get("provider") != name or not target.get("id") or target.get("account", "") != account:
                raise ProviderError("The chat does not belong to this service.")
        if action == "export":
            result = await provider.call("messages", request)
            selected = next((row for row in result.get("messages", []) if row["id"] == str(request.get("messageId"))), None)
            if selected is None:
                context = await provider.call("context", request)
                selected = next((row for row in context.get("messages", []) if row["id"] == str(request.get("messageId"))), None)
            if not selected or not selected.get("mediaPath"):
                raise ProviderError("Load the media before saving it.")
            await asyncio.to_thread(export_media, selected["mediaPath"], request.get("destination", ""))
            return {"ok": True}
        if action == "read" and name == "telegram" and request.get("messageId"):
            mid = request["messageId"]
            if not isinstance(mid, str) or not mid.isdecimal() or not 0 < int(mid) < 2**63:
                raise ProviderError("Select an existing Telegram chat first.")
        if action == "notify":
            if not isinstance(request.get("since"), (float, int)) or not isinstance(request.get("fallback"), str) or len(request["fallback"]) > 200:
                raise ProviderError("Invalid notification request.")
        if action == "browse":
            query, category, offset = request.get("query", ""), request.get("category", ""), request.get("offset", "")
            if not isinstance(query, str) or len(query) > 256 or category not in ("", "images", "videos", "files", "links", "audio") or not isinstance(offset, str) or (offset and (not offset.isdecimal() or len(offset) > 12)):
                raise ProviderError("Invalid search.")
        if action == "edit":
            text, mid = request.get("text"), request.get("messageId")
            if not isinstance(text, str) or not text.strip() or len(text) > 4096 or not isinstance(mid, str) or not mid or len(mid) > 256 or (name == "telegram" and not mid.isdecimal()):
                raise ProviderError("Enter a message of up to 4096 characters.")
        if action == "delete":
            mid = request.get("messageId")
            if not isinstance(request.get("forMe"), bool) or not isinstance(mid, str) or not mid or len(mid) > 256 or (name == "telegram" and (not mid.isdecimal() or int(mid) <= 0)):
                raise ProviderError("Select a message and a deletion option.")
        if action == "reaction":
            emoji = request.get("emoji")
            ident = request.get("messageId")
            if not isinstance(ident, str) or not ident or len(ident) > 256:
                raise ProviderError("Select a message to react to.")
            if not isinstance(emoji, str) or len(emoji) > 16 or any(ord(c) < 32 for c in emoji):
                raise ProviderError("Choose a valid emoji reaction.")
        if action == "pin" and not isinstance(request.get("pinned"), bool):
            raise ProviderError("Invalid pin state.")
        if action in {"send", "file"}:
            text = request.get("text", "")
            if not isinstance(text, str) or len(text) > 4096 or (action == "send" and not text.strip()):
                raise ProviderError("Enter a message of up to 4096 characters.")
            if action == "file":
                path = Path(request.get("path", ""))
                if not path.is_absolute() or not path.is_file() or path.stat().st_size > 100 * 1024 * 1024:
                    raise ProviderError("Choose a local file smaller than 100 MB.")
        if action == "voice":
            try:
                request["path"] = self.voice.validated_path(request.get("path"))
                request["duration"] = self.voice.duration
            except ValueError as exc:
                raise ProviderError(str(exc)) from exc
        result = await provider.call(action, request)
        if action == "chats" and result.get("ok"):
            label = next((r["label"] for r in self.accounts.rows() if r["provider"] == name and r["id"] == account), name)
            for row in result.get("chats", []):
                row.update(account=account, accountLabel=label, key=chat_key(name, account, row["id"]))
        if action == "voice" and result.get("ok"):
            await self.voice.discard()
        if action == "logout" and result.get("ok"):
            provider.sent.close()
        return result

    async def close(self):
        for provider in self.providers.values():
            await provider.close()
        await self.voice.discard()
        self.clipboard.close()


async def main():
    os.umask(0o077)
    for path in (STATE, CACHE, CONFIG, RUNTIME):
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        path.chmod(0o700)
    # One bridge per user, including during plugin reload or multiple bar instances.
    import fcntl
    lock = (RUNTIME / "bridge.lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return
    bridge = Bridge()
    runner = RequestRunner()
    tasks = set()
    output = sys.stdout
    sink = open(os.devnull, "w")
    sys.stdout = sink
    sys.stderr = sink

    def emit(result):
        output.write(json.dumps(result, ensure_ascii=True) + "\n")
        output.flush()
    bridge.on_event = emit

    async def respond(request):
        try:
            if request.get("action") in {"diagnostics", "export_diagnostics"}:
                result = {"ok": True, "requests": list(runner.diagnostics)}
                if request["action"] == "export_diagnostics":
                    report = {"application": bridge.updates.info(), "connections": list(bridge.status_snapshots.values()), "requests": list(runner.diagnostics),
                              "accounts": {name: sum(1 for key in bridge.providers if key.split(":")[0] == name) for name in ("telegram", "whatsapp")}}
                    with tempfile.NamedTemporaryFile(mode="w", dir=RUNTIME, suffix=".json") as out:
                        json.dump(report, out, indent=2); out.flush()
                        await asyncio.to_thread(export_media, out.name, request.get("destination", ""))
            else:
                result = await runner.run(request, bridge.dispatch)
        except ProviderError as exc:
            result = {"ok": False, "error": str(exc)}
        except Exception:
            writes = {"send", "file", "voice", "delete", "reaction", "pin", "read", "edit"}
            error = "The service could not complete this request. Check the connection; do not resend without checking the conversation." if request.get("action") in writes else "The service is temporarily unavailable. Please try again."
            result = {"ok": False, "error": error}
        result["requestId"] = request.get("requestId")
        emit(result)
    reader = asyncio.StreamReader(limit=MAX_REQUEST + 1)
    await asyncio.get_running_loop().connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    task = asyncio.current_task()
    for sig in (signal.SIGTERM, signal.SIGINT):
        asyncio.get_running_loop().add_signal_handler(sig, task.cancel)
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            request = {}
            try:
                if len(line) > MAX_REQUEST:
                    raise ProviderError("Request is too large.")
                request = json.loads(line)
                if not isinstance(request, dict):
                    request = {}
                    raise ProviderError("Invalid request.")
                if request.get("action") == "configure":
                    if tasks:
                        await asyncio.gather(*tasks)
                    await respond(request)
                else:
                    if len(tasks) >= 32:
                        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                    work = asyncio.create_task(respond(request))
                    tasks.add(work)
                    work.add_done_callback(tasks.discard)
            except ProviderError as exc:
                output.write(json.dumps({"ok": False, "error": str(exc), "requestId": request.get("requestId")}) + "\n")
                output.flush()
            except (json.JSONDecodeError, UnicodeDecodeError):
                output.write('{"ok":false,"error":"Invalid JSON request."}\n')
                output.flush()
        if tasks:
            await asyncio.gather(*tasks)
    except asyncio.CancelledError:
        for work in tasks:
            work.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
    finally:
        await bridge.close()
        lock.close()


if __name__ == "__main__":
    asyncio.run(main())
