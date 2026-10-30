"""Staged recovery keeps Linux ownership handling and supports hosts without it."""
import argparse
from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('backup_ownership', ROOT / 'scripts/utilities/relay_backup.py')
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class RestoreOwnershipTests(unittest.TestCase):
    def test_root_sets_container_ids_and_other_hosts_keep_host_ownership(self):
        for host in ('root', 'unprivileged', 'without-unix-api'):
            with self.subTest(host=host), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive = root / 'encrypted-fixture'
                archive.write_bytes(b'fixture')
                destination = root / 'staged'
                manifest = {'image_id': 'fixture:local', 'config_path': '/etc/tor/torrc'}
                args = argparse.Namespace(archive=str(archive), destination=str(destination), validation_image=None)
                def verified(_args, staging=None):
                    if staging:
                        keys = staging / 'data/keys'
                        keys.mkdir(parents=True)
                        (keys / 'fixture-key').write_bytes(b'synthetic identity')
                    return manifest
                chown = Mock()
                host_os = SimpleNamespace(chown=chown)
                if host != 'without-unix-api':
                    host_os.geteuid = Mock(return_value=0 if host == 'root' else 1000)
                with patch.object(backup, 'os', host_os), \
                        patch.object(backup, 'validate_archive', side_effect=verified), \
                        patch.object(backup, 'validate_restored_config') as config, redirect_stdout(io.StringIO()):
                    backup.restore(args)
                config.assert_called_once_with(destination, manifest, 'fixture:local')
                self.assertEqual((destination / 'data/keys/fixture-key').read_bytes(), b'synthetic identity')
                if host == 'root':
                    self.assertTrue(chown.called)
                    self.assertTrue(all(call.args[1:] == (100, 101) for call in chown.call_args_list))
                    self.assertIn(destination, [call.args[0] for call in chown.call_args_list])
                else:
                    chown.assert_not_called()
