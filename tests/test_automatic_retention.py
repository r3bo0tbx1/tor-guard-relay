"""Exercise the automatic deletion clock, durable history and exact legacy scope."""
import copy
from datetime import timedelta
import json
import os
from pathlib import Path
import subprocess as sp
import sys
import tempfile
import unittest
from unittest import mock

from test_rebuild_retention import Builds, NOW, POLICY, load, rebuild
from test_registry_retention import digest

auto = load('automatic_retention_tests', 'scripts/release/automatic-retention.py')
REPOSITORY = 'fixture/tor-guard-relay'
URL = 'https://github.com/' + REPOSITORY + '/issues/1'
LEGACY = {'registry': 'fixture/onion-relay', 'builds': []}


def policy():
    value = copy.deepcopy(POLICY)
    value.update(grace_days=14, deployment_review_complete=True, deployment_reviewed_at=NOW.isoformat())
    value['automatic'] = {'enabled': True, 'migration_days': 14, 'interval_days': 14,
                          'acknowledged_failed_deployments': []}
    return value


class NoticeAPI:
    def __init__(self, settings, age=14):
        self.issue = {'html_url': URL, 'state': 'open', 'author_association': 'OWNER',
                      'user': {'type': 'User'}, 'body': auto.marker(settings, LEGACY),
                      'created_at': (NOW - timedelta(days=age)).isoformat(),
                      'updated_at': (NOW - timedelta(days=age)).isoformat()}
        self.records, self.statuses, self.private = [], {}, False
        self.calls = []

    def __call__(self, path):
        self.calls.append(path)
        if path == 'repos/' + REPOSITORY:
            return {'private': self.private}
        if '/issues/' in path:
            return self.issue
        if '/statuses?' in path:
            return self.statuses[int(path.split('/deployments/')[1].split('/')[0])]
        if '/deployments?' in path:
            return self.records
        raise AssertionError(path)

    def record(self, identity, state='success', days=14, run_id=42):
        self.records.append({'id': identity, 'created_at': (NOW - timedelta(days=days)).isoformat(),
                             'payload': {'schema': 1, 'run_id': run_id, 'plan_sha256': '1' * 64}})
        self.statuses[identity] = [{'state': state, 'created_at': (NOW - timedelta(days=days)).isoformat()}]


class AutomaticClockTests(unittest.TestCase):
    def setUp(self):
        self.policy = policy()
        self.api = NoticeAPI(self.policy)

    def evaluate(self, now=NOW, url=URL, run=100):
        return auto.evaluate(REPOSITORY, self.policy, LEGACY, url, now, run, self.api)

    def test_no_notice_is_a_successful_wait_without_mutation_or_history_calls(self):
        self.assertFalse(self.evaluate(url='')['due'])
        self.assertFalse(self.api.calls)

    def test_exact_fourteen_days_and_one_second_before(self):
        self.assertFalse(self.evaluate(NOW - timedelta(seconds=1))['due'])
        self.assertTrue(self.evaluate()['due'])

    def test_notice_edit_restarts_full_window(self):
        self.api.issue['updated_at'] = (NOW - timedelta(days=13)).isoformat()
        self.assertFalse(self.evaluate()['due'])

    def test_foreign_url_pull_request_closed_bot_or_untrusted_author_cannot_authorize(self):
        self.assertFalse(self.evaluate(url=URL.replace('fixture', 'foreign'))['due'])
        for field, value in [('pull_request', {}), ('state', 'closed'), ('author_association', 'NONE'),
                             ('user', {'type': 'Bot'}), ('body', 'unrelated announcement')]:
            original = copy.deepcopy(self.api.issue)
            self.api.issue[field] = value
            if field == 'pull_request':
                self.api.issue[field] = {'url': 'pull'}
            self.assertFalse(self.evaluate()['due'])
            self.api.issue = original

    def test_private_notice_and_future_date_fail_closed(self):
        self.api.private = True
        with self.assertRaisesRegex(ValueError, 'publicly'):
            self.evaluate()
        self.api.private = False
        self.api.issue['updated_at'] = (NOW + timedelta(seconds=1)).isoformat()
        with self.assertRaisesRegex(ValueError, 'timestamps'):
            self.evaluate()

    def test_changed_scope_or_retention_contract_requires_matching_notice(self):
        self.policy['keep_builds'] = 3
        self.assertFalse(self.evaluate()['due'])
        self.assertNotEqual(auto.marker(policy(), LEGACY), auto.marker(policy(), {**LEGACY, 'builds': ['new']}))

    def test_protection_refresh_does_not_change_published_contract(self):
        original = auto.marker(self.policy, LEGACY)
        self.policy['protected_digests'] = [digest('additional-protection')]
        self.policy['deployment_reviewed_at'] = (NOW - timedelta(days=1)).isoformat()
        self.assertEqual(original, auto.marker(self.policy, LEGACY))
        self.assertTrue(self.evaluate()['due'])

    def test_disabled_short_interval_or_short_grace_cannot_enable_deletion(self):
        self.policy['automatic']['enabled'] = False
        self.assertFalse(self.evaluate()['due'])
        for field in ('migration_days', 'interval_days'):
            settings = policy()
            settings['automatic'][field] = 13
            with self.assertRaises(ValueError):
                auto.validate_settings(settings)
        settings = policy()
        settings['grace_days'] = 13
        with self.assertRaises(ValueError):
            auto.validate_settings(settings)

    def test_stale_or_incomplete_fleet_review_waits_without_deleting(self):
        self.policy['deployment_reviewed_at'] = (NOW - timedelta(days=8)).isoformat()
        result = self.evaluate()
        self.assertFalse(result['due'])
        self.assertIn('seven days', result['reason'])
        self.policy['deployment_review_complete'] = False
        self.assertFalse(self.evaluate()['due'])

    def test_successful_cleanup_interval_is_fourteen_full_days(self):
        self.api.record(1)
        self.assertFalse(self.evaluate(NOW - timedelta(seconds=1))['due'])
        self.assertTrue(self.evaluate()['due'])

    def test_failed_missing_status_and_in_progress_records_block_even_reruns(self):
        for state in ('failure', 'error', 'in_progress', 'pending', 'inactive'):
            self.api.records.clear()
            self.api.record(1, state, days=30, run_id=100)
            self.assertFalse(self.evaluate(run=100)['due'])
        self.api.statuses[1] = []
        self.assertFalse(self.evaluate()['due'])

    def test_reviewed_failed_attempt_still_observes_interval(self):
        self.api.record(1, 'failure', days=13)
        self.policy['automatic']['acknowledged_failed_deployments'] = [1]
        self.assertFalse(self.evaluate()['due'])
        self.api.statuses[1][0]['created_at'] = (NOW - timedelta(days=14)).isoformat()
        self.assertTrue(self.evaluate()['due'])

    def test_history_api_error_propagates_instead_of_authorizing(self):
        def broken(path):
            if '/deployments?' in path:
                raise RuntimeError('API unavailable')
            return self.api(path)
        with self.assertRaises(RuntimeError):
            auto.evaluate(REPOSITORY, self.policy, LEGACY, URL, NOW, fetch=broken)

    def test_inactive_status_never_automatically_hides_failed_attempts(self):
        with mock.patch.object(auto, 'post') as post, mock.patch.dict(os.environ, {'GITHUB_RUN_ID': '7'}):
            auto.finish(REPOSITORY, 9, 'success')
        self.assertFalse(post.call_args.args[1]['auto_inactive'])


class LegacyScopeTests(unittest.TestCase):
    def setUp(self):
        self.registry = 'fixture/onion-relay'
        self.fixture = Builds(self.registry)
        self.policy = policy()
        arches = {arch: self.fixture.image('legacy-' + arch, '2.1.0', arch) for arch in ('amd64', 'arm64')}
        self.root = digest('legacy-index')
        self.fixture.manifests[self.root] = {'manifests': [
            {'digest': value, 'platform': {'os': 'linux', 'architecture': arch}} for arch, value in arches.items()]}
        self.legacy = {'registry': self.registry, 'builds': [{'index_digest': self.root, 'version': '2.1.0',
                         'architectures': arches, 'manifest_digests': sorted([self.root, *arches.values()])}]}

    def plan(self):
        return rebuild.plan_registry(self.fixture, self.registry, self.fixture.catalog, self.policy, NOW, legacy=self.legacy)

    def test_exact_legacy_index_and_children_are_eligible_and_repeat_is_safe(self):
        report = self.plan()
        self.assertTrue(set(self.legacy['builds'][0]['manifest_digests']) <= set(report['manifest_targets']))
        rebuild.apply_registry(self.fixture, report)
        self.assertFalse(self.plan()['manifest_targets'])
        self.assertTrue(self.fixture.tags['latest'] in self.fixture.manifests)

    def test_new_tag_or_deployment_pin_protects_both_legacy_architectures(self):
        self.policy['protected_image_ids'] = [self.legacy['builds'][0]['architectures']['arm64']]
        report = self.plan()
        self.assertFalse(set(self.legacy['builds'][0]['manifest_digests']) & set(report['manifest_targets']))

    def test_changed_graph_or_newer_version_cannot_expand_allowlist(self):
        row = self.legacy['builds'][0]
        row['manifest_digests'].append(digest('unreviewed'))
        with self.assertRaisesRegex(ValueError, 'reviewed complete'):
            self.plan()
        row['version'] = '2.2.0'
        with self.assertRaisesRegex(ValueError, 'newer'):
            self.plan()
        self.assertFalse(self.fixture.deletions)

    def test_manual_apply_with_automatic_policy_cannot_bypass_missing_notice(self):
        with tempfile.TemporaryDirectory() as work:
            work = Path(work)
            for name, data in [('policy', self.policy), ('catalog', self.fixture.catalog), ('legacy', self.legacy)]:
                (work / (name + '.json')).write_text(json.dumps(data))
            arguments = ['retention', '--owner', 'fixture', '--policy', str(work / 'policy.json'),
                         '--catalog', str(work / 'catalog.json'), '--legacy', str(work / 'legacy.json'),
                         '--output', str(work / 'result.json'), '--apply']
            with mock.patch.object(sys, 'argv', arguments), mock.patch.object(rebuild, 'Client') as client:
                with mock.patch.dict(os.environ, {'REGISTRY_RETIREMENT_NOTICE_URL': ''}):
                    with self.assertRaisesRegex(ValueError, 'Publish the notice'):
                        rebuild.main()
                client.assert_not_called()


class AutomaticApplyTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.directory = Path(self.work.name)
        self.hub, self.ghcr = Builds('fixture/onion-relay'), Builds('ghcr.io/fixture/onion-relay')
        catalog = copy.deepcopy(self.hub.catalog)
        catalog['current'] = catalog['current'] + self.ghcr.catalog['current']
        for item, other in zip(catalog['publications'], self.ghcr.catalog['publications']):
            item['rows'] += other['rows']
        settings = policy()
        settings['deployment_reviewed_at'] = rebuild.datetime.now(rebuild.timezone.utc).isoformat()
        for name, data in [('policy', settings), ('catalog', catalog), ('legacy', LEGACY)]:
            (self.directory / (name + '.json')).write_text(json.dumps(data))
        self.arguments = ['retention', '--owner', 'fixture', '--policy', str(self.directory / 'policy.json'),
                          '--catalog', str(self.directory / 'catalog.json'), '--legacy', str(self.directory / 'legacy.json'),
                          '--output', str(self.directory / 'result.json')]
        hub, ghcr = self.hub, self.ghcr
        class Router:
            def run(self, *args):
                return (ghcr if args[2].startswith('ghcr.io/') else hub).run(*args)
            def manifest(self, reference):
                return (ghcr if reference.startswith('ghcr.io/') else hub).manifest(reference)
        self.router = Router()

    def invoke(self, arguments, automatic=None):
        with mock.patch.object(sys, 'argv', arguments), mock.patch.object(rebuild, 'Client', return_value=self.router), \
                mock.patch.object(rebuild.prune, 'Packages', return_value=self.ghcr), \
                mock.patch.object(rebuild.prune, 'release_snapshot', return_value=[]):
            if automatic:
                with mock.patch.object(rebuild, 'load_automation', return_value=automatic):
                    rebuild.main()
            else:
                rebuild.main()

    def prepare(self):
        self.invoke(self.arguments)
        fingerprint = json.loads((self.directory / 'result.json').read_text())['plan_sha256']
        automatic = mock.Mock()
        automatic.evaluate.return_value = {'due': True, 'contract_sha256': '2' * 64}
        def start(*args):
            self.assertFalse(self.hub.deletions or self.ghcr.deletions)
            return 99
        automatic.start.side_effect = start
        return self.arguments + ['--apply', '--automatic', '--confirm-plan', fingerprint], automatic

    def test_durable_intent_precedes_deletion_and_success_follows_verification(self):
        arguments, automatic = self.prepare()
        self.invoke(arguments, automatic)
        automatic.start.assert_called_once()
        automatic.finish.assert_called_once_with(REPOSITORY, 99, 'success')
        result = json.loads((self.directory / 'result.json').read_text())
        self.assertTrue(result['completed'])
        self.assertEqual(result['cleanup_deployment_id'], 99)
        self.assertEqual(len(self.hub.deletions), 12)
        self.assertEqual(len(self.ghcr.deletions), 12)

    def test_changed_confirmation_never_records_intent_or_deletes(self):
        arguments, automatic = self.prepare()
        arguments[-1] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'unchanged reviewed preview'):
            self.invoke(arguments, automatic)
        automatic.start.assert_not_called()
        self.assertFalse(self.hub.deletions or self.ghcr.deletions)

    def test_durable_record_failure_prevents_any_delete(self):
        arguments, automatic = self.prepare()
        automatic.start.side_effect = RuntimeError('Deployment API unavailable')
        with self.assertRaises(RuntimeError):
            self.invoke(arguments, automatic)
        self.assertFalse(self.hub.deletions or self.ghcr.deletions)

    def test_registry_failure_marks_attempt_failed_and_keeps_requested_evidence(self):
        arguments, automatic = self.prepare()
        call = self.hub.run
        def fail(*args):
            if args[:2] == ('manifest', 'delete'):
                raise sp.CalledProcessError(1, args, stderr='Registry unavailable')
            return call(*args)
        self.hub.run = fail
        with self.assertRaises(sp.CalledProcessError):
            self.invoke(arguments, automatic)
        automatic.finish.assert_called_once_with(REPOSITORY, 99, 'failure')
        result = json.loads((self.directory / 'result.json').read_text())
        self.assertFalse(result['completed'])
        self.assertEqual(result['registries'][0]['attempts'][0]['status'], 'requested')


if __name__ == '__main__':
    unittest.main()
