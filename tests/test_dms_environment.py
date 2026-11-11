import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
from dms_environment import find_source


class DmsDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.base = Path(self.directory.name)
        self.env = {'XDG_RUNTIME_DIR': str(self.base)}
        self.fallback = self.base / 'system'

    def source(self, name, timestamp=1):
        path = self.base / name
        (path / 'Widgets').mkdir(parents=True)
        (path / 'shell.qml').touch()
        os.utime(path / 'shell.qml', (timestamp, timestamp))
        for widget in ('DankPopout', 'DankFloatingWindow'):
            (path / 'Widgets' / (widget + '.qml')).touch()
        (path / 'DCommon/FileBrowser').mkdir(parents=True)
        (path / 'DCommon/FileBrowser/FilePicker.qml').touch()
        return path

    def find(self):
        return find_source(self.env, self.fallback)

    def test_preflight_discovers_both_runtime_layouts_without_override(self):
        for name in ('danklinux-shell/old', 'dms-shell/new'):
            with self.subTest(name=name):
                source = self.source(name)
                env = dict(os.environ, **self.env)
                env.pop('DANKCHAT_DMS_SOURCE', None)
                result = subprocess.run([sys.executable, str(ROOT / 'scripts/check-environment')],
                                        env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(str(source), result.stdout)
                # Only one layout may exist, as on a freshly installed host.
                (source / 'shell.qml').unlink()

    def test_most_recent_valid_source_across_both_layouts(self):
        old = self.source('danklinux-shell/old', 30)
        new = self.source('dms-shell/new', 20)
        self.source('dms-shell/incomplete', 40).joinpath('Widgets/DankPopout.qml').unlink()
        (self.base / 'dms-shell/incomplete/Widgets/DankFloatingWindow.qml').unlink()
        (self.base / 'dms-shell/incomplete/Widgets').rmdir()
        self.assertEqual(self.find(), old)
        os.utime(new / 'shell.qml', (50, 50))
        self.assertEqual(self.find(), new)

    def test_explicit_directory_and_shell_file_override_runtime(self):
        self.source('dms-shell/new', 30)
        explicit = self.source('custom')
        for path in (explicit, explicit / 'shell.qml'):
            self.env['DANKCHAT_DMS_SOURCE'] = str(path)
            self.assertEqual(self.find(), explicit)

    def test_invalid_explicit_source_does_not_silently_fall_back(self):
        self.source('dms-shell/new')
        self.env['DANKCHAT_DMS_SOURCE'] = str(self.base / 'missing')
        self.assertIsNone(self.find())

    def test_system_fallback_and_no_source(self):
        self.assertIsNone(self.find())
        self.source('system')
        self.assertEqual(self.find(), self.fallback)

    def test_broken_runtime_symlink_is_ignored(self):
        path = self.base / 'dms-shell/stale'
        path.mkdir(parents=True)
        (path / 'shell.qml').symlink_to(self.base / 'removed')
        self.source('system')
        self.assertEqual(self.find(), self.fallback)
