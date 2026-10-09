import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "scripts/testing/security_policy.py"
spec = importlib.util.spec_from_file_location("gate", path)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class SecurityGateTests(unittest.TestCase):
    def report(self, findings=None, secrets=None):
        return {"SchemaVersion": 2, "ArtifactType": "container_image", "Metadata": {"ImageID": "sha256:test"},
                "Results": [{"Type": "alpine", "Vulnerabilities": findings or [], "Secrets": secrets or []}]}

    def test_full_report_retains_unfixed_advisory_but_blocks_available_security_fix(self):
        findings = [{"VulnerabilityID": "UNFIXED", "Severity": "UNKNOWN"},
                    {"VulnerabilityID": "FIXABLE", "Severity": "HIGH", "FixedVersion": "2.0"}]
        report = self.report(findings)
        result = gate.assess(report)
        self.assertEqual(result["vulnerability_findings"], 2)
        self.assertEqual(result["blocker_ids"], ["FIXABLE"])
        self.assertFalse(result["passed"])
        findings.pop()
        self.assertTrue(gate.assess(report)["passed"])
        self.assertEqual(len(report["Results"][0]["Vulnerabilities"]), 1)

    def test_secret_and_incomplete_report_fail_closed(self):
        self.assertFalse(gate.assess(self.report(secrets=[{"RuleID": "private-key"}]))["passed"])
        with self.assertRaises(ValueError):
            gate.assess({})

    def test_unfixed_severe_findings_block_and_remain_in_report(self):
        report = self.report([{"VulnerabilityID": "NO-FIX", "Severity": "CRITICAL"}])
        assessment = gate.assess(report)
        self.assertFalse(assessment['passed'])
        self.assertEqual(assessment['unfixed_high_critical'], 1)
        self.assertEqual(report['Results'][0]['Vulnerabilities'][0]['VulnerabilityID'], 'NO-FIX')

    def test_empty_or_malformed_scan_is_not_a_clean_scan(self):
        report = self.report()
        report['Results'] = []
        with self.assertRaises(ValueError): gate.assess(report)
        report = self.report([{'VulnerabilityID': 'UNKNOWN-SEVERITY'}])
        with self.assertRaises(ValueError): gate.assess(report)

    def go_report(self, function=None):
        frame = {'module': 'example.com/dependency', 'version': 'v1.0.0'}
        if function: frame['function'] = function
        return '\n'.join(json.dumps(message) for message in [
            {'config': {'protocol_version': 'v1.0.0', 'scan_level': 'symbol', 'scan_mode': 'source', 'go_version': 'go1.27.2'}},
            {'SBOM': {'roots': ['example.com/main'], 'modules': [{'path': 'example.com/dependency'}]}},
            {'osv': {'id': 'GO-UNFIXED'}}, {'finding': {'osv': 'GO-UNFIXED', 'trace': [frame]}}])

    def test_reachable_go_vulnerability_blocks_without_severity_or_fix(self):
        result = gate.assess_go(self.go_report('VulnerableFunction'))
        self.assertFalse(result['passed'])
        self.assertEqual(result['reachable_ids'], ['GO-UNFIXED'])

    def test_module_only_go_finding_is_retained_for_assessment(self):
        result = gate.assess_go(self.go_report())
        self.assertTrue(result['passed'])
        self.assertEqual(result['finding_count'], 1)

    def test_go_scan_errors_or_incomplete_stream_fail_closed(self):
        for text in ['', '{}', self.go_report() + '{', self.go_report().replace('symbol', 'module')]:
            with self.assertRaises(ValueError): gate.assess_go(text)


class DependencyPinTests(unittest.TestCase):
    def test_source_metadata_or_variant_pin_drift_is_rejected(self):
        spec = importlib.util.spec_from_file_location('pins', ROOT / 'scripts/testing/check-dependency-pins.py')
        pins = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(pins)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['Dockerfile', 'Dockerfile.edge']:
                (root / name).write_text((ROOT / name).read_text())
            original = pins.inspect_pins(root)['lyrebird_revision']
            edge = root / 'Dockerfile.edge'
            edge.write_text(edge.read_text().replace(original, '0' * 40, 1))
            with self.assertRaises(ValueError): pins.inspect_pins(root)
