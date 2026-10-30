"""Fleet proposals preserve retention safeguards and cannot renew stale evidence."""
import copy
from datetime import timedelta
import json
import subprocess as sp
import sys
import tempfile
from pathlib import Path
import unittest

from test_rebuild_retention import NOW, POLICY, ROOT, digest, load

review = load('fleet_review', 'scripts/release/review-fleet-protection.py')
automatic = load('fleet_automatic', 'scripts/release/automatic-retention.py')


class FleetReviewTests(unittest.TestCase):
    def setUp(self):
        self.policy = copy.deepcopy(POLICY)
        self.policy.update({'protected_digests': [digest('keep')],
                            'protected_image_ids': [digest('rollback')],
                            'automatic': {'enabled': True, 'migration_days': 14, 'interval_days': 14}})
        self.reports = [self.report(str(n), days=n) for n in range(3)]

    def report(self, engine, days=0):
        return {'schema': 1, 'owner': 'fixture', 'engine_id_sha256': digest(engine)[7:],
                'observed_at': (NOW - timedelta(days=days)).isoformat(), 'relay_containers': 2,
                'protected_image_ids': [digest(engine + '-image')],
                'protected_digests': [digest(engine + '-index')], 'deployment_review_complete': False}

    def prepare(self, **overrides):
        args = dict(policy=self.policy, reports=self.reports, expected_engines=3,
                    complete=True, owner='fixture', now=NOW)
        args.update(overrides)
        return review.prepare(**args)

    def test_additive_proposal_preserves_settings_and_uses_oldest_observation(self):
        before = copy.deepcopy(self.policy)
        result = self.prepare()
        self.assertEqual(self.policy, before)
        self.assertEqual(result['automatic'], before['automatic'])
        self.assertEqual(result['keep_builds'], before['keep_builds'])
        self.assertEqual(result['grace_days'], before['grace_days'])
        self.assertEqual(automatic.marker(result, {'images': []}), automatic.marker(before, {'images': []}))
        self.assertEqual(result['deployment_reviewed_at'], '2026-10-08T00:00:00Z')
        self.assertTrue(result['deployment_review_complete'])
        for field in ('protected_digests', 'protected_image_ids'):
            self.assertEqual(set(result[field]), set(before[field]).union(*(set(r[field]) for r in self.reports)))

    def test_missing_duplicate_empty_or_unconfirmed_fleet_is_blocked(self):
        for kwargs in ({'reports': self.reports[:2]}, {'reports': [self.reports[0]] * 3},
                       {'complete': False}, {'expected_engines': 0}, {'expected_engines': True}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                self.prepare(**kwargs)
        for field, value in (('relay_containers', 0), ('relay_containers', True),
                             ('protected_image_ids', []), ('deployment_review_complete', True)):
            reports = copy.deepcopy(self.reports)
            reports[0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.prepare(reports=reports)

    def test_stale_future_malformed_or_wrong_owner_reports_are_blocked(self):
        for field, value in (('observed_at', (NOW - timedelta(days=7, seconds=1)).isoformat()),
                             ('observed_at', (NOW + timedelta(seconds=1)).isoformat()),
                             ('observed_at', '2026-10-10'), ('observed_at', None),
                             ('owner', 'other'), ('schema', True), ('schema', 0),
                             ('engine_id_sha256', ''), ('protected_digests', ['sha256:short'])):
            reports = copy.deepcopy(self.reports)
            reports[0][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                self.prepare(reports=reports)

    def test_exact_seven_day_boundary_and_reprocessing_do_not_extend_review(self):
        reports = [self.report(str(n), days=7) for n in range(3)]
        result = self.prepare(reports=reports)
        self.assertEqual(result['deployment_reviewed_at'], '2026-10-03T00:00:00Z')
        with self.assertRaises(ValueError):
            self.prepare(reports=reports, now=NOW + timedelta(seconds=1))

    def test_cli_never_overwrites_policy_or_an_existing_proposal(self):
        with tempfile.TemporaryDirectory() as work:
            directory = Path(work)
            policy = directory / 'policy.json'
            data = json.dumps(self.policy)
            policy.write_text(data, encoding='utf-8')
            report = directory / 'report.json'
            fresh = self.report('engine')
            fresh['observed_at'] = review.datetime.now(review.timezone.utc).isoformat()
            report.write_text(json.dumps(fresh), encoding='utf-8')
            args = [sys.executable, '-B', str(ROOT / 'scripts/release/review-fleet-protection.py'),
                    '--policy', str(policy), '--report', str(report), '--expected-engines', '1',
                    '--owner', 'fixture', '--confirm-complete-fleet', '--output']
            blocked = sp.run([*args, str(policy)], capture_output=True, text=True)
            self.assertNotEqual(blocked.returncode, 0)
            self.assertEqual(policy.read_text(encoding='utf-8'), data)
            target = directory / 'proposal.json'
            success = sp.run([*args, str(target)], capture_output=True, text=True)
            self.assertEqual(success.returncode, 0, success.stderr)
            original = target.read_bytes()
            self.assertNotEqual(sp.run([*args, str(target)], capture_output=True).returncode, 0)
            self.assertEqual(target.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
