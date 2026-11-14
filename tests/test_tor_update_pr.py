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
        review = patch.object(proposer, 'process_review')
        self.review = review.start()
        self.addCleanup(review.stop)

    def api(self, path, method='GET', body=None):
        if method != 'GET':
            self.writes.append((method, path, body))
            return {'html_url': 'https://fixture.invalid/pull/1', 'number': 1,
                    'assignees': [{'login': 'fixture'}]}
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
                      'user': {'login': BOT}, 'draft': True,
                      'body': proposer.PR_MARKER + f'\n<!-- tor-source-head:{HEAD} -->'
                              + '\n<!-- tor-source-update:version=0.4.9.16 -->',
                      'title': '⬆️ build(deps): update authenticated Tor source to 0.4.9.16',
                      'assignees': [{'login': 'fixture'}],
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

    def test_assigns_unassigned_draft_to_owner(self):
        self.existing()
        self.open[0]['assignees'] = []
        self.run_publish()
        self.assertEqual(self.writes, [('POST', f'repos/{REPO}/issues/1/assignees', {'assignees': ['fixture']})])
        self.review.assert_called_once()

    def test_same_proposal_is_a_noop_and_newer_proposal_updates_in_place(self):
        self.existing()
        self.run_publish()
        self.assertFalse(self.push_calls() or self.writes)
        self.review.assert_called_once_with(f'repos/{REPO}', REPO, self.open[0], HEAD, BOT,
                                            self.open[0]['title'],
                                            'Update the reviewed Tor source from 0.4.9.15 to 0.4.9.16.')
        self.pending = {**LOCK, 'version': '0.4.9.15'}
        self.run_publish()
        self.assertIn(f'--force-with-lease=refs/heads/{proposer.BRANCH}:{HEAD}', self.push_calls()[0])
        self.assertEqual([(method, path) for method, path, _ in self.writes], [('PATCH', f'repos/{REPO}/pulls/1')])

    def test_refresh_returns_a_ready_pr_to_draft(self):
        self.existing()
        self.open[0]['draft'] = False
        self.pending = LOCK
        with patch.object(proposer, 'github') as github:
            self.run_publish()
        github.assert_called_once_with(['pr', 'ready', '1', '--repo', REPO, '--undo'])
        self.assertIn('- [ ]', self.writes[0][2]['body'])

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


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.prefix = f'repos/{REPO}'
        self.path = f'{self.prefix}/pulls/1'
        self.comment_path = f'{self.prefix}/issues/1/comments'
        self.title = '⬆️ build(deps): update authenticated Tor source to 0.4.9.16'
        self.message = 'Update the reviewed Tor source from 0.4.9.15 to 0.4.9.16.'
        self.bot_account = {'login': BOT, 'type': 'Bot', 'id': 456}
        self.owner = {'content': '+1', 'user': {'id': 123}}
        self.pull = {'number': 1, 'state': 'open', 'draft': True, 'head': {'sha': HEAD},
                     'user': {'login': BOT}, 'base': {'ref': 'main'},
                     'body': f'{proposer.PR_MARKER}\n<!-- tor-source-head:{HEAD} -->\n'
                             + ''.join(f'- [ ] {item}\n' for item in proposer.REVIEW_ITEMS)}
        self.comment = {'id': 7, 'user': {'login': BOT}, 'body': f'<!-- tor-source-merge-approval:{HEAD} -->'}
        env = patch.dict(proposer.os.environ, {'GH_REVIEW_READ_TOKEN': 'fixture', 'GITHUB_REPOSITORY_OWNER_ID': '123'})
        env.start()
        self.addCleanup(env.stop)

    def run_review(self, responses, checks='[{"bucket":"pass"}]', exit_code=0):
        with patch.object(proposer, 'api', side_effect=responses) as api, \
                patch.object(proposer, 'github', return_value=Mock(stdout=checks, returncode=exit_code)) as github:
            proposer.process_review(self.prefix, REPO, self.pull, HEAD, BOT, self.title, self.message)
        return api, github

    def test_posts_a_new_comment_only_for_the_current_bot_revision(self):
        stale = {**self.comment, 'body': f'<!-- tor-source-merge-approval:{BASE} -->'}
        imitation = {**self.comment, 'user': {'login': 'someone'}}
        previous_policy = {**self.comment, 'body': f'<!-- tor-source-review:{HEAD} -->'}
        api, github = self.run_review([[stale, imitation, previous_policy], {}])
        self.assertEqual(api.call_args.args[:2], (self.comment_path, 'POST'))
        self.assertIn(self.comment['body'], api.call_args.args[2]['body'])
        github.assert_not_called()

    def test_requires_the_owner_and_all_required_checks(self):
        api, github = self.run_review([[self.comment], [{'content': '+1', 'user': {'id': 999}}]])
        self.assertEqual(api.call_count, 2)
        github.assert_not_called()
        for checks in ('[]', '[{"bucket":"pending"}]', '[{"bucket":"fail"}]'):
            with self.subTest(checks=checks):
                api, github = self.run_review([[self.comment], [self.owner]], checks)
                self.assertEqual(api.call_count, 2)
                github.assert_called_once()

    def test_checks_boxes_marks_ready_and_squash_merges_the_verified_head(self):
        api, github = self.run_review([[self.comment], [self.owner], self.pull, self.bot_account, {}, {'merged': True}])
        patch_call, merge_call = api.call_args_list[-2:]
        self.assertEqual(patch_call.args[:2], (self.path, 'PATCH'))
        self.assertEqual(patch_call.args[2]['body'].count('- [x] '), 2)
        self.assertEqual(github.call_args.args[0], ['pr', 'ready', '1', '--repo', REPO])
        self.assertEqual(merge_call.args, (f'{self.path}/merge', 'PUT', {
            'sha': HEAD, 'merge_method': 'squash', 'commit_title': self.title,
            'commit_message': f'{self.message}\n\nCo-authored-by: {BOT} <456+{BOT}@users.noreply.github.com>'}))

    def test_retries_a_merge_after_the_pr_was_marked_ready(self):
        ready = {**self.pull, 'draft': False, 'body': self.pull['body'].replace('[ ]', '[x]')}
        self.pull = ready
        api, github = self.run_review([[self.comment], [self.owner], ready, self.bot_account, {'merged': True}])
        self.assertEqual(api.call_args.args[:2], (f'{self.path}/merge', 'PUT'))
        self.assertEqual(github.call_count, 1)

    def test_head_change_blocks_writes(self):
        changed = {**self.pull, 'head': {'sha': BASE}}
        with self.assertRaisesRegex(ValueError, 'changed while checking'):
            self.run_review([[self.comment], [self.owner], changed])
