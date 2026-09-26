"""Read image data only on an explicit paste action; never send it here."""
import asyncio
import io
import warnings
from pathlib import Path
import shutil
import tempfile
from urllib.parse import urlsplit, unquote


class ClipboardImages:
    def __init__(self, runtime):
        self.runtime = runtime
        self.directory = None

    async def read(self, *args, limit):
        process = await asyncio.create_subprocess_exec('wl-paste', *args,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        async def collect():
            chunks, size = [], 0
            while chunk := await process.stdout.read(65536):
                size += len(chunk)
                if size > limit:
                    raise ValueError('The clipboard image is too large (maximum 20 MB).')
                chunks.append(chunk)
            if await process.wait():
                raise ValueError('The clipboard could not be read.')
            return b''.join(chunks)
        try:
            return await asyncio.wait_for(collect(), timeout=10)
        finally:
            if process.returncode is None:
                process.kill()
            await process.wait()

    async def paste(self):
        if not shutil.which('wl-paste'):
            return {'ok': True, 'textFallback': True, 'error': 'Install wl-clipboard to paste images.'}
        types = (await self.read('--list-types', limit=16384)).decode().splitlines()
        mime = next((kind for kind in ['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/bmp', 'image/x-bmp', 'image/tiff'] if kind in types), None)
        if 'text/uri-list' in types:
            try:
                raw = (await self.read('--no-newline', '--type', 'text/uri-list', limit=65536)).decode()
                paths = []
                for line in raw.splitlines():
                    if not line.strip() or line.startswith('#'):
                        continue
                    uri = urlsplit(line.strip())
                    if uri.scheme != 'file' or uri.netloc not in ('', 'localhost'):
                        raise ValueError('Choose local files only.')
                    path = Path(unquote(uri.path))
                    if not path.is_absolute() or not path.is_file() or path.stat().st_size > 100 * 1024 * 1024:
                        raise ValueError('Choose a local file smaller than 100 MB.')
                    if str(path) not in paths:
                        paths.append(str(path))
                if len(paths) > 10:
                    raise ValueError('Choose up to 10 attachments.')
                if paths:
                    return {'ok': True, 'paths': paths}
            except (ValueError, OSError):
                if mime is None:
                    raise
        if mime is None:
            if any(kind.startswith('image/') for kind in types):
                raise ValueError('This clipboard image format is not supported. Copy it as PNG or attach the file.')
            return {'ok': True, 'textFallback': True}
        data = await self.read('--no-newline', '--type', mime, limit=20 * 1024 * 1024)
        if not data:
            raise ValueError('The clipboard image is empty.')
        data, suffix = await asyncio.to_thread(self.prepare_image, data)
        if self.directory is None:
            self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
            self.directory = tempfile.TemporaryDirectory(prefix='clipboard-', dir=self.runtime)
        if len(list(Path(self.directory.name).iterdir())) >= 20:
            raise ValueError('Too many pending clipboard images. Reload DankChat to clear them.')
        with tempfile.NamedTemporaryFile(prefix='screenshot-', suffix=suffix, dir=self.directory.name, delete=False) as output:
            output.write(data)
            return {'ok': True, 'paths': [output.name]}

    @staticmethod
    def prepare_image(data):
        try:
            from PIL import Image, ImageOps
        except ImportError as exc:
            raise ValueError('Image support is missing. Run python3 scripts/setup.') from exc
        try:
            with warnings.catch_warnings():
                warnings.simplefilter('error', Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(data)) as image:
                    if image.width * image.height > 40_000_000:
                        raise ValueError()
                    format_name = image.format
                    image.verify()
                suffix = {'PNG': '.png', 'JPEG': '.jpg', 'WEBP': '.webp', 'GIF': '.gif'}.get(format_name)
                if suffix:
                    return data, suffix
                with Image.open(io.BytesIO(data)) as image:
                    converted = ImageOps.exif_transpose(image).convert('RGBA')
                    output = io.BytesIO()
                    converted.save(output, format='PNG')
                    data = output.getvalue()
                if len(data) > 20 * 1024 * 1024:
                    raise ValueError()
                return data, '.png'
        except (OSError, ValueError, SyntaxError, Image.DecompressionBombWarning, Image.DecompressionBombError) as exc:
            raise ValueError('The clipboard image could not be decoded or is too large. Copy it again or attach the file.') from exc

    def discard(self, paths):
        if self.directory:
            directory = Path(self.directory.name)
            for value in paths:
                path = Path(value)
                if path.parent == directory:
                    path.unlink(missing_ok=True)

    def close(self):
        if self.directory:
            self.directory.cleanup()
            self.directory = None
