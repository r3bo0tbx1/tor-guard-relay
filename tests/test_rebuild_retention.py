"""Verify rebuild cleanup preserves pull graphs and fails closed on ambiguity."""
import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import io
import json
from pathlib import Path
import subprocess as sp
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

from test_registry_retention import RegistryFixture, digest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/release'))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rebuild = load('rebuild_retention', 'scripts/release/prune-rebuilds.py')
collect = load('collect_retention', 'scripts/release/collect-retention-builds.py')
inventory = load('image_protection', 'scripts/utilities/relay-image-protection.py')
NOW = datetime(2026, 10, 10, tzinfo=timezone.utc)
REGISTRY = 'ghcr.io/fixture/onion-relay'
POLICY = {'keep_builds': 2, 'grace_days': 7, 'deployment_review_complete': False,
          'deployment_reviewed_at': None, 'protected_digests': [], 'protected_image_ids': []}


class Builds(RegistryFixture):
    def __init__(self, registry=REGISTRY):
        self.manifests, self.configs, self.tags, self.deletions = {}, {}, {}, []
        self.catalog = {'current': [], 'publications': [], 'original_image_ids': [], 'publication_run': 5}
        for serial, days in enumerate((40, 30, 20, 5, 0), start=1):
            rows = []
            for variant in ('stable', 'edge'):
                version = '2.2.0' + ('-edge' if variant == 'edge' else '')
                arches = {arch: self.image(f'{serial}-{variant}-{arch}', version, arch) for arch in ('amd64', 'arm64')}
                root = digest(f'{serial}-{variant}')
                self.manifests[root] = {'manifests': [{'digest': value, 'platform': {'os': 'linux', 'architecture': arch}}
                                                     for arch, value in arches.items()]}
                tags = rebuild.prune.tidy.public_tags(registry, '2.2.0', variant)
                row = {'registry': registry, 'variant': variant, 'tags': tags, 'index_digest': root,
                       'architectures': arches, 'image_ids': {arch: self.manifests[value]['config']['digest'] for arch, value in arches.items()}}
                rows.append(row)
                if serial == 1:
                    self.catalog['original_image_ids'].extend(row['image_ids'].values())
                if serial == 5:
                    self.tags.update({tag: root for tag in tags})
            self.catalog['publications'].append({'run_id': serial, 'published_at': (NOW - timedelta(days=days)).isoformat(), 'rows': rows})
        self.catalog['current'] = rows
        self.entries = dict(enumerate(self.manifests, start=1))

    def run(self, *args):
        if args[:2] == ('manifest', 'delete'):
            target = args[2].rsplit('@', 1)[1]
            if target in self.tags.values() or any(target in rebuild.prune.Graph.children(m) for m in self.manifests.values()):
                raise sp.CalledProcessError(1, args, stderr='[http 403]: still referenced')
            self.deletions.append(('manifest', target))
            del self.manifests[target]
            return ''
        return super().run(*args)


class RebuildTests(unittest.TestCase):
    def setUp(self):
        self.fixture = Builds()
        self.policy = copy.deepcopy(POLICY)

    def plan(self):
        return rebuild.plan_registry(self.fixture, REGISTRY, self.fixture.catalog, self.policy, NOW, self.fixture)

    def test_selects_only_old_known_builds_preserving_original_and_two_recent_builds(self):
        report = self.plan()
        self.assertEqual(len(report['package_targets']), 12)
        self.assertEqual(len(report['protected']['manifests']), 18)
        self.assertFalse(self.fixture.deletions)

    def test_docker_hub_deletes_actual_manifests_parent_first_and_preserves_pulls(self):
        registry = 'fixture/onion-relay'
        fixture = Builds(registry)
        report = rebuild.plan_registry(fixture, registry, fixture.catalog, self.policy, NOW)
        self.assertEqual(len(report['manifest_targets']), 12)
        rebuild.apply_registry(fixture, report)
        self.assertEqual(len(fixture.manifests), 18)
        self.assertEqual(set(fixture.tags), {'2.2.0', 'latest', 'edge'})
        again = rebuild.plan_registry(fixture, registry, fixture.catalog, self.policy, NOW)
        self.assertFalse(again['manifest_targets'])

    def test_unknown_parent_protects_shared_old_architecture(self):
        child = self.fixture.catalog['publications'][1]['rows'][0]['architectures']['amd64']
        root = digest('unknown-parent')
        self.fixture.manifests[root] = {'manifests': [{'digest': child}]}
        self.fixture.entries[999] = root
        report = self.plan()
        self.assertIn(child, report['protected']['manifests'])
        self.assertNotIn(child, {item['digest'] for item in report['package_targets']})

    def test_original_release_config_protects_all_of_its_parents(self):
        self.assertTrue(all(row['index_digest'] in self.plan()['protected']['manifests']
                            for row in self.fixture.catalog['publications'][0]['rows']))

    def test_deployed_config_protects_parent_index_and_both_architectures(self):
        row = self.fixture.catalog['publications'][1]['rows'][0]
        self.policy['protected_image_ids'] = [row['image_ids']['amd64']]
        report = self.plan()
        self.assertIn(row['index_digest'], report['protected']['manifests'])
        self.assertTrue(set(row['architectures'].values()) <= set(report['protected']['manifests']))

    def test_explicit_deployed_index_and_children_are_protected(self):
        row = self.fixture.catalog['publications'][1]['rows'][1]
        self.policy['protected_digests'] = [row['index_digest']]
        self.assertIn(row['index_digest'], self.plan()['protected']['manifests'])

    def test_containerd_engine_index_id_protects_both_architectures(self):
        row = self.fixture.catalog['publications'][1]['rows'][0]
        self.policy['protected_image_ids'] = [row['index_digest']]
        report = self.plan()
        protected = set(report['protected']['manifests'])
        self.assertIn(row['index_digest'], protected)
        self.assertTrue(set(row['architectures'].values()) <= protected)
        self.assertNotIn(row['index_digest'], {x['digest'] for x in report['package_targets']})

    def test_engine_architecture_manifest_id_protects_parent_and_sibling(self):
        row = self.fixture.catalog['publications'][1]['rows'][0]
        self.policy['protected_image_ids'] = [row['architectures']['amd64']]
        protected = set(self.plan()['protected']['manifests'])
        self.assertIn(row['index_digest'], protected)
        self.assertTrue(set(row['architectures'].values()) <= protected)

    def test_unresolved_engine_identity_blocks_deletion_plan(self):
        self.policy['protected_image_ids'] = [digest('unresolved-engine-id')]
        with self.assertRaisesRegex(ValueError, 'Deployed image identities cannot be resolved'):
            self.plan()
        self.assertFalse(self.fixture.deletions)

    def test_unknown_images_and_tagged_rollback_are_preserved(self):
        root = self.fixture.catalog['publications'][1]['rows'][0]['index_digest']
        self.fixture.tags['rollback'] = root
        unknown = self.fixture.image('unknown', None, 'amd64')
        self.fixture.entries[999] = unknown
        report = self.plan()
        self.assertIn(root, report['protected']['manifests'])
        self.assertIn(unknown, report['protected']['manifests'])

    def test_seven_day_grace_preserves_builds_outside_two_newest(self):
        self.fixture.catalog['publications'][2]['published_at'] = (NOW - timedelta(days=6)).isoformat()
        self.assertEqual(len(self.plan()['package_targets']), 6)

    def test_repeated_digest_publication_uses_latest_date_and_distinct_builds(self):
        copied = copy.deepcopy(self.fixture.catalog['publications'][1])
        copied['published_at'] = (NOW - timedelta(days=1)).isoformat()
        self.fixture.catalog['publications'].append(copied)
        row = copied['rows'][0]
        self.assertIn(row['index_digest'], self.plan()['protected']['manifests'])

    def test_tag_drift_blocks_before_any_deletion(self):
        report = self.plan()
        self.fixture.tags['new-pin'] = report['package_targets'][0]['digest']
        with self.assertRaisesRegex(ValueError, 'tag inventory changed'):
            rebuild.apply_registry(self.fixture, report, self.fixture)
        self.assertFalse(self.fixture.deletions)

    def test_new_untagged_package_blocks_before_any_deletion(self):
        report = self.plan()
        self.fixture.entries[999] = self.fixture.image('new-untagged', '2.2.0', 'amd64')
        with self.assertRaisesRegex(ValueError, 'Package inventory changed'):
            rebuild.apply_registry(self.fixture, report, self.fixture)
        self.assertFalse(self.fixture.deletions)

    def test_forged_target_overlapping_protected_graph_is_rejected(self):
        report = self.plan()
        current = next(item for item in self.fixture.versions() if item['name'] == self.fixture.tags['latest'])
        report['package_targets'].insert(0, rebuild.prune.package_identity(current))
        with self.assertRaisesRegex(ValueError, 'overlaps'):
            rebuild.apply_registry(self.fixture, report, self.fixture)
        self.assertFalse(self.fixture.deletions)

    def test_current_image_identity_or_missing_child_blocks_plan(self):
        row = self.fixture.catalog['current'][0]
        row['image_ids']['amd64'] = digest('forged')
        with self.assertRaisesRegex(ValueError, 'image identity differs'):
            self.plan()

    def test_missing_or_malformed_original_protection_blocks_plan(self):
        for value in ([], [digest('x')] * 4, ['bad'] * 4):
            self.fixture.catalog['original_image_ids'] = value
            with self.assertRaisesRegex(ValueError, 'original-release'):
                self.plan()

    def test_missing_explicit_deployed_digest_blocks_plan(self):
        self.policy['protected_digests'] = [digest('missing')]
        with self.assertRaises(sp.CalledProcessError):
            self.plan()

    def test_auth_errors_are_never_treated_as_missing_old_images(self):
        original = self.fixture.manifest
        def denied(reference):
            if reference.endswith(self.fixture.catalog['publications'][1]['rows'][0]['index_digest']):
                raise sp.CalledProcessError(1, ['fixture'], stderr='[http 401]: unauthorized')
            return original(reference)
        self.fixture.manifest = denied
        with self.assertRaises(sp.CalledProcessError):
            self.plan()

    def test_hub_reference_rejection_stops_without_forcing_or_retrying(self):
        registry = 'fixture/onion-relay'
        fixture = Builds(registry)
        report = rebuild.plan_registry(fixture, registry, fixture.catalog, self.policy, NOW)
        fixture.manifests[digest('unknown-parent')] = {'manifests': [{'digest': report['manifest_targets'][0]}]}
        with self.assertRaises(sp.CalledProcessError):
            rebuild.apply_registry(fixture, report)
        self.assertFalse(fixture.deletions)

    def test_ghcr_apply_preserves_graph_and_is_idempotent(self):
        report = self.plan()
        rebuild.apply_registry(self.fixture, report, self.fixture)
        self.assertTrue(report['applied'])
        self.assertEqual(len(report['removed_packages']), 12)
        self.assertFalse(self.plan()['package_targets'])

    def test_policy_blocks_unknown_stale_future_or_incomplete_deployment_review(self):
        with self.assertRaisesRegex(ValueError, 'coverage'):
            rebuild.validate_policy(self.policy, NOW, True)
        self.policy['deployment_review_complete'] = True
        for days in (8, -1):
            self.policy['deployment_reviewed_at'] = (NOW - timedelta(days=days)).isoformat()
            with self.assertRaisesRegex(ValueError, 'seven days'):
                rebuild.validate_policy(self.policy, NOW, True)
        self.policy['deployment_reviewed_at'] = NOW.isoformat()
        rebuild.validate_policy(self.policy, NOW, True)

    def test_policy_cannot_lower_safety_minima_or_use_invalid_digests(self):
        for field, value in (('keep_builds', 1), ('grace_days', 6), ('keep_builds', True), ('protected_digests', ['bad'])):
            policy = {**self.policy, field: value}
            with self.assertRaises(ValueError):
                rebuild.validate_policy(policy, NOW)

    def test_exact_preview_confirmation_rejects_missing_or_changed_plans(self):
        fingerprint = rebuild.hash_json(self.plan())
        rebuild.confirm_plan(fingerprint, fingerprint)
        for value in ('', 'bad', '0' * 64):
            with self.assertRaisesRegex(ValueError, 'unchanged reviewed preview'):
                rebuild.confirm_plan(fingerprint, value)
        changed = self.plan()
        changed['package_targets'].pop()
        self.assertNotEqual(rebuild.hash_json(changed), fingerprint)

    def test_apply_without_deployment_coverage_never_constructs_a_registry_client(self):
        with tempfile.TemporaryDirectory() as work:
            work = Path(work)
            (work / 'policy.json').write_text(json.dumps(self.policy))
            (work / 'catalog.json').write_text(json.dumps(self.fixture.catalog))
            arguments = ['retention', '--owner', 'fixture', '--policy', str(work / 'policy.json'),
                         '--catalog', str(work / 'catalog.json'), '--output', str(work / 'result.json'), '--apply']
            with mock.patch.object(sys, 'argv', arguments), mock.patch.object(rebuild, 'Client') as client:
                with self.assertRaisesRegex(ValueError, 'coverage'):
                    rebuild.main()
                client.assert_not_called()

    def test_missing_retained_layer_blocks_before_any_delete(self):
        report = self.plan()
        manifest = next(value for value in report['protected']['manifests'].values() if value.get('config'))
        manifest['layers'] = [{'digest': digest('missing-layer')}]
        # Make the immutable manifest agree with the preview; it is the missing
        # blob, rather than a changed manifest, which must stop the operation.
        key = next(key for key, value in report['protected']['manifests'].items() if value is manifest)
        self.fixture.manifests[key] = copy.deepcopy(manifest)
        original = self.fixture.run
        def call(*args):
            if args[:2] == ('blob', 'head'):
                raise sp.CalledProcessError(1, args, stderr='missing retained layer')
            return original(*args)
        self.fixture.run = call
        with self.assertRaises(sp.CalledProcessError):
            rebuild.apply_registry(self.fixture, report, self.fixture)
        self.assertFalse(self.fixture.deletions)

    def test_partial_failure_records_completed_deletions_and_stops(self):
        report = self.plan()
        delete = self.fixture.delete
        snapshots = []
        def fail_second(identity):
            if self.fixture.deletions:
                raise sp.CalledProcessError(1, ['delete'], stderr='service unavailable')
            delete(identity)
        self.fixture.delete = fail_second
        with self.assertRaises(sp.CalledProcessError):
            rebuild.apply_registry(self.fixture, report, self.fixture, lambda: snapshots.append(copy.deepcopy(report)))
        self.assertEqual(len(snapshots), 3)
        self.assertEqual(len(snapshots[-1]['removed_packages']), 1)
        self.assertEqual(snapshots[-1]['attempts'][-1]['status'], 'requested')
        self.assertFalse(report['applied'])


class EvidenceTests(unittest.TestCase):
    def test_original_archive_is_read_without_extracting_and_requires_all_four_images(self):
        source = '1' * 40
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / 'evidence.tar.gz'
            with tarfile.open(path, 'w:gz') as bundle:
                for variant in ('stable', 'edge'):
                    for arch in ('amd64', 'arm64'):
                        image = {'Id': digest(variant + arch), 'Architecture': arch, 'Os': 'linux', 'Config': {'Labels': {
                            'org.opencontainers.image.version': '2.2.0' + ('-edge' if variant == 'edge' else ''),
                            'org.opencontainers.image.revision': source}}}
                        data = json.dumps([image]).encode()
                        entry = tarfile.TarInfo(f'./candidate-{variant}-{arch}/image.json')
                        entry.size = len(data)
                        bundle.addfile(entry, io.BytesIO(data))
            self.assertEqual(len(collect.original_ids(path, '2.2.0', source)), 4)
            with self.assertRaisesRegex(ValueError, 'Git tag'):
                collect.original_ids(path, '2.2.0', '2' * 40)
            with tarfile.open(path, 'w:gz'):
                pass
            with self.assertRaisesRegex(ValueError, 'four image'):
                collect.original_ids(path, '2.2.0', source)

    def test_deployment_inventory_uses_only_image_fields_and_includes_stopped_containers(self):
        calls = []
        def call(*args):
            calls.append(args)
            if args == ('ps', '-aq'):
                return 'running\nstopped\nunrelated'
            if args[0] == 'inspect':
                return json.dumps(args[-1])
            if args[:2] == ('image', 'inspect'):
                relay = args[-1] != 'unrelated'
                return json.dumps({'id': digest(args[-1]), 'tags': ['fixture/onion-relay:latest' if relay else 'nginx:latest'],
                                   'digests': ['fixture/onion-relay@' + digest(args[-1] + 'index')] if relay else [], 'source': None})
            raise AssertionError(args)
        result = inventory.collect(call, 'fixture')
        self.assertEqual(result['relay_containers'], 2)
        self.assertEqual(len(result['protected_image_ids']), 2)
        self.assertFalse(result['deployment_review_complete'])
        self.assertTrue(all('exec' not in parts for parts in calls))
        self.assertTrue(all('{{json .}}' not in parts for parts in calls))


if __name__ == '__main__':
    unittest.main()
