import hashlib
import importlib.machinery
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch, AsyncMock

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('dankchat_setup', str(ROOT / 'scripts/setup'))
spec = importlib.util.spec_from_loader(loader.name, loader)
setup = importlib.util.module_from_spec(spec)
loader.exec_module(setup)


def release(symlink=False):
    target = io.BytesIO()
    with tarfile.open(fileobj=target, mode='w:gz') as archive:
        entry = tarfile.TarInfo('wacli')
        if symlink:
            entry.type = tarfile.SYMTYPE
            entry.linkname = '/etc/passwd'
            archive.addfile(entry)
        else:
            content = b'fixture binary'
            entry.size = len(content)
            archive.addfile(entry, io.BytesIO(content))
    data = target.getvalue()
    filename = 'wacli_0.19.0_linux_amd64.tar.gz'
    return data, f'{hashlib.sha256(data).hexdigest()}  {filename}\n', filename


class SetupTests(unittest.TestCase):
    def test_checksum_required_before_reading_archive(self):
        archive, checksums, filename = release()
        self.assertEqual(setup.verified_binary(archive, checksums, filename), b'fixture binary')
        for changed in (archive + b'corruption', b'not an archive'):
            with self.assertRaisesRegex(ValueError, 'checksum'):
                setup.verified_binary(changed, checksums, filename)
        with self.assertRaisesRegex(ValueError, 'checksum'):
            setup.verified_binary(archive, checksums, 'other.tar.gz')

    def test_archive_symlink_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'archive contents'):
            setup.verified_binary(*release(symlink=True))

    def test_failed_interface_check_preserves_existing_binary(self):
        archive, checksums, _ = release()
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'wacli'
            destination.write_bytes(b'old binary')
            with patch.object(setup.platform, 'machine', return_value='x86_64'), patch.object(setup.platform, 'system', return_value='Linux'), patch.object(setup, 'download', side_effect=[archive, checksums.encode()]), patch.object(setup, 'check', AsyncMock(side_effect=ValueError('incompatible'))):
                with self.assertRaisesRegex(ValueError, 'incompatible'):
                    setup.install_wacli(destination)
            self.assertEqual(destination.read_bytes(), b'old binary')
            self.assertEqual(list(Path(directory).iterdir()), [destination])

    def test_successful_update_keeps_backup(self):
        archive, checksums, _ = release()
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'wacli'
            destination.write_bytes(b'old binary')
            with patch.object(setup.platform, 'machine', return_value='x86_64'), patch.object(setup.platform, 'system', return_value='Linux'), patch.object(setup, 'download', side_effect=[archive, checksums.encode()]), patch.object(setup, 'check', AsyncMock(return_value='wacli 0.19.0')):
                setup.install_wacli(destination)
            self.assertEqual(destination.read_bytes(), b'fixture binary')
            self.assertTrue(destination.stat().st_mode & 0o100)
            backup, = Path(directory).glob('dankchat-wacli-backup-*/wacli')
            self.assertEqual(backup.read_bytes(), b'old binary')
