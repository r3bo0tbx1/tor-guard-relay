import json
from pathlib import Path
import subprocess as sp
import sys
import tempfile
import unittest


CHECKER = Path(__file__).resolve().parents[1] / 'scripts/testing/check-security.py'


class PublishedSecuritySummaryTests(unittest.TestCase):
    def run_check(self, directory, findings, inspected_id='sha256:fixture'):
        report = {'SchemaVersion': 2, 'ArtifactType': 'container_image',
                  'ArtifactName': 'example.invalid/relay@sha256:fixture',
                  'Metadata': {'ImageID': 'sha256:fixture'},
                  'Results': [{'Type': 'gobinary', 'Vulnerabilities': findings}]}
        metadata = [{'Id': inspected_id, 'Config': {'Labels': {
            'org.opencontainers.image.version': '2.1.0|<script>\nextra',
            'org.opencontainers.image.revision': 'reviewed-source'}}}]
        (directory / 'trivy.json').write_text(json.dumps(report), encoding='utf-8')
        (directory / 'image.json').write_text(json.dumps(metadata), encoding='utf-8')
        summary = directory / 'summary.md'
        summary.write_text('Existing job evidence\n', encoding='utf-8')
        result = sp.run([sys.executable, str(CHECKER), str(directory / 'trivy.json'),
                         '--image-metadata', str(directory / 'image.json'), '--summary', str(summary)],
                        capture_output=True, text=True, encoding='utf-8')
        return result, summary.read_text(encoding='utf-8')

    def test_blockers_remain_failed_and_summary_preserves_fix_status(self):
        findings = [
            {'VulnerabilityID': 'FIXABLE', 'Severity': 'HIGH', 'PkgName': 'stdlib',
             'InstalledVersion': 'v1.26.8', 'FixedVersion': '1.27.2'},
            {'VulnerabilityID': 'UNFIXED', 'Severity': 'CRITICAL', 'PkgName': 'other'},
        ]
        with tempfile.TemporaryDirectory() as directory:
            result, summary = self.run_check(Path(directory), findings)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(json.loads(result.stdout)['passed'])
        self.assertIn('FIXABLE | stdlib | v1.26.8 | 1.27.2', summary)
        self.assertIn('No fix reported', summary)
        self.assertIn('| Without a reported fix | 1 |', summary)
        self.assertIn('2.1.0\\|&lt;script&gt; extra', summary)
        self.assertTrue(summary.startswith('Existing job evidence\n'))
        self.assertIn('does not replace published images', summary)

    def test_passing_report_remains_successful(self):
        with tempfile.TemporaryDirectory() as directory:
            result, summary = self.run_check(Path(directory), [])
        self.assertEqual(result.returncode, 0)
        self.assertTrue(json.loads(result.stdout)['passed'])
        self.assertIn('✅ Passed', summary)
        self.assertNotIn('Publish a reviewed release', summary)

    def test_wrong_image_identity_fails_without_misleading_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            result, summary = self.run_check(Path(directory), [], inspected_id='sha256:different')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('does not match inspected image identity', result.stderr)
        self.assertEqual(summary, 'Existing job evidence\n')
