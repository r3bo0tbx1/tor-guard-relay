"""Exercise release provenance using local Git history, without network access."""
import importlib.util
from pathlib import Path
import subprocess as sp
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release_source',
    Path(__file__).resolve().parents[1] / 'scripts/release/prepare-source.py')
release_source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_source)


class ReviewedReleaseSourceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git('init', '-b', 'main')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'user.name', 'Release fixture')
        self.git('config', 'commit.gpgsign', 'false')
        (self.root / 'version').write_text('old')
        self.git('add', 'version')
        self.git('commit', '-m', 'fixture baseline')
        self.source = self.git('rev-parse', 'HEAD')
        (self.root / 'version').write_text('new')
        self.git('commit', '-am', 'fixture policy')
        self.policy = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', self.policy)

    def git(self, *args):
        return sp.check_output(['git', '-C', str(self.root), *args],
            text=True, stderr=sp.DEVNULL).strip()

    def test_reviewed_source_and_policy_remain_separate(self):
        source, policy = release_source.prepare(self.root, self.source, self.policy)
        self.assertEqual((source / 'version').read_text(), 'old')
        self.assertEqual((policy / 'version').read_text(), 'new')
        self.assertEqual(sp.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'],
            text=True).strip(), self.source)

    def test_unreviewed_commit_rejected_before_any_tree_is_created(self):
        self.git('checkout', '-b', 'unreviewed-fixture')
        (self.root / 'version').write_text('unreviewed')
        self.git('commit', '-am', 'fixture unreviewed')
        unreviewed = self.git('rev-parse', 'HEAD')
        for source, policy in ((unreviewed, self.policy), (self.source, unreviewed)):
            with self.assertRaises(sp.CalledProcessError):
                release_source.prepare(self.root, source, policy)
            self.assertFalse((self.root / '.release-source').exists())
            self.assertFalse((self.root / '.release-policy').exists())

    def test_ref_expression_rejected(self):
        with self.assertRaises(ValueError):
            release_source.prepare(self.root, 'main', self.policy)

    def test_existing_workspace_is_never_overwritten(self):
        (self.root / '.release-policy').mkdir()
        with self.assertRaises(ValueError):
            release_source.prepare(self.root, self.source, self.policy)
        self.assertFalse((self.root / '.release-source').exists())
