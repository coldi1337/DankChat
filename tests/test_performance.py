import asyncio
import importlib.util
import importlib.machinery
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from request_runner import RequestRunner
from sent_messages import SentMessages
from wacli_compat import supported_version


class SchedulingTests(unittest.IsolatedAsyncioTestCase):
    async def test_download_does_not_delay_send_and_all_transfers_block_logout(self):
        runner = RequestRunner()
        started, release = asyncio.Event(), asyncio.Event()
        calls = []
        async def dispatch(request):
            calls.append(request['action'])
            if request['action'] == 'download':
                started.set(); await release.wait()
            return {'ok': True}
        download = asyncio.create_task(runner.run({'provider': 'telegram', 'action': 'download'}, dispatch))
        await started.wait()
        await asyncio.wait_for(runner.run({'provider': 'telegram', 'action': 'file'}, dispatch), .25)
        logout = asyncio.create_task(runner.run({'provider': 'telegram', 'action': 'logout'}, dispatch))
        await asyncio.sleep(.02)
        self.assertNotIn('logout', calls)
        release.set(); await asyncio.gather(download, logout)

    async def test_chat_list_does_not_delay_open_chat_or_presence(self):
        runner = RequestRunner()
        started, release = asyncio.Event(), asyncio.Event()
        async def dispatch(request):
            if request['action'] == 'chats': started.set(); await release.wait()
            return {'ok': True}
        listing = asyncio.create_task(runner.run({'provider': 'telegram', 'action': 'chats'}, dispatch))
        await started.wait()
        for action in ('messages', 'presence'):
            await asyncio.wait_for(runner.run({'provider': 'telegram', 'action': action}, dispatch), .25)
        release.set(); await listing

    async def test_download_concurrency_is_bounded_per_provider(self):
        runner = RequestRunner()
        for provider, expected in [('telegram', 2), ('whatsapp', 1)]:
            release = asyncio.Event(); count = 0
            async def dispatch(request):
                nonlocal count
                count += 1; await release.wait()
                return {'ok': True}
            tasks = [asyncio.create_task(runner.run({'provider': provider, 'action': 'download'}, dispatch)) for _ in range(3)]
            await asyncio.sleep(.03)
            self.assertEqual(count, expected)
            release.set(); await asyncio.gather(*tasks)


class SentPreviewTests(unittest.TestCase):
    def test_confirmed_preview_survives_clipboard_cleanup_and_merges_receipts(self):
        for provider, result in [('telegram', {'message_id': 123}), ('whatsapp', {'items': [{'id': '123'}]})]:
            with self.subTest(provider=provider), tempfile.TemporaryDirectory() as directory:
                base = Path(directory); source = base / 'image.png'; source.write_bytes(b'synthetic')
                cache = SentMessages(base / 'runtime'); target = {'id': 'chat', 'account': 'one'}
                sent = cache.remember(provider, target, result, {'path': str(source), 'text': 'Caption'})
                source.unlink()
                self.assertEqual(Path(sent['mediaPath']).read_bytes(), b'synthetic')
                self.assertEqual(Path(sent['mediaPath']).stat().st_mode & 0o777, 0o600)
                self.assertEqual(cache.merge(target, []), [sent])
                incoming = dict(sent, mediaPath='', deliveryStatus='read')
                merged = cache.merge(target, [incoming])
                self.assertEqual(len(merged), 1)
                self.assertEqual(merged[0]['deliveryStatus'], 'read')
                self.assertTrue(merged[0]['mediaPath'])
                self.assertEqual(cache.merge({'id': 'other', 'account': 'one'}, []), [])
                cache.forget(target, '123'); self.assertFalse(cache.merge(target, []))
                cache.close()

    def test_missing_confirmation_and_failed_copy_do_not_invent_or_fail_send(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = SentMessages(Path(directory))
            self.assertIsNone(cache.remember('telegram', {'id': 'chat'}, {}, {}))
            row = cache.remember('telegram', {'id': 'chat'}, {'message_id': 42}, {'path': '/missing/file.png'})
            self.assertEqual(row['id'], '42'); self.assertEqual(row['mediaPath'], '')
            with patch('sent_messages.time.time', return_value=10**12):
                self.assertEqual(cache.merge({'id': 'chat'}, []), [])
            cache.close()

    def test_wacli_version_floor_accepts_new_releases(self):
        for version in ('0.17.1', '0.18.0', '0.19.0', '0.20.0', '1.0.0'):
            self.assertTrue(supported_version('wacli ' + version))
        for version in ('wacli 0.17.0', 'wacli 0.9.0', 'unexpected', 'wacli 0.19'):
            self.assertFalse(supported_version(version))

    def test_dms_preflight_detects_missing_widget(self):
        loader = importlib.machinery.SourceFileLoader('preflight', str(Path(__file__).resolve().parents[1] / 'scripts/check-environment'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec); loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory); (source / 'Widgets').mkdir()
            self.assertIn('DankPopout', module.check_widgets(source))
            for name in ('DankPopout', 'DankFloatingWindow'):
                (source / 'Widgets' / (name + '.qml')).touch()
            self.assertEqual(module.check_widgets(source), [])

class TelegramDownloadTests(unittest.IsolatedAsyncioTestCase):
    async def test_download_is_published_only_after_completion_and_cancel_cleans_stage(self):
        # Exercise the actual upstream command branch without importing a live Telethon client.
        import ast, os
        from types import SimpleNamespace
        from unittest.mock import AsyncMock
        source = Path(__file__).resolve().parents[1] / 'vendor/telegram/telegram_client.py'
        tree = ast.parse(source.read_text())
        method = next(node for node in ast.walk(tree) if isinstance(node, ast.AsyncFunctionDef) and node.name == 'execute_command')
        namespace = {'os': os, 'tempfile': tempfile}
        module = ast.Module(body=[method], type_ignores=[])
        exec(compile(ast.fix_missing_locations(module), str(source), 'exec'), namespace)
        with tempfile.TemporaryDirectory() as directory:
            namespace['MEDIA_DIR'] = directory
            target = Path(directory) / 'photo_9_1.jpg'
            client = SimpleNamespace(is_user_authorized=AsyncMock(return_value=True), get_entity=AsyncMock(return_value=object()), get_messages=AsyncMock(return_value=SimpleNamespace(media=object())))
            async def download(media, file):
                Path(file).write_bytes(b'partial')
                self.assertFalse(target.exists())
                await asyncio.sleep(0)
                Path(file).write_bytes(b'complete')
                return file
            client.download_media = download
            daemon = SimpleNamespace(client=client)
            request = {'action': 'download_media', 'chat_id': 1, 'message_id': 9, 'media_type': 'photo'}
            result = await namespace['execute_command'](daemon, request)
            self.assertTrue(result['success']); self.assertEqual(target.read_bytes(), b'complete')
            target.unlink()
            async def cancelled(media, file):
                Path(file).write_bytes(b'partial')
                raise asyncio.CancelledError()
            client.download_media = cancelled
            with self.assertRaises(asyncio.CancelledError):
                await namespace['execute_command'](daemon, request)
            self.assertFalse(target.exists()); self.assertEqual(list(Path(directory).iterdir()), [])
