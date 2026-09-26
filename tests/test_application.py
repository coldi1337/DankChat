import asyncio
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
from accounts import Accounts, instance_key
from bridge import Bridge, Telegram, WhatsApp, ProviderError
from request_runner import RequestRunner
from storage import Storage
from updates import Updates


class ApplicationTests(unittest.IsolatedAsyncioTestCase):
    async def test_accounts_keep_default_paths_and_isolate_new_sessions(self):
        with tempfile.TemporaryDirectory() as directory:
            registry = Accounts(Path(directory) / 'accounts.json')
            original = registry.rows()
            first = registry.add('telegram', 'Personal')
            second = registry.add('telegram', 'Work')
            registry.rename('telegram', first['id'], 'Family')
            self.assertEqual(registry.rows()[:2], original)
            self.assertNotEqual(first['id'], second['id'])
            self.assertEqual(registry.path.stat().st_mode & 0o777, 0o600)
            providers = [Telegram(r) for r in ('', first['id'], second['id'])]
            self.assertEqual(len({p.config for p in providers}), 3)
            self.assertEqual(len({p.cache for p in providers}), 3)
            self.assertEqual(providers[0].config.name, 'telegram')
            wa = [WhatsApp(r) for r in ('', first['id'], second['id'])]
            self.assertEqual(len({p.store for p in wa}), 3)
            self.assertEqual(len({p.unit for p in wa}), 3)
            self.assertEqual(wa[0].unit, 'dankchat-whatsapp.service')
            for invalid in ('../escape', 'other', 'a' * 33):
                with self.assertRaises(ValueError): Telegram(invalid)

    async def test_same_chat_id_routes_only_to_selected_account(self):
        bridge = Bridge(); first, second = 'a' * 32, 'b' * 32
        providers = [AsyncMock(), AsyncMock()]
        bridge.providers = {instance_key('telegram', account): provider for account, provider in zip((first, second), providers)}
        for provider in providers: provider.call.return_value = {'ok': True}
        target = {'provider': 'telegram', 'id': '123', 'account': second}
        for action in ('read', 'messages', 'browse', 'edit'):
            await bridge.dispatch({'provider': 'telegram', 'action': action, 'chat': target, 'text': 'Edited', 'messageId': '10'})
        providers[0].call.assert_not_called()
        self.assertEqual(providers[1].call.await_count, 4)
        with self.assertRaises(ProviderError):
            await bridge.dispatch({'provider': 'telegram', 'account': first, 'action': 'read', 'chat': target})
        self.assertEqual(providers[0].call.await_count, 0)

    async def test_account_download_lanes_do_not_block_another_account(self):
        runner = RequestRunner(); entered, release = asyncio.Event(), asyncio.Event()
        async def dispatch(request):
            if request['account'] == 'a' * 32:
                entered.set(); await release.wait()
            return {'ok': True}
        pending = asyncio.create_task(runner.run({'provider': 'whatsapp', 'account': 'a' * 32, 'action': 'download'}, dispatch))
        await asyncio.wait_for(entered.wait(), 1)
        try:
            self.assertTrue((await asyncio.wait_for(runner.run({'provider': 'whatsapp', 'account': 'b' * 32, 'action': 'download'}, dispatch), .3))['ok'])
        finally:
            release.set(); await pending
        self.assertNotIn('a' * 32, str(runner.diagnostics))

    async def test_telegram_edit_checks_ownership_before_writing(self):
        provider = Telegram(); provider.connect = AsyncMock()
        client = SimpleNamespace(is_user_authorized=AsyncMock(return_value=True), get_input_entity=AsyncMock(return_value=123), get_messages=AsyncMock(return_value=SimpleNamespace(id=10, out=False, chat_id=123)), edit_message=AsyncMock())
        provider.daemon = SimpleNamespace(client=client, dialogs_cache=[{'id':123}], messages_cache={})
        data = {'chat': {'id': '123'}, 'messageId': '10', 'text': 'Edited'}
        with self.assertRaises(ProviderError): await provider.call('edit', data)
        client.edit_message.assert_not_called()
        client.get_messages.return_value.out = True
        self.assertTrue((await provider.call('edit', data))['ok'])
        client.edit_message.assert_awaited_once_with(123, 10, 'Edited')

    async def test_telegram_auto_read_does_not_acknowledge_unfetched_messages(self):
        provider = Telegram(); provider.connect = AsyncMock()
        client = SimpleNamespace(is_user_authorized=AsyncMock(return_value=True), send_read_acknowledge=AsyncMock())
        provider.daemon = SimpleNamespace(client=client, dialogs_cache=[{'id':123}], messages_cache={})
        await provider.call('read', {'chat': {'id':'123'}, 'messageId':'42'})
        client.send_read_acknowledge.assert_awaited_once_with(123,max_id=42)

    async def test_whatsapp_sync_is_not_restarted_while_write_yields_store(self):
        provider = WhatsApp(); provider.binary = Path(__file__); provider.version_checked = True
        provider.backend = Mock(return_value=SimpleNamespace(status=Mock(return_value={'ok': True, 'authenticated': True, 'online':True, 'sync_active':False})))
        provider.sync = AsyncMock(); provider.maintenance = 1
        with patch('pathlib.Path.exists', return_value=True):
            await provider.status()
            provider.sync.assert_not_called()
            provider.maintenance = 0; await provider.status()
            provider.sync.assert_awaited_once_with(True)

    async def test_expired_media_has_actionable_error_and_does_not_write(self):
        provider = WhatsApp(); backend = Mock(); provider.backend = Mock(return_value=backend)
        backend.download_media.side_effect = provider.module.WhatsAppError('download failed with status code 403')
        with self.assertRaisesRegex(ProviderError, 'Open it on your phone'):
            await provider.call('download', {'chat': {'id':'synthetic'}, 'messageId':'m1'})
        backend.download_media.assert_called_once_with('synthetic', 'm1', read_only=True)

    def test_cleanup_preserves_accounts_originals_active_media_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); cache = root/'cache'; state=root/'state'
            media=cache/'telegram/media'; media.mkdir(parents=True)
            active=media/'active.jpg'; active.write_bytes(b'active')
            old=media/'old.jpg'; old.write_bytes(b'old')
            original=root/'original.jpg'; original.write_bytes(b'original')
            (media/'link').symlink_to(original)
            database=state/'whatsapp/store/session.db'; database.parent.mkdir(parents=True); database.write_bytes(b'credentials')
            accountmedia=cache/'telegram'/('a'*32)/'media'; accountmedia.mkdir(parents=True); (accountmedia/'old.jpg').write_bytes(b'old')
            result=Storage(cache,state).clean(clear=True,protect=[str(active)])
            self.assertEqual(result['removed'],2)
            self.assertTrue(active.exists()); self.assertTrue(original.exists()); self.assertTrue(database.exists())

    def test_release_checks_cache_and_compare_versions_without_trusting_urls(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); (root/'plugin.json').write_text('{"version":"0.4.0"}')
            updates=Updates(root,root/'cache.json')
            response=Mock(); response.__enter__=Mock(return_value=response); response.__exit__=Mock(return_value=None)
            response.read.return_value=json.dumps({'tag_name':'v0.5.0','html_url':'https://untrusted.example'}).encode()
            with patch('updates.urllib.request.urlopen',return_value=response) as fetch:
                result=updates.check(); self.assertTrue(result['available'])
                self.assertEqual(result['releaseUrl'],'https://github.com/coldi1337/DankChat/releases/tag/v0.5.0')
                updates.check(); self.assertEqual(fetch.call_count,1)
            with patch('updates.urllib.request.urlopen',side_effect=OSError()):
                self.assertFalse(updates.check(force=True)['ok'])

    async def test_search_validation_rejects_unknown_categories_and_bad_offsets(self):
        bridge=Bridge(); provider=AsyncMock(); bridge.providers={'telegram':provider}
        for extra in ({'category':'unsupported'}, {'offset':'../file'}, {'query':['unsafe']}):
            with self.assertRaises(ProviderError):
                await bridge.dispatch({'provider':'telegram','action':'browse','chat':{'provider':'telegram','id':'1'}, **extra})
        provider.call.assert_not_called()

    async def test_notifications_escape_markup_and_do_not_use_a_shell(self):
        from notifications import deliver
        process=SimpleNamespace(returncode=0,wait=AsyncMock(return_value=0))
        with patch('notifications.shutil.which', return_value='/usr/bin/notify-send'), patch('notifications.asyncio.create_subprocess_exec',return_value=process) as spawn:
            self.assertTrue(await deliver('Test','<b>message</b> $(ignored)',False))
            args=spawn.call_args.args
            self.assertIn('--hint=boolean:suppress-sound:true',args)
            self.assertEqual(args[-1],'&lt;b&gt;message&lt;/b&gt; $(ignored)')


class HistoryTests(unittest.TestCase):
    def setUp(self):
        spec=importlib.util.spec_from_file_location('wa_test_fixture',ROOT/'vendor/whatsapp/tests/test_backend.py')
        self.module=importlib.util.module_from_spec(spec)
        with patch.dict(os.environ, {"WHATSAPP_SCRIPT": str(ROOT/"vendor/whatsapp/bin/whatsapp_client.py")}):
            spec.loader.exec_module(self.module)
        self.fixture=self.module.BackendTests(methodName='runTest'); self.fixture.setUp()
    def tearDown(self): self.fixture.tearDown()

    def test_search_and_media_filters_run_before_pagination(self):
        backend=self.fixture.backend
        target='team@g.us'
        rows=backend.messages(target, limit=1, query='mockup')['messages']
        self.assertEqual([r['id'] for r in rows], ['t2'])
        images=backend.messages(target, category='images', limit=1)['messages']
        self.assertEqual([r['id'] for r in images], ['t2'])
        self.assertEqual(backend.messages(target,offset=1,limit=1)['messages'][0]['id'], 't2')
        self.assertEqual(backend.messages(target,offset=1000000)['messages'],[])

    def test_readonly_download_never_yields_sync_and_caches_completed_file(self):
        import sqlite3, subprocess
        from contextlib import closing
        backend = self.fixture.backend
        with closing(sqlite3.connect(self.fixture.store/'wacli.db')) as db, db:
            db.execute("UPDATE messages SET local_path='' WHERE msg_id='t2'")
        def download(args, **kwargs):
            self.assertIn('--read-only', args)
            Path(args[args.index('--output')+1]).write_bytes(b'image')
            return subprocess.CompletedProcess(args,0,'{"success":true}','')
        with patch.object(backend, '_run',side_effect=download) as run, patch.object(backend, '_write') as write:
            first = backend.download_media('team@g.us','t2',read_only=True)
            second = backend.download_media('team@g.us','t2',read_only=True)
            self.assertEqual(first['local_path'],second['local_path']); self.assertEqual(run.call_count,1)
            self.assertEqual(Path(first['local_path']).stat().st_mode & 0o777,0o600)
            write.assert_not_called()
