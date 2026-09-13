from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from bridge import Bridge, export_media, ProviderError


class ExportTests(unittest.IsolatedAsyncioTestCase):
    async def test_export_uses_provider_attachment_not_caller_supplied_source(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'cached.png'; source.write_bytes(b'synthetic image')
            destination = Path(directory) / 'saved.png'
            provider = AsyncMock()
            provider.call.return_value = {'ok': True, 'messages': [{'id': '1', 'mediaPath': str(source)}]}
            bridge = Bridge(); bridge.providers['telegram'] = provider
            result = await bridge.dispatch({'provider': 'telegram', 'action': 'export', 'chat': {'provider': 'telegram', 'id': 'synthetic'}, 'messageId': '1', 'source': '/untrusted/path', 'destination': str(destination)})
            self.assertTrue(result['ok'])
            self.assertEqual(destination.read_bytes(), source.read_bytes())
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
            self.assertEqual(len(list(Path(directory).iterdir())), 2)

    async def test_missing_media_does_not_create_export(self):
        provider = AsyncMock(); provider.call.return_value = {'ok': True, 'messages': []}
        bridge = Bridge(); bridge.providers['telegram'] = provider
        with self.assertRaises(ProviderError):
            await bridge.dispatch({'provider': 'telegram', 'action': 'export', 'chat': {'provider': 'telegram', 'id': 'synthetic'}, 'messageId': 'missing', 'destination': '/unused'})

    def test_export_replaces_file_and_rejects_relative_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'cached'; source.write_bytes(b'new')
            target = Path(directory) / 'saved'; target.write_bytes(b'old')
            export_media(source, target)
            self.assertEqual(target.read_bytes(), b'new')
            with self.assertRaises(ProviderError):
                export_media(source, 'relative-file')
