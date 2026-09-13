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
import shutil
import sys

from model import chat, messages
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


class ProviderError(Exception):
    pass


class Telegram:
    def __init__(self):
        self.daemon = None
        self.qr_task = None
        self.qr = None
        self.auth_state = "disconnected"
        self.downloads = {}

    async def connect(self):
        if self.daemon:
            if not self.daemon.client.is_connected():
                await self.daemon.client.connect()
            return
        os.environ["DANKCHAT_TELEGRAM_CONFIG"] = str(CONFIG / "telegram")
        os.environ["DANKCHAT_TELEGRAM_CACHE"] = str(CACHE / "telegram")
        os.environ["DANKCHAT_TELEGRAM_RUNTIME"] = str(RUNTIME / "telegram")
        try:
            import telethon
            import qrcode
        except ImportError:
            raise ProviderError("Telegram dependencies are missing. Run scripts/setup-telegram.")
        module = load_module("dankchat_telegram", ROOT / "vendor/telegram/telegram_client.py")
        daemon = module.TelegramBackend()
        try:
            await daemon.client.connect()
        except Exception:
            await daemon.client.disconnect()
            raise
        self.daemon = daemon

        @daemon.client.on(telethon.events.NewMessage)
        @daemon.client.on(telethon.events.MessageEdited)
        @daemon.client.on(telethon.events.MessageDeleted)
        @daemon.client.on(telethon.events.MessageRead)
        async def invalidate(event):
            daemon.messages_cache.clear()

    async def status(self):
        if not self.daemon and not (CONFIG / "telegram/telegram.session").exists():
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
            shutil.rmtree(CACHE / "telegram", ignore_errors=True)
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
            self.qr = QrLogin(CACHE / "telegram", qrcode.make, SessionPasswordNeededError)
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
            return {"ok": True, "chats": [chat("telegram", c) for c in result["chats"]]}
        target = data.get("chat", {})
        if action in {"messages", "send", "read", "file", "download", "pin"}:
            # Resolve only exact dialogs returned by this account, never a guessed recipient.
            ident = str(target.get("id", ""))
            if not any(str(c["id"]) == ident for c in self.daemon.dialogs_cache):
                raise ProviderError("Select an existing Telegram chat first.")
            if action == "pin":
                from telethon.tl import functions, types
                peer = types.InputDialogPeer(await client.get_input_entity(int(ident)))
                await client(functions.messages.ToggleDialogPinRequest(peer=peer, pinned=data["pinned"]))
                return {"ok": True}
            if action == "messages":
                result = await self.daemon.execute_command({"action": "messages", "chat_id": ident, "limit": 100})
                for row in result["messages"]:
                    path = self.downloads.get((ident, str(row["id"])))
                    if path and Path(path).is_file():
                        row["media_path"] = path
                return {"ok": True, "messages": messages("telegram", result["messages"])}
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
            if action == "send":
                result = await self.daemon.execute_command({"action": "send", "chat_id": ident, "text": data["text"], "reply_to": data.get("replyId") or None})
            elif action == "file":
                result = await self.daemon.execute_command({"action": "send_file", "chat_id": ident, "file_path": data["path"], "caption": data.get("text", ""), "reply_to": data.get("replyId") or None})
            else:
                result = await self.daemon.execute_command({"action": "mark_read", "chat_id": ident})
            if not result.get("success"):
                raise ProviderError("Telegram could not complete the action. Check the conversation before retrying.")
            return {"ok": True}
        raise ProviderError("Unsupported Telegram action.")

    async def close(self):
        if self.qr_task:
            self.qr_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.qr_task
        if self.daemon:
            await self.daemon.client.disconnect()
            self.daemon = None


class WhatsApp:
    def __init__(self):
        sys.path.insert(0, str(ROOT / "vendor/whatsapp/bin"))
        self.module = load_module("dankchat_whatsapp", ROOT / "vendor/whatsapp/bin/whatsapp_client.py")
        self.module.SYNC_UNIT = "dankchat-whatsapp.service"
        self.module.SYNC_UNIT_NAME = re.compile(r"dankchat-whatsapp\.service\Z")
        self.store = STATE / "whatsapp/store"
        self.helper_state = STATE / "whatsapp/helper"
        self.binary = Path.home() / ".local/bin/wacli"
        self.version_checked = False
        self.login = None

    async def sync(self, start, wait=False):
        process = await asyncio.create_subprocess_exec("systemctl", "--user", *([] if wait else ["--no-block"]), "start" if start else "stop",
            "dankchat-whatsapp.service", stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
        await process.wait()

    def backend(self, account=""):
        backend = self.module.Backend(store_dir=self.store, state_dir=self.helper_state,
                                      wacli=self.binary, account_config=STATE / "whatsapp/accounts.yaml")
        backend.use_account(account)
        return backend

    async def status(self):
        if not self.binary.is_file():
            return {"ok": True, "authorized": False, "installed": False}
        if not self.version_checked:
            process = await asyncio.create_subprocess_exec(str(self.binary), "--version",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
            output, _ = await process.communicate()
            if output.decode(errors="replace").strip() != "wacli 0.17.1":
                raise ProviderError("DankChat requires wacli 0.17.1.")
            self.version_checked = True
        if self.login and self.login.task and not self.login.task.done():
            return {"ok": True, "authorized": self.login.state == "authorized", "installed": True,
                    "authState": self.login.state, "qrPath": self.login.qr.path, "linking": True}
        if not (self.store / "session.db").exists():
            return {"ok": True, "authorized": False, "installed": True,
                    "authState": self.login.state if self.login else "disconnected"}
        result = await asyncio.to_thread(self.backend().status)
        if result.get("authenticated") and result.get("online") and not result.get("sync_active"):
            await self.sync(True)
        return {"ok": result.get("ok", False), "authorized": result.get("authenticated", False), "installed": True,
                "authState": "authorized" if result.get("authenticated") else self.login.state if self.login else "disconnected"}

    async def call(self, action, data):
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
                raise ProviderError("Install wacli 0.17.1 first.")
            try:
                import qrcode
            except ImportError:
                raise ProviderError("QR dependencies are missing. Run scripts/setup-telegram.")
            await self.sync(False, wait=True)
            self.store.mkdir(parents=True, exist_ok=True, mode=0o700)
            directory = CACHE / "whatsapp-login"
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
        if action == "messages":
            result = await asyncio.to_thread(backend.messages, ident)
            await asyncio.to_thread(apply_receipts, self.helper_state / "receipts.sqlite", ident, result["messages"])
            return {"ok": True, "messages": messages("whatsapp", result["messages"])}
        if action == "download":
            await asyncio.to_thread(backend.download_media, ident, data["messageId"])
            return {"ok": True}
        if action == "pin":
            await asyncio.to_thread(backend.chat_action, ident, "pin" if data["pinned"] else "unpin")
            return {"ok": True}
        if action == "send":
            result = await asyncio.to_thread(backend.send, ident, data["text"], data.get("replyId", ""))
        elif action == "file":
            result = await asyncio.to_thread(backend.send_files, ident, [data["path"]], data.get("text", ""), data.get("replyId", ""))
        elif action == "acknowledge":
            result = await asyncio.to_thread(backend.acknowledge_notifications, ident)
        else:
            raise ProviderError("Unsupported WhatsApp action.")
        if not result.get("ok"):
            raise ProviderError("WhatsApp could not complete the action. Check the conversation before retrying.")
        return {"ok": True}

    async def close(self):
        if self.login:
            await self.login.cancel()
        await self.sync(False)


class Bridge:
    def __init__(self):
        self.providers = {}

    async def dispatch(self, request):
        action = request.get("action")
        if action == "configure":
            enabled = request.get("enabled", [])
            for name in list(self.providers):
                if name not in enabled:
                    await self.providers.pop(name).close()
            for name, cls in (("telegram", Telegram), ("whatsapp", WhatsApp)):
                if name in enabled and name not in self.providers:
                    self.providers[name] = cls()
            return {"ok": True}
        name = request.get("provider")
        if name not in self.providers:
            raise ProviderError("This service is disabled.")
        provider = self.providers[name]
        if action == "status":
            return await provider.status()
        if action not in {"chats", "messages", "send", "file", "read", "acknowledge", "login", "password", "download", "pin", "logout", "cancel_login"}:
            raise ProviderError("Unsupported action.")
        if action in {"messages", "send", "file", "read", "acknowledge", "download", "pin"}:
            target = request.get("chat")
            if not isinstance(target, dict) or target.get("provider") != name or not target.get("id"):
                raise ProviderError("The chat does not belong to this service.")
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
        return await provider.call(action, request)

    async def close(self):
        for provider in self.providers.values():
            await provider.close()


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
    locks = {name: asyncio.Lock() for name in ("telegram", "whatsapp", "")}
    tasks = set()
    output = sys.stdout
    sink = open(os.devnull, "w")
    sys.stdout = sink
    sys.stderr = sink

    async def respond(request):
        try:
            async with locks.get(request.get("provider", ""), locks[""]):
                result = await asyncio.wait_for(bridge.dispatch(request), timeout=210 if request.get("action") == "download" else 90)
        except ProviderError as exc:
            result = {"ok": False, "error": str(exc)}
        except Exception:
            result = {"ok": False, "error": "The service could not complete this request. Check the connection; do not resend without checking the conversation."}
        result["requestId"] = request.get("requestId")
        output.write(json.dumps(result, ensure_ascii=True) + "\n")
        output.flush()
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
