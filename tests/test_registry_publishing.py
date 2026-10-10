import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/release'))
from registry_tools import architecture_digests, prepare_archive, promote, public_tags

spec = importlib.util.spec_from_file_location('registry_tidy', ROOT / 'scripts/release/tidy-release-tags.py')
tidy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tidy)


class PublicationTests(unittest.TestCase):
    def test_registry_specific_tags(self):
        self.assertEqual(public_tags('r3bo0tbx1/onion-relay', '2.2.0', 'stable'), ['2.2.0', 'latest'])
        self.assertEqual(public_tags('r3bo0tbx1/onion-relay', '2.2.0', 'edge'), ['edge'])
        self.assertEqual(public_tags('ghcr.io/r3bo0tbx1/onion-relay', '2.2.0', 'stable'), ['2.2.0', 'latest'])
        self.assertEqual(public_tags('ghcr.io/r3bo0tbx1/onion-relay', '2.2.0', 'edge'), ['2.2.0-edge', 'edge'])

    def test_invalid_version_or_variant_rejected(self):
        for version, variant in [('2.2.0:latest', 'stable'), ('2.2.0', 'unknown')]:
            with self.assertRaises(ValueError):
                public_tags('registry/repo', version, variant)

    def test_duplicate_missing_or_non_linux_platform_rejected(self):
        entry = {'digest': 'sha256:' + '1' * 64, 'platform': {'os': 'linux', 'architecture': 'amd64'}}
        for entries in ([entry], [entry, entry], [entry, {**entry, 'platform': {'os': 'windows', 'architecture': 'arm64'}}]):
            with self.assertRaises(ValueError):
                architecture_digests({'manifests': entries})

    def test_incomplete_edge_set_rejected_before_any_registry_call(self):
        client = Mock()
        with self.assertRaises(ValueError):
            promote(client, [{'variant': 'stable', 'arch': arch} for arch in ('amd64', 'arm64')],
                    ['registry/repo'], '2.2.0', 'unused.json')
        client.run.assert_not_called()

    def prepare_fixture(self, directory):
        (directory / 'image.tar').write_bytes(b'synthetic archive')
        import hashlib
        digest = hashlib.sha256(b'synthetic archive').hexdigest()
        (directory / 'image.tar.sha256').write_text(digest + '  image.tar\n')
        image = {'Id': 'sha256:' + '1' * 64, 'Os': 'linux', 'Architecture': 'amd64',
                 'Config': {'Labels': {'org.opencontainers.image.version': '2.2.0',
                                      'org.opencontainers.image.revision': '2' * 40}}}
        (directory / 'image.json').write_text(json.dumps([image]))
        return image

    def test_corrupt_archive_rejected_before_client_call(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            self.prepare_fixture(directory)
            (directory / 'image.tar').write_bytes(b'changed')
            client = Mock()
            with self.assertRaisesRegex(ValueError, 'checksum'):
                prepare_archive(client, directory, 'stable', 'amd64', '2.2.0', '2' * 40)
            client.run.assert_not_called()

    def test_source_version_and_architecture_mismatches_rejected(self):
        for arch, version, source in [('arm64', '2.2.0', '2' * 40),
                                       ('amd64', '2.2.1', '2' * 40), ('amd64', '2.2.0', '3' * 40)]:
            with tempfile.TemporaryDirectory() as directory:
                directory = Path(directory)
                self.prepare_fixture(directory)
                client = Mock()
                with self.assertRaisesRegex(ValueError, 'does not match'):
                    prepare_archive(client, directory, 'stable', arch, version, source)
                client.run.assert_not_called()

    def test_imported_config_identity_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            self.prepare_fixture(directory)
            client = Mock()
            client.run.return_value = 'sha256:' + '4' * 64
            client.manifest.return_value = {'config': {'digest': 'sha256:' + '5' * 64}}
            with self.assertRaisesRegex(ValueError, 'identity differs'):
                prepare_archive(client, directory, 'stable', 'amd64', '2.2.0', '2' * 40)

    def test_protected_manifest_change_fails_verification(self):
        client = Mock()
        client.run.return_value = 'sha256:' + '1' * 64
        client.manifest.return_value = {'changed': True}
        with self.assertRaisesRegex(ValueError, 'manifest changed'):
            tidy.verify_snapshot(client, 'registry/repo', {'roots': {'latest': client.run.return_value},
                'manifests': {client.run.return_value: {'original': True}}})

    def test_original_image_cannot_be_deleted_as_placeholder(self):
        client = Mock()
        client.run.return_value = 'sha256:' + '1' * 64
        with patch.object(tidy.sp, 'run') as delete:
            with self.assertRaisesRegex(ValueError, 'refusing package deletion'):
                tidy.delete_dummy_version(client, 'ghcr.io/owner/onion-relay', 'unwanted', client.run.return_value)
            delete.assert_not_called()

    def test_placeholder_with_another_tag_cannot_be_deleted(self):
        client = Mock()
        client.run.side_effect = ['sha256:' + '2' * 64, json.dumps({'config': {'Labels': {'delete-tag': 'unwanted'}}})]
        client.manifest.return_value = {'config': {'digest': 'sha256:' + '3' * 64}}
        pages = [[{'name': 'sha256:' + '2' * 64, 'metadata': {'container': {'tags': ['unwanted', 'latest']}}}]]
        with patch.object(tidy.sp, 'check_output', return_value=json.dumps(pages)), patch.object(tidy.sp, 'run') as delete:
            with self.assertRaisesRegex(ValueError, 'has other tags'):
                tidy.delete_dummy_version(client, 'ghcr.io/owner/onion-relay', 'unwanted', 'sha256:' + '1' * 64)
            delete.assert_not_called()

    def test_only_verified_unique_placeholder_version_is_deleted(self):
        client = Mock()
        client.run.side_effect = ['sha256:' + '2' * 64, json.dumps({'config': {'Labels': {'delete-tag': 'unwanted'}}})]
        client.manifest.return_value = {'config': {'digest': 'sha256:' + '3' * 64}}
        pages = [[{'id': 42, 'name': 'sha256:' + '2' * 64, 'metadata': {'container': {'tags': ['unwanted']}}}]]
        with patch.object(tidy.sp, 'check_output', return_value=json.dumps(pages)), patch.object(tidy.sp, 'run') as delete:
            tidy.delete_dummy_version(client, 'ghcr.io/owner/onion-relay', 'unwanted', 'sha256:' + '1' * 64)
            delete.assert_called_once_with(['gh', 'api', '--method', 'DELETE',
                'users/owner/packages/container/onion-relay/versions/42'], check=True)


if __name__ == '__main__':
    unittest.main()
