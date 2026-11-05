"""Exercise authenticated proposals and bot branch ownership without GitHub writes."""
import base64
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from test_tor_source import LOCK, ROOT, module


proposer = module('tor_proposer', ROOT / 'scripts/release/propose-tor-update.py')
REPO = 'fixture/tor-guard-relay'
BASE, HEAD = 'a' * 40, 'b' * 40
BOT = 'tor-update[bot]'
NEW = {**LOCK, 'version': '0.4.9.16', 'sha256': '2' * 64}
REPORT = {'current': LOCK, 'latest': NEW['version'], 'update_available': True,
          'verified': NEW, 'proposed': NEW}
PLAN = {'current': LOCK, 'proposed': NEW, 'highest_installed': LOCK['version']}
ENV = {'GITHUB_ACTIONS': 'true', 'GITHUB_REF': 'refs/heads/main', 'GITHUB_REPOSITORY': REPO,
       'GITHUB_EVENT_NAME': 'schedule', 'GITHUB_RUN_ID': '42', 'GH_TOKEN': 'fixture'}


class PrepareTests(unittest.TestCase):
    def test_current_version_needs_no_image_reports_or_credentials(self):
        report = {'current': LOCK, 'latest': LOCK['version'], 'update_available': False}
        with patch.object(proposer.updater, 'published_versions') as images:
            self.assertIsNone(proposer.prepare(report, None, 'fixture', LOCK))
            images.assert_not_called()

    def test_rejects_unverified_proposal_and_stale_source_report(self):
        with patch.object(proposer.updater, 'published_versions') as images:
            for report in ({**REPORT, 'verified': None}, {**REPORT, 'current': NEW},
                           {**REPORT, 'proposed': None}, {**REPORT, 'error': 'invalid signature'}):
                with self.subTest(report=report), self.assertRaises(ValueError):
                    proposer.prepare(report, None, 'fixture', LOCK)
            images.assert_not_called()

    def test_schedule_also_rejects_downgrade_against_published_images(self):
        with patch.object(proposer.updater, 'published_versions', return_value=[{'version': '0.4.9.17'}]):
            with self.assertRaisesRegex(ValueError, 'already installed'):
                proposer.prepare(REPORT, None, 'fixture', LOCK)
        with patch.object(proposer.updater, 'published_versions', return_value=[{'version': LOCK['version']}]):
            self.assertEqual(proposer.prepare(REPORT, None, 'fixture', LOCK), PLAN)


class PublishTests(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        root = Path(work.name)
        self.lock = root / proposer.LOCK
        self.lock.parent.mkdir(parents=True)
        self.lock.write_text(json.dumps(LOCK))
        for mock in (patch.dict(proposer.os.environ, ENV), patch.object(proposer, 'ROOT', root),
                     patch.object(proposer.source, 'load_lock', return_value=LOCK)):
            mock.start()
            self.addCleanup(mock.stop)
        self.git = Mock(side_effect=lambda *args, **kwargs: BASE if args[0] == 'rev-parse' else '')
        mock = patch.object(proposer, 'git', self.git)
        mock.start()
        self.addCleanup(mock.stop)
        self.head = ''
        self.parent = BASE
        self.open = []
        self.closed = []
        self.pending = NEW
        self.bot_author = BOT
        self.bot_committer = BOT
        self.main = BASE
        self.writes = []
        mock = patch.object(proposer, 'api', self.api)
        mock.start()
        self.addCleanup(mock.stop)

    def api(self, path, method='GET', body=None):
        if method != 'GET':
            self.writes.append((method, path, body))
            return {'html_url': 'https://fixture.invalid/pull/1'}
        if '/matching-refs/' in path:
            return [{'ref': f'refs/heads/{proposer.BRANCH}', 'object': {'sha': self.head}}] if self.head else []
        if 'state=open' in path:
            return self.open
        if 'state=closed' in path:
            return self.closed
        if path.endswith('/git/ref/heads/main'):
            return {'object': {'sha': self.main}}
        if path.startswith('users/'):
            return {'login': BOT, 'type': 'Bot', 'id': 123}
        if '/commits/' in path:
            return {'author': {'login': self.bot_author}, 'committer': {'login': self.bot_committer},
                    'parents': [{'sha': self.parent}], 'commit': {'message': proposer.MARKER},
                    'files': [{'filename': proposer.LOCK, 'status': 'modified'}]}
        if '/compare/' in path:
            return {'status': 'ahead'}
        if '/contents/' in path:
            return {'encoding': 'base64', 'content': base64.b64encode(json.dumps(self.pending).encode()).decode()}
        raise AssertionError(path)

    def existing(self):
        self.head = HEAD
        self.open = [{'head': {'sha': HEAD, 'repo': {'full_name': REPO}}, 'base': {'ref': 'main'},
                      'user': {'login': BOT}, 'body': proposer.PR_MARKER + '\n<!-- tor-source-update:version=0.4.9.16 -->',
                      'title': '⬆️ build(deps): update authenticated Tor source to 0.4.9.16',
                      'number': 1, 'html_url': 'https://fixture.invalid/pull/1'}]

    def run_publish(self):
        proposer.publish(PLAN, REPO, 'tor-update')

    def push_calls(self):
        return [call.args for call in self.git.call_args_list if 'push' in call.args]

    def test_creates_one_draft_and_uses_an_empty_branch_lease(self):
        self.run_publish()
        self.assertEqual(len(self.writes), 1)
        method, path, body = self.writes[0]
        self.assertEqual((method, path, body['head'], body['base'], body['draft']),
                         ('POST', f'repos/{REPO}/pulls', proposer.BRANCH, 'main', True))
        self.assertIn(f'--force-with-lease=refs/heads/{proposer.BRANCH}:', self.push_calls()[0])
        self.assertEqual(json.loads(self.lock.read_text()), NEW)

    def test_same_proposal_is_a_noop_and_newer_proposal_updates_in_place(self):
        self.existing()
        self.run_publish()
        self.assertFalse(self.push_calls() or self.writes)
        self.pending = {**LOCK, 'version': '0.4.9.15'}
        self.run_publish()
        self.assertIn(f'--force-with-lease=refs/heads/{proposer.BRANCH}:{HEAD}', self.push_calls()[0])
        self.assertEqual([(method, path) for method, path, _ in self.writes], [('PATCH', f'repos/{REPO}/pulls/1')])

    def test_partial_push_can_create_missing_pr_without_rewriting_branch(self):
        self.head = HEAD
        self.run_publish()
        self.assertFalse(self.push_calls())
        self.assertEqual(self.writes[0][0], 'POST')

    def test_declined_release_is_not_reopened(self):
        self.closed = [{'user': {'login': BOT}, 'merged_at': None,
                        'body': proposer.PR_MARKER + '\n<!-- tor-source-update:version=0.4.9.16 -->'}]
        self.run_publish()
        self.assertFalse(self.push_calls() or self.writes)

    def test_foreign_branch_and_newer_pending_proposal_block_updates(self):
        self.existing()
        self.bot_author = 'maintainer'
        with self.assertRaisesRegex(ValueError, 'managed bot commit'):
            self.run_publish()
        self.bot_author = BOT
        self.bot_committer = 'maintainer'
        with self.assertRaisesRegex(ValueError, 'managed bot commit'):
            self.run_publish()
        self.bot_committer = BOT
        self.pending = {**NEW, 'version': '0.4.9.17'}
        with self.assertRaisesRegex(ValueError, 'downgrade'):
            self.run_publish()
        self.assertFalse(self.push_calls() or self.writes)

    def test_stale_main_and_wrong_event_block_writes(self):
        self.main = HEAD
        with self.assertRaisesRegex(ValueError, 'Main advanced'):
            self.run_publish()
        with patch.dict(proposer.os.environ, {'GITHUB_EVENT_NAME': 'pull_request'}):
            with self.assertRaisesRegex(ValueError, 'main-branch workflow'):
                self.run_publish()
        self.assertFalse(self.push_calls() or self.writes)
