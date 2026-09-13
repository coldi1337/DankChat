"""Rotate Telegram login codes at the expiry supplied by Telegram itself."""
import asyncio
from pathlib import Path
import secrets


class QrLogin:
    def __init__(self, directory, render, password_error):
        self.directory = Path(directory)
        self.render = render
        self.password_error = password_error
        self.path = ""
        self.state = "waiting"

    def publish(self, qr):
        path = self.directory / ("login-" + secrets.token_hex(8) + ".png")
        self.render(qr.url).save(path)
        path.chmod(0o600)
        old = self.path
        self.path = str(path)
        if old:
            Path(old).unlink(missing_ok=True)

    def clear(self):
        if self.path:
            Path(self.path).unlink(missing_ok=True)
            self.path = ""

    async def run(self, qr):
        try:
            # Bound unattended linking to ten codes. Each code uses the server's expiry.
            for attempt in range(10):
                self.publish(qr)
                try:
                    await qr.wait()
                    self.state = "authorized"
                    return
                except asyncio.TimeoutError:
                    if attempt < 9:
                        await qr.recreate()
            self.state = "expired"
        except self.password_error:
            self.state = "password"
        except asyncio.CancelledError:
            raise
        except Exception:
            self.state = "failed"
        finally:
            self.clear()
