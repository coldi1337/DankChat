import asyncio
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from qr_login import QrLogin


class PasswordRequired(Exception):
    pass


class FakeImage:
    def save(self, path):
        Path(path).write_bytes(b"synthetic-qr")


class QrTests(unittest.IsolatedAsyncioTestCase):
    async def test_expired_code_rotates_with_new_image_and_uses_server_expiry(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            flow = QrLogin(directory, lambda url: FakeImage(), PasswordRequired)
            qr = AsyncMock()
            qr.url = "synthetic"

            async def wait():
                paths.append(flow.path)
                if len(paths) == 1:
                    raise asyncio.TimeoutError

            qr.wait.side_effect = wait
            await flow.run(qr)
            self.assertEqual(flow.state, "authorized")
            self.assertEqual(qr.wait.call_args_list[0].kwargs, {})
            qr.recreate.assert_awaited_once()
            self.assertNotEqual(paths[0], paths[1])
            self.assertFalse(any(Path(p).exists() for p in paths))

    async def test_two_factor_password_hides_qr(self):
        with tempfile.TemporaryDirectory() as directory:
            flow = QrLogin(directory, lambda url: FakeImage(), PasswordRequired)
            qr = AsyncMock(); qr.wait.side_effect = PasswordRequired
            await flow.run(qr)
            self.assertEqual(flow.state, "password")
            self.assertEqual(flow.path, "")

    async def test_cancellation_removes_private_qr(self):
        with tempfile.TemporaryDirectory() as directory:
            flow = QrLogin(directory, lambda url: FakeImage(), PasswordRequired)
            qr = AsyncMock(); qr.wait.side_effect = asyncio.CancelledError
            with self.assertRaises(asyncio.CancelledError):
                await flow.run(qr)
            self.assertEqual(list(Path(directory).iterdir()), [])
