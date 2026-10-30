"""Authenticate updates before changing a source pin or building Tor."""
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess as sp
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


source = module('tor_source', ROOT / 'build/tor/source.py')
updater = module('tor_updater', ROOT / 'scripts/release/update-tor-source.py')
samples = module('sample_config', ROOT / 'scripts/testing/sample_config.py')
preflight = module('tor_preflight', ROOT / 'build/tor/preflight.py')
SIGNER = source.TRUSTED_SIGNERS[0]
DATA = b'fixture source archive'
LOCK = {'version': '0.4.9.15', 'sha256': hashlib.sha256(DATA).hexdigest(), 'signing_fingerprint': SIGNER}


class TorSourceTests(unittest.TestCase):
    def test_emulated_kernel_rejection_preserves_sandbox_test_requirement(self):
        libc = Mock()
        libc.prctl.return_value = -1
        with patch.object(preflight.ctypes, 'CDLL', return_value=libc), \
                patch.object(preflight.ctypes, 'get_errno', return_value=22):
            with self.assertRaisesRegex(RuntimeError, 'QEMU user-mode.*Tests remain enabled'):
                preflight.require_seccomp()

    def test_native_kernel_accepts_existing_or_absent_outer_filter(self):
        for mode in (0, 2):
            libc = Mock()
            libc.prctl.return_value = mode
            with self.subTest(mode=mode), \
                    patch.object(preflight.ctypes, 'CDLL', return_value=libc):
                self.assertEqual(preflight.require_seccomp(), mode)

    def test_sample_fixtures_replace_addresses_without_changing_directives(self):
        original = ('Address YOUR.IPV4.IP.ADDRESS\nORPort [YOUR:IPV6:IP:ADDRESS::]:9001\n'
                    'ExitPolicy reject VPS.DNS.IP.ADDRESS:*\n'
                    'ExitPolicy reject [VPS:DNS:IP:ADDRESS::4]:*\nDirPort 0\n')
        self.assertEqual(samples.render_sample(original),
                         'Address 192.0.2.10\nORPort [2001:db8::10]:9001\n'
                         'ExitPolicy reject 192.0.2.53:*\nExitPolicy reject [2001:db8::56]:*\nDirPort 0\n')

    def test_invalid_versions_and_unreviewed_signers_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source.json'
            for field, value in (('version', '0.4.9.16-alpha'), ('sha256', 'abc'),
                                 ('signing_fingerprint', 'F' * 40)):
                path.write_text(json.dumps({**LOCK, field: value}))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    source.load_lock(path)

    def test_signature_requires_reviewed_fingerprint_and_no_failure_status(self):
        for status, code, valid in (
                (f'[GNUPG:] VALIDSIG {SIGNER} fixture {SIGNER}\n', 0, True),
                ('[GNUPG:] VALIDSIG ' + 'F' * 40 + ' fixture\n', 0, False),
                (f'[GNUPG:] VALIDSIG {SIGNER} fixture\n[GNUPG:] EXPKEYSIG expired\n', 0, False),
                (f'[GNUPG:] VALIDSIG {SIGNER} fixture\n', 2, False),
                ('[GNUPG:] GOODSIG short-key-id\n', 0, False)):
            with self.subTest(status=status), patch.object(source.shutil, 'which', return_value='gpg'), \
                    patch.object(source.sp, 'run', side_effect=[Mock(), Mock(stdout=status, returncode=code)]):
                if valid:
                    self.assertEqual(source.verify_signature('signature', 'checksum'), SIGNER)
                else:
                    with self.assertRaises(ValueError): source.verify_signature('signature', 'checksum')

    def test_checksum_cannot_select_another_file_or_add_extra_entries(self):
        valid = f"{LOCK['sha256']}  tor-0.4.9.15.tar.gz\n"
        self.assertEqual(source.checksum_value(valid, '0.4.9.15'), LOCK['sha256'])
        for text in (valid.replace('0.4.9.15', '0.4.9.14'), valid + valid,
                     valid.replace('tor-', '../tor-')):
            with self.assertRaises(ValueError): source.checksum_value(text, '0.4.9.15')

    def download(self, name, path, limit=0):
        data = DATA if name.endswith('.tar.gz') else b'fixture signature'
        if name.endswith('.sha256sum'):
            data = f"{LOCK['sha256']}  tor-0.4.9.15.tar.gz\n".encode()
        path.write_bytes(data)

    def test_matching_signed_archive_produces_exact_reviewed_provenance(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(source, 'download', side_effect=self.download), \
                patch.object(source, 'verify_signature', return_value=SIGNER):
            self.assertEqual(source.fetch_release('0.4.9.15', directory, expected=LOCK), LOCK)
            self.assertEqual(json.loads((Path(directory) / 'source.json').read_text()), LOCK)

    def test_changed_authenticated_checksum_blocks_before_archive_download(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(source, 'download', side_effect=self.download) as download, \
                patch.object(source, 'verify_signature', return_value=SIGNER):
            with self.assertRaisesRegex(ValueError, 'differs from the reviewed source lock'):
                source.fetch_release('0.4.9.15', directory, expected={**LOCK, 'sha256': '0' * 64})
            self.assertEqual(download.call_count, 2)
            self.assertFalse((Path(directory) / 'source.json').exists())

    def test_tampered_archive_never_records_verified_provenance(self):
        def tamper(name, path, limit=0):
            self.download(name, path, limit)
            if name.endswith('.tar.gz'): path.write_bytes(b'tampered')
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(source, 'download', side_effect=tamper), \
                patch.object(source, 'verify_signature', return_value=SIGNER):
            with self.assertRaisesRegex(ValueError, 'authenticated checksum'):
                source.fetch_release('0.4.9.15', directory, expected=LOCK)
            self.assertFalse((Path(directory) / 'source.json').exists())

    def test_discovery_excludes_prereleases_and_compares_all_four_numbers(self):
        page = b'<a href="tor-0.4.9.16-alpha.tar.gz"><a href="tor-0.4.9.99.tar.gz"><a href="tor-0.4.10.1.tar.gz">'
        with patch.object(source, 'urlopen') as fetch:
            fetch.return_value.__enter__.return_value.read.return_value = page
            self.assertEqual(source.latest_release(), '0.4.10.1')


class TorUpdateTests(unittest.TestCase):
    def run_updater(self, *argv, version='0.4.9.15'):
        with patch('sys.argv', ['update-tor-source.py', *argv]), \
                patch.object(updater.source, 'load_lock', return_value=LOCK), \
                patch.object(updater.source, 'latest_release', return_value=version), \
                redirect_stdout(io.StringIO()):
            return updater.main()

    def test_equal_release_is_a_noop_without_archive_download(self):
        with patch.object(updater.source, 'fetch_release') as fetch:
            self.assertEqual(self.run_updater('--write'), 0)
            fetch.assert_not_called()

    def test_downgrade_is_rejected_before_downloading(self):
        with patch.object(updater.source, 'fetch_release') as fetch:
            with self.assertRaisesRegex(ValueError, 'downgrade'):
                self.run_updater(version='0.4.9.14')
            fetch.assert_not_called()

    def test_new_release_check_retains_proposal_without_mutating_source(self):
        proposed = {**LOCK, 'version': '0.4.9.16'}
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(updater.source, 'fetch_release', return_value=proposed):
            report = Path(directory) / 'report.json'
            self.assertEqual(self.run_updater('--output', str(report), version='0.4.9.16'), 1)
            self.assertEqual(json.loads(report.read_text())['proposed'], proposed)

    def test_write_changes_only_the_pin_after_verification(self):
        proposed = {**LOCK, 'version': '0.4.9.16'}
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(updater, 'ROOT', Path(directory)), \
                patch.object(updater.source, 'fetch_release', return_value=proposed):
            target = Path(directory) / 'build/tor/source.json'
            target.parent.mkdir(parents=True)
            target.write_text(json.dumps(LOCK))
            self.assertEqual(self.run_updater('--write', version='0.4.9.16'), 0)
            self.assertEqual(json.loads(target.read_text()), proposed)

    def test_authentication_failure_does_not_change_pin(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(updater, 'ROOT', Path(directory)), \
                patch.object(updater.source, 'fetch_release', side_effect=ValueError('bad signature')):
            target = Path(directory) / 'build/tor/source.json'
            target.parent.mkdir(parents=True)
            before = json.dumps(LOCK)
            target.write_text(before)
            report = Path(directory) / 'failed-update.json'
            with self.assertRaisesRegex(ValueError, 'bad signature'):
                self.run_updater('--write', '--output', str(report), version='0.4.9.16')
            self.assertEqual(target.read_text(), before)
            self.assertEqual(json.loads(report.read_text())['error'], 'bad signature')
