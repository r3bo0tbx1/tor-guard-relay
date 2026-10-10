"""Prove retired images cannot delete retained aliases, children or releases."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import subprocess as sp
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/release'))


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts/release' / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prune = load('registry_prune', 'prune-old-images.py')
ready = load('registry_readiness', 'check-retention-ready.py')


def digest(name):
    return 'sha256:' + hashlib.sha256(name.encode()).hexdigest()


class RegistryFixture:
    def __init__(self):
        self.manifests, self.configs, self.tags, self.deletions = {}, {}, {}, []
        for version in ('2.1.0', '2.2.0'):
            for variant in ('stable', 'edge'):
                label = version + ('-edge' if variant == 'edge' else '')
                children = [self.image(label + arch, label, arch) for arch in ('amd64', 'arm64')]
                if version == '2.1.0':
                    children.append(self.image(label + 'attestation', None, 'unknown'))
                root = digest(label)
                self.manifests[root] = {'manifests': [
                    {'digest': child, 'platform': {'os': 'linux', 'architecture': arch}}
                    for child, arch in zip(children, ('amd64', 'arm64', 'unknown'))]}
                self.tags[label] = root
        self.tags['latest'] = self.tags['2.2.0']
        self.tags['edge'] = self.tags['2.2.0-edge']
        self.previous = self.image('earlier-current-build', '2.2.0', 'amd64')
        self.entries = {index: value for index, value in enumerate(self.manifests, start=1)}

    def image(self, name, version, arch):
        key, config = digest(name), digest(name + '-config')
        labels = {'org.opencontainers.image.version': version} if version else {}
        self.configs[config] = {'architecture': arch, 'config': {'Labels': labels}}
        self.manifests[key] = {'config': {'digest': config},
                              'layers': [] if version else [{'mediaType': 'application/vnd.in-toto+json'}]}
        return key

    def run(self, *args):
        if args[:2] == ('tag', 'ls'):
            return '\n'.join(sorted(self.tags))
        if args[:2] == ('image', 'digest'):
            return self.tags[args[2].rsplit(':', 1)[1]]
        if args[:2] == ('blob', 'get'):
            return json.dumps(self.configs[args[3]])
        if args[:2] == ('tag', 'delete'):
            tag = args[2].rsplit(':', 1)[1]
            del self.tags[tag]
            self.deletions.append(('tag', tag))
            return ''
        raise AssertionError(args)

    def manifest(self, reference):
        name = reference.rsplit('@', 1)[1]
        if name not in self.manifests:
            raise sp.CalledProcessError(1, ['fixture'], stderr='not found [http 404]: MANIFEST_UNKNOWN')
        return copy.deepcopy(self.manifests[name])

    def get(self, identity):
        name = self.entries[identity]
        return {'id': identity, 'name': name,
                'metadata': {'container': {'tags': sorted(tag for tag, value in self.tags.items() if value == name)}}}

    def versions(self):
        return [self.get(identity) for identity in self.entries]

    def delete(self, identity):
        name = self.entries.pop(identity)
        self.deletions.append(('package', name))
        del self.manifests[name]
        self.tags = {tag: value for tag, value in self.tags.items() if value != name}


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.registry = RegistryFixture()

    def plan(self):
        return prune.plan_registry(self.registry, 'ghcr.io/fixture/onion-relay', '2.2.0',
                                   ['2.0.0', '2.1.0'], self.registry)

    def test_plan_preserves_current_untagged_builds_and_selects_old_attestations(self):
        report = self.plan()
        self.assertFalse(report['applied'])
        self.assertEqual(set(report['tag_targets']), {'2.1.0', '2.1.0-edge'})
        self.assertEqual(len(report['package_targets']), 8)
        self.assertIn(self.registry.previous, report['protected']['manifests'])
        current = set(report['protected']['manifests'])
        self.assertTrue(current.isdisjoint(item['digest'] for item in report['package_targets']))
        self.assertFalse(self.registry.deletions)

    def test_apply_preserves_exact_current_images_and_is_idempotent(self):
        report = self.plan()
        before = copy.deepcopy(report['protected'])
        prune.apply_registry(self.registry, report, self.registry)
        self.assertTrue(report['applied'])
        self.assertEqual(set(self.registry.tags), {'2.2.0', '2.2.0-edge', 'latest', 'edge'})
        self.assertEqual(report['protected'], before)
        self.assertEqual(len(report['removed_packages']), 8)
        again = self.plan()
        self.assertFalse(again['package_targets'])
        self.assertFalse(again['tag_targets'])

    def test_old_tag_sharing_retained_graph_is_removed_without_deleting_images(self):
        self.registry.tags['rollback'] = self.registry.tags['2.1.0']
        report = self.plan()
        protected = self.registry.tags['rollback']
        self.assertIn(protected, report['protected']['manifests'])
        self.assertIn('2.1.0', report['tag_only'])
        prune.apply_registry(self.registry, report, self.registry)
        self.assertIn(protected, self.registry.manifests)
        self.assertIn('rollback', self.registry.tags)

    def test_current_or_newer_version_cannot_be_retired(self):
        for version in ('2.2.0', '2.3.0', 'main', '2.1.0-edge'):
            with self.assertRaises(ValueError):
                prune.plan_registry(self.registry, 'ghcr.io/fixture/onion-relay', '2.2.0', [version], self.registry)
        self.assertFalse(self.registry.deletions)

    def test_changed_current_alias_blocks_before_deletion(self):
        report = self.plan()
        self.registry.tags['latest'] = self.registry.tags['2.1.0']
        with self.assertRaisesRegex(ValueError, 'tag changed'):
            prune.apply_registry(self.registry, report, self.registry)
        self.assertFalse(self.registry.deletions)

    def test_new_tag_on_target_blocks_package_deletion(self):
        report = self.plan()
        first = report['package_targets'][0]
        self.registry.tags['new-retained-alias'] = first['digest']
        with self.assertRaisesRegex(ValueError, 'identity or tags changed'):
            prune.apply_registry(self.registry, report, self.registry)
        self.assertFalse(self.registry.deletions)

    def test_changed_package_id_digest_blocks_before_deletion(self):
        report = self.plan()
        self.registry.entries[report['package_targets'][0]['id']] = self.registry.previous
        with self.assertRaisesRegex(ValueError, 'identity or tags changed'):
            prune.apply_registry(self.registry, report, self.registry)
        self.assertFalse(self.registry.deletions)

    def test_forged_protected_target_is_rejected(self):
        report = self.plan()
        current = next(item for item in self.registry.versions() if item['name'] == self.registry.tags['latest'])
        report['package_targets'].insert(0, prune.package_identity(current))
        with self.assertRaisesRegex(ValueError, 'overlaps protected'):
            prune.apply_registry(self.registry, report, self.registry)
        self.assertFalse(self.registry.deletions)

    def test_unknown_untagged_images_are_preserved(self):
        unknown = self.registry.image('unknown-image', None, 'amd64')
        self.registry.entries[999] = unknown
        self.assertIn(unknown, self.plan()['protected']['manifests'])

    def test_package_inventory_disagreement_fails_closed(self):
        original = self.registry.versions
        def changed():
            rows = original()
            rows[0]['metadata']['container']['tags'] = ['latest']
            return rows
        self.registry.versions = changed
        with self.assertRaisesRegex(ValueError, 'metadata and registry tags disagree'):
            self.plan()

    def test_duplicate_package_identity_is_rejected(self):
        original = self.registry.versions
        self.registry.versions = lambda: original() + [original()[0]]
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            self.plan()

    def test_preexisting_missing_retired_child_is_recorded_without_becoming_a_deletion(self):
        missing = digest('already-deleted-old-child')
        old = self.registry.tags['2.1.0']
        self.registry.manifests[old]['manifests'].append({'digest': missing})
        # Use an untagged older index, matching a historical orphaned build.
        del self.registry.tags['2.1.0']
        report = self.plan()
        self.assertEqual(report['missing_retired_references'], [missing])
        self.assertNotIn(missing, {item['digest'] for item in report['package_targets']})
        prune.apply_registry(self.registry, report, self.registry)
        self.assertTrue(report['applied'])

    def test_missing_current_child_blocks_cleanup(self):
        current = self.registry.tags['latest']
        self.registry.manifests[current]['manifests'][0]['digest'] = digest('missing-current')
        with self.assertRaises(sp.CalledProcessError):
            self.plan()
        self.assertFalse(self.registry.deletions)

    def test_network_or_permission_errors_cannot_be_treated_as_missing_old_children(self):
        original = self.registry.manifest
        unlisted = digest('unlisted-child')
        old = self.registry.tags['2.1.0']
        self.registry.manifests[old]['manifests'].append({'digest': unlisted})
        del self.registry.tags['2.1.0']
        for message in ('[http 401]: unauthorized', '[http 503]: server unavailable'):
            def failed(reference):
                if reference.endswith(unlisted):
                    raise sp.CalledProcessError(1, ['fixture'], stderr=message)
                return original(reference)
            self.registry.manifest = failed
            with self.assertRaises(sp.CalledProcessError):
                self.plan()
        self.assertFalse(self.registry.deletions)

    def test_publication_identity_mismatch_blocks_cleanup(self):
        report = self.plan()
        evidence = []
        for variant, tags in (('stable', ['2.2.0', 'latest']), ('edge', ['2.2.0-edge', 'edge'])):
            root = self.registry.tags[tags[0]]
            arches = prune.architecture_digests(self.registry.manifests[root])
            evidence.append({'registry': report['registry'], 'variant': variant, 'tags': tags,
                             'index_digest': root, 'architectures': arches,
                             'image_ids': {arch: self.registry.manifests[value]['config']['digest'] for arch, value in arches.items()}})
        prune.verify_publication(report, evidence)
        evidence[0]['image_ids']['amd64'] = digest('wrong-config')
        with self.assertRaisesRegex(ValueError, 'image identity differs'):
            prune.verify_publication(report, evidence)


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.release = {'id': 10, 'status': 'completed', 'conclusion': 'success',
                        'head_sha': '1' * 40, 'updated_at': '2026-10-10T06:00:00Z'}
        self.audit = {'id': 11, 'event': 'workflow_run', 'status': 'completed', 'conclusion': 'success',
                      'head_sha': '1' * 40, 'created_at': '2026-10-10T06:00:01Z'}

    def test_matching_post_publication_audit_required(self):
        self.assertEqual(ready.choose([self.release], [self.audit]), (self.release, self.audit))
        for changed in ({'conclusion': 'failure'}, {'event': 'push'}, {'head_sha': '2' * 40},
                        {'created_at': '2026-10-10T05:59:00Z'}, {'status': 'in_progress'}):
            with self.assertRaises(ValueError):
                ready.choose([self.release], [{**self.audit, **changed}])

    def test_active_publication_blocks_retirement(self):
        with self.assertRaisesRegex(ValueError, 'active release runs'):
            ready.choose([{**self.release, 'status': 'in_progress'}, self.release], [self.audit])

    def test_no_successful_publication_blocks_retirement(self):
        with self.assertRaisesRegex(ValueError, 'successful publication'):
            ready.choose([{**self.release, 'conclusion': 'failure'}], [self.audit])
