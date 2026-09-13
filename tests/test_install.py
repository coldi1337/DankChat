"""Exercise installer paths without calling the user's DMS or systemd."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class InstallTests(unittest.TestCase):
    def check_install(self, registry):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            config = base / 'config'
            plugins = config / 'DankMaterialShell/plugins'
            checkout = plugins / 'dankChat' if registry else base / 'checkout'
            (checkout / 'scripts').mkdir(parents=True)
            shutil.copy2(ROOT / 'scripts/install-local', checkout / 'scripts/install-local')
            commands = base / 'commands'; commands.mkdir()
            for command in ('dms', 'systemctl'):
                path = commands / command
                path.write_text('#!/bin/sh\nexit 0\n'); path.chmod(0o755)
            env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(base / 'data'), PATH=str(commands))
            subprocess.run([sys.executable, str(checkout / 'scripts/install-local')], env=env, check=True, capture_output=True)
            self.assertEqual(len(list(plugins.iterdir())), 1)
            self.assertEqual(next(plugins.iterdir()).resolve(), checkout)
            self.assertIn(str(checkout), (config / 'systemd/user/dankchat-whatsapp.service').read_text())
            self.assertIn('Terminal=false', (base / 'data/applications/dankchat.desktop').read_text())
            subprocess.run([sys.executable, str(checkout / 'scripts/install-local')], env=env, check=True, capture_output=True)

    def test_checkout_install(self):
        self.check_install(False)

    def test_registry_install_does_not_duplicate_plugin(self):
        self.check_install(True)
