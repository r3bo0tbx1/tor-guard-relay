"""Exercise version synchronization against a disposable repository."""
from pathlib import Path
import os
import subprocess as sp
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class VersionSyncTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="relay-version-test-")
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        sp.run(["git", "init", "-q", str(self.root)], check=True)
        self.write("scripts/release/check-versions.py",
                   (ROOT / "scripts/release/check-versions.py").read_text())
        self.write("Dockerfile", 'FROM alpine:3.24.3@sha256:' + "a" * 64 +
                   '\nLABEL org.opencontainers.image.base.name="docker.io/library/alpine:3.24.2"\n')
        self.write("README.md", "<!-- RELAY_VERSION -->v2.2.0<!-- /RELAY_VERSION -->\n"
                   "Alpine Linux 3.24.2; alpine:3.24.2; onion-relay:2.2.0\n")
        for name in ("docs/README.md", "docs/BACKUP.md", "docs/TOOLS.md",
                     "scripts/release/README.md"):
            self.write(name, "Alpine 3.24.2\n")
        for number in range(20):
            self.write(f"docs/current-{number}.md", "docker run alpine:3.24.2 sh\n")
        self.release = ("<!-- RELAY_VERSION -->v2.2.0<!-- /RELAY_VERSION -->\n"
                        "Alpine 3.24.2; alpine:3.24.2; onion-relay:2.2.0\n")
        self.write("docs/releases/v2.2.0.md", self.release)
        self.history = ("## [v2.2.0] - 2026-10-10\n\n"
                        "Alpine 3.24.2; alpine:3.24.2; onion-relay:2.2.0\n"
                        "## [v2.1.0] - 2026-07-22\n\nAlpine 3.24.1\n")
        self.write("CHANGELOG.md", "<!-- RELAY_VERSION -->v2.2.0<!-- /RELAY_VERSION -->\n"
                   "## [Unreleased]\n\nUpdated Alpine to 3.24.2.\n\n" + self.history)

    def write(self, name, text):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8", newline="\n")

    def run_check(self, *args):
        return sp.run([sys.executable, str(self.root / "scripts/release/check-versions.py"), *args],
                      cwd=self.root, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
                      text=True, capture_output=True)

    def test_check_rejects_unsynchronized_base_label_and_current_docs(self):
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Dockerfile", result.stderr)
        self.assertIn("README.md", result.stderr)
        self.assertNotIn("docs/releases/v2.2.0.md", result.stderr)
        self.assertEqual((self.root / "docs/releases/v2.2.0.md").read_text(), self.release)

    def test_write_updates_current_references_and_is_idempotent(self):
        result = self.run_check("--write")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('alpine:3.24.3@sha256:' + "a" * 64,
                      (self.root / "Dockerfile").read_text())
        self.assertIn('docker.io/library/alpine:3.24.3',
                      (self.root / "Dockerfile").read_text())
        self.assertIn("Alpine Linux 3.24.3; alpine:3.24.3", (self.root / "README.md").read_text())
        snapshot = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob("*")
                    if p.is_file() and ".git" not in p.relative_to(self.root).parts}
        self.assertEqual(self.run_check().returncode, 0)
        self.assertEqual(self.run_check("--write").returncode, 0)
        self.assertTrue(all((self.root / p).read_bytes() == data for p, data in snapshot.items()))

    def test_project_bump_preserves_release_notes_and_changelog_facts(self):
        result = self.run_check("--write", "--version", "2.3.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("v2.3.0", (self.root / "README.md").read_text())
        self.assertIn("onion-relay:2.3.0", (self.root / "README.md").read_text())
        self.assertEqual((self.root / "docs/releases/v2.2.0.md").read_text(), self.release)
        changelog = (self.root / "CHANGELOG.md").read_text()
        self.assertTrue(changelog.endswith(self.history))
        self.assertIn("Updated Alpine to 3.24.2.", changelog)
        self.assertIn("<!-- RELAY_VERSION -->v2.3.0<!-- /RELAY_VERSION -->", changelog)

    def test_print_version_has_no_file_mutations_or_status_noise(self):
        before = (self.root / 'README.md').read_bytes()
        result = self.run_check('--print-version')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '2.2.0\n')
        self.assertEqual((self.root / 'README.md').read_bytes(), before)
        invalid = self.run_check('--print-version', '--version', 'invalid')
        self.assertNotEqual(invalid.returncode, 0)


if __name__ == "__main__":
    unittest.main()
