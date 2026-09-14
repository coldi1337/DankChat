import asyncio
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from voice import VoiceRecorder
from bridge import Bridge, ProviderError, Telegram, WhatsApp


class VoiceTests(unittest.IsolatedAsyncioTestCase):
    async def test_real_encoder_stop_preview_and_private_cleanup_without_microphone(self):
        real_spawn = asyncio.create_subprocess_exec
        async def synthetic_spawn(*args, **kwargs):
            args = list(args)
            pos = args.index('-f')
            self.assertEqual(args[pos:pos + 4], ['-f', 'pulse', '-i', 'default'])
            args[pos:pos + 4] = ['-re', '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=mono']
            return await real_spawn(*args, **kwargs)
        with tempfile.TemporaryDirectory() as directory:
            recorder = VoiceRecorder(Path(directory))
            with patch('voice.asyncio.create_subprocess_exec', side_effect=synthetic_spawn):
                await recorder.start()
            with self.assertRaises(ValueError):
                await recorder.start()
            await asyncio.sleep(0.8)
            result = await recorder.stop()
            path = Path(result['path'])
            self.assertTrue(path.read_bytes().startswith(b'OggS'))
            self.assertIn(b'OpusHead', path.read_bytes()[:100])
            self.assertGreater(recorder.duration, 0)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(recorder.validated_path(str(path)), str(path))
            with self.assertRaises(ValueError):
                recorder.validated_path('/tmp/not-our-recording.ogg')
            await recorder.discard()
            self.assertFalse(path.exists())
            self.assertFalse(list(Path(directory).iterdir()))

    async def test_unavailable_microphone_cleans_draft(self):
        with tempfile.TemporaryDirectory() as directory:
            recorder = VoiceRecorder(Path(directory))
            with patch('voice.asyncio.create_subprocess_exec', new=AsyncMock(return_value=Mock(returncode=1))):
                with self.assertRaisesRegex(ValueError, 'microphone'):
                    await recorder.start()
            self.assertFalse(list(Path(directory).iterdir()))

    async def test_voice_send_uses_owned_draft_and_cleans_only_after_success(self):
        bridge = Bridge()
        provider = AsyncMock()
        bridge.providers['telegram'] = provider
        request = {'provider': 'telegram', 'action': 'voice', 'chat': {'provider': 'telegram', 'id': '123'}, 'path': '/tmp/voice.ogg'}
        with self.assertRaises(ProviderError):
            await bridge.dispatch(request)
        provider.call.assert_not_called()
        bridge.voice = Mock(validated_path=Mock(return_value=request['path']), discard=AsyncMock())
        provider.call.side_effect = RuntimeError('synthetic send failure')
        with self.assertRaises(RuntimeError):
            await bridge.dispatch(request)
        bridge.voice.discard.assert_not_awaited()
        provider.call.side_effect = None
        provider.call.return_value = {'ok': True}
        await bridge.dispatch(request)
        bridge.voice.discard.assert_awaited_once()

    async def test_telegram_uses_voice_note_flag_and_exact_chat_reply(self):
        provider = Telegram()
        provider.connect = AsyncMock()
        provider.daemon = AsyncMock()
        provider.daemon.client.is_user_authorized.return_value = True
        provider.daemon.dialogs_cache = [{'id': 123}]
        provider.daemon.send_file_to_chat.return_value = {'success': True}
        await provider.call('voice', {'chat': {'id': '123'}, 'path': '/tmp/synthetic.ogg', 'replyId': '7', 'duration': 3})
        provider.daemon.send_file_to_chat.assert_awaited_once_with('123', '/tmp/synthetic.ogg', reply_to='7', voice_note=True, voice_duration=3)
        with self.assertRaises(ProviderError):
            await provider.call('voice', {'chat': {'id': '999'}, 'path': '/tmp/synthetic.ogg'})

    async def test_whatsapp_routes_to_voice_sender_and_cleans_helper_copy(self):
        provider = WhatsApp()
        backend = Mock()
        provider.backend = Mock(return_value=backend)
        with tempfile.TemporaryDirectory() as directory:
            source, staged = Path(directory) / 'source.ogg', Path(directory) / 'staged.ogg'
            source.write_bytes(b'synthetic')
            backend.voice_draft.return_value = {'path': str(staged)}
            backend.send_voice.return_value = {'ok': True}
            await provider.call('voice', {'chat': {'id': 'synthetic'}, 'path': str(source), 'replyId': '7'})
            backend.send_voice.assert_called_once_with('synthetic', str(staged), '7')
            backend.voice_draft.assert_called_with('discard', str(staged))
            self.assertTrue(source.exists())
