"""Prove main rebuilds include merged fixes without moving release tags."""
import importlib.util
from pathlib import Path
import subprocess as sp
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('select_source',
    Path(__file__).resolve().parents[1] / 'scripts/release/select-source.py')
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)


class RebuildSourceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git('init', '-b', 'main')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'user.name', 'Release fixture')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('config', 'tag.gpgsign', 'false')
        (self.root / 'README.md').write_text('🧅 <!-- RELAY_VERSION -->v2.2.0<!-- /RELAY_VERSION -->', encoding='utf-8')
        self.git('add', 'README.md')
        self.git('commit', '-m', 'fixture release')
        self.tagged = self.git('rev-parse', 'HEAD')
        self.git('tag', 'v2.2.0')
        (self.root / 'merged-fix').write_text('included in main rebuild')
        self.git('add', 'merged-fix')
        self.git('commit', '-m', 'fixture merged fix')
        self.main = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', self.main)

    def git(self, *args):
        return sp.check_output(['git', '-C', str(self.root), *args],
                              text=True, stderr=sp.DEVNULL).strip()

    def select(self, event='workflow_dispatch', ref='main', revision=None, tag='', publish=False):
        return selection.select(self.root, event, ref, revision or self.main, tag, publish)

    def test_default_manual_build_uses_main_and_preserves_tag(self):
        result = self.select(publish=True)
        self.assertEqual(result['sha'], self.main)
        self.assertNotEqual(result['sha'], self.tagged)
        self.assertEqual(result['policy_sha'], self.main)
        self.assertEqual(result['version'], '2.2.0')
        self.assertEqual(result['publish'], 'true')
        self.assertEqual(result['release'], 'false')
        self.assertEqual(self.git('rev-parse', 'v2.2.0^{commit}'), self.tagged)

    def test_dispatch_captures_immutable_revision_when_main_advances(self):
        (self.root / 'merged-fix').write_text('later change')
        self.git('commit', '-am', 'fixture later change')
        later = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', later)
        result = self.select()
        self.assertEqual(result['sha'], self.main)
        self.assertEqual(result['policy_sha'], later)

    def test_manual_defaults_to_validation(self):
        self.assertEqual(self.select()['publish'], 'false')

    def test_explicit_tag_rebuild_keeps_tagged_source(self):
        result = self.select(tag='v2.2.0', publish=True)
        self.assertEqual(result['sha'], self.tagged)
        self.assertEqual(result['release'], 'false')

    def test_schedule_keeps_merged_fixes_instead_of_reverting_to_tag(self):
        result = self.select(event='schedule')
        self.assertEqual(result['sha'], self.main)
        self.assertEqual(result['source_ref'], 'main')
        self.assertEqual(result['publish'], 'true')
        self.assertEqual(result['release'], 'false')

    def test_tag_push_creates_release_from_tag(self):
        result = self.select(event='push', ref='v2.2.0')
        self.assertEqual(result['sha'], self.tagged)
        self.assertEqual(result['publish'], 'true')
        self.assertEqual(result['release'], 'true')

    def test_feature_branch_cannot_publish_as_main(self):
        with self.assertRaises(ValueError):
            self.select(ref='feature', publish=True)

    def test_unmerged_revision_and_release_tag_are_rejected(self):
        self.git('checkout', '-b', 'unmerged')
        (self.root / 'merged-fix').write_text('not reviewed')
        self.git('commit', '-am', 'fixture unmerged')
        unmerged = self.git('rev-parse', 'HEAD')
        with self.assertRaises(sp.CalledProcessError):
            self.select(revision=unmerged, publish=True)
        self.git('tag', 'v2.2.1')
        with self.assertRaises(sp.CalledProcessError):
            self.select(tag='v2.2.1', publish=True)

    def test_version_bump_cannot_overwrite_previous_release_namespace(self):
        (self.root / 'README.md').write_text('<!-- RELAY_VERSION -->v2.3.0<!-- /RELAY_VERSION -->')
        self.git('commit', '-am', 'fixture next version')
        bumped = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', bumped)
        with self.assertRaises(ValueError):
            self.select(revision=bumped, publish=True)

    def test_invalid_tag_and_ref_expression_are_rejected(self):
        for tag in ('main', '--help', 'v2.2.0^{}'):
            with self.assertRaises(ValueError):
                self.select(tag=tag)
        with self.assertRaises(ValueError):
            self.select(revision='main')
