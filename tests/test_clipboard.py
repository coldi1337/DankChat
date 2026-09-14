import asyncio
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from clipboard_image import ClipboardImages

class ClipboardTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.clip = ClipboardImages(Path(self.temp.name))
        self.which = patch('clipboard_image.shutil.which', return_value='/fake/wl-paste')
        self.which.start()
    async def asyncTearDown(self):
        self.clip.close(); self.temp.cleanup(); self.which.stop()
    async def test_image_is_staged_privately_and_removed_on_close(self):
        self.clip.read = AsyncMock(side_effect=[b'image/png\ntext/plain', b'synthetic-image'])
        result = await self.clip.paste()
        path = Path(result['paths'][0])
        self.assertEqual(path.read_bytes(), b'synthetic-image')
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
        self.clip.close(); self.assertFalse(path.exists())
    async def test_multiple_file_uris_keep_spaces_and_deduplicate(self):
        files = [Path(self.temp.name) / name for name in ['one image.png', 'two.pdf']]
        for path in files: path.write_bytes(b'fixture')
        self.clip.read = AsyncMock(side_effect=[b'text/uri-list', ('# files\r\n' + '\r\n'.join(p.as_uri() for p in files + files[:1])).encode()])
        self.assertEqual((await self.clip.paste())['paths'], list(map(str, files)))
    async def test_remote_uri_is_never_downloaded(self):
        self.clip.read = AsyncMock(side_effect=[b'text/uri-list', b'https://example.com/picture.png'])
        with self.assertRaisesRegex(ValueError, 'local'): await self.clip.paste()
    async def test_text_paste_does_not_read_clipboard_text(self):
        self.clip.read = AsyncMock(return_value=b'text/plain')
        self.assertTrue((await self.clip.paste())['textFallback'])
        self.clip.read.assert_awaited_once()
    async def test_unavailable_tool_retains_text_paste(self):
        with patch('clipboard_image.shutil.which', return_value=None):
            self.assertTrue((await self.clip.paste())['textFallback'])
    async def test_discard_cannot_delete_user_files(self):
        outside = Path(self.temp.name) / 'original.png'; outside.write_bytes(b'original')
        self.clip.read = AsyncMock(side_effect=[b'image/png', b'fixture'])
        staged = Path((await self.clip.paste())['paths'][0])
        self.clip.discard([str(staged), str(outside)])
        self.assertFalse(staged.exists()); self.assertTrue(outside.exists())
    async def test_empty_image_is_rejected(self):
        self.clip.read = AsyncMock(side_effect=[b'image/png', b''])
        with self.assertRaisesRegex(ValueError, 'empty'): await self.clip.paste()
