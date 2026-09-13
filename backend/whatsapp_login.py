"""Private wacli QR lifecycle; never forward raw events or terminal output."""
import asyncio
import contextlib
import json
from types import SimpleNamespace
from qr_login import QrLogin


class WhatsAppLogin:
    def __init__(self, binary, store, directory, render):
        self.binary, self.store = str(binary), str(store)
        self.qr = QrLogin(directory, render, RuntimeError)
        self.state = "waiting"
        self.process = None
        self.task = None

    def event(self, line):
        try:
            event = json.loads(line)
            if not isinstance(event, dict):
                return
            kind = event.get("event")
            if kind == "qr_code" and self.state != "authorized":
                data = event.get("data")
                code = data.get("code") if isinstance(data, dict) else None
                if isinstance(code, str) and 0 < len(code) < 8192:
                    self.qr.publish(SimpleNamespace(url=code))
                    self.state = "waiting"
            elif kind == "connected":
                self.state = "authorized"
                self.qr.clear()
            elif kind == "logged_out":
                self.state = "failed"
                self.qr.clear()
        except (ValueError, TypeError):
            pass

    async def run(self):
        try:
            self.process = await asyncio.create_subprocess_exec(
                self.binary, "--store", self.store, "--events", "auth", "--qr-format", "text",
                "--idle-exit", "15s", stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE)
            async def consume():
                while line := await self.process.stderr.readline():
                    self.event(line)
                return await self.process.wait()
            code = await asyncio.wait_for(consume(), 600)
            if code or self.state != "authorized":
                self.state = "failed"
        except asyncio.CancelledError:
            raise
        except TimeoutError:
            self.state = "expired"
        except Exception:
            self.state = "failed"
        finally:
            await self.stop_process()
            self.qr.clear()

    async def stop_process(self):
        if self.process and self.process.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                self.process.terminate()
            try:
                await asyncio.wait_for(self.process.wait(), 5)
            except asyncio.TimeoutError:
                with contextlib.suppress(ProcessLookupError):
                    self.process.kill()
                await self.process.wait()

    async def cancel(self):
        if self.task and not self.task.done():
            self.task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.task
        self.qr.clear()
