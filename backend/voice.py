"""Explicit, bounded microphone capture into a private, disposable OGG/Opus draft."""
import asyncio
import contextlib
import math
from pathlib import Path
import shutil
import tempfile


class VoiceRecorder:
    def __init__(self, runtime):
        self.runtime = runtime
        self.directory = None
        self.process = None
        self.path = None
        self.ready = False
        self.duration = 0

    async def start(self):
        if self.directory:
            raise ValueError('Discard the current recording first.')
        if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
            raise ValueError('Install FFmpeg to record voice messages.')
        self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.directory = tempfile.TemporaryDirectory(prefix='voice-', dir=self.runtime)
        self.path = Path(self.directory.name) / 'voice.ogg'
        self.path.touch(mode=0o600)
        try:
            self.process = await asyncio.create_subprocess_exec(
                'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                '-f', 'pulse', '-i', 'default', '-t', '300', '-ac', '1',
                '-ar', '48000', '-c:a', 'libopus', '-b:a', '32k', str(self.path),
                stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL)
            await asyncio.sleep(0.25)
            if self.process.returncode is not None:
                raise ValueError('The microphone could not be opened. Check the default input device and audio service.')
        except BaseException:
            await self.discard()
            raise
        return {'ok': True}

    async def stop(self):
        if not self.process:
            raise ValueError('No recording is running.')
        if self.process.returncode is None:
            with contextlib.suppress(BrokenPipeError, ConnectionResetError):
                self.process.stdin.write(b'q\n')
                await self.process.stdin.drain()
            try:
                await asyncio.wait_for(self.process.wait(), 5)
            except asyncio.TimeoutError:
                await self.discard()
                raise ValueError('The recording could not be finished. Please record it again.')
        if self.process.returncode != 0 or not self.path or self.path.stat().st_size < 100:
            await self.discard()
            raise ValueError('The recording is empty or unavailable. Check your microphone.')
        probe = await asyncio.create_subprocess_exec('ffprobe', '-v', 'error',
            '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', str(self.path),
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        try:
            output, _ = await asyncio.wait_for(probe.communicate(), 5)
            duration = float(output.strip())
            if probe.returncode or not math.isfinite(duration) or duration <= 0:
                raise ValueError()
            self.duration = max(1, math.ceil(duration))
        except (ValueError, asyncio.TimeoutError):
            await self.discard()
            raise ValueError('The recording is empty or unavailable. Check your microphone.')
        finally:
            if probe.returncode is None:
                probe.kill()
            await probe.wait()
        self.ready = True
        return {'ok': True, 'path': str(self.path)}

    def validated_path(self, value):
        if not self.ready or not self.path or str(self.path) != value or not self.path.is_file():
            raise ValueError('Record a voice message before sending it.')
        return str(self.path)

    async def discard(self):
        if self.process and self.process.returncode is None:
            self.process.kill()
            await self.process.wait()
        self.process = None
        self.ready = False
        if self.directory:
            self.directory.cleanup()
        self.directory = self.path = None
