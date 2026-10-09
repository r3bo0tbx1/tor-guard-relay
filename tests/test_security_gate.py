import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / "scripts/testing/check-security.py"
spec = importlib.util.spec_from_file_location("gate", path)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class SecurityGateTests(unittest.TestCase):
    def test_full_report_retains_unfixed_advisory_but_blocks_available_security_fix(self):
        findings = [{"VulnerabilityID": "UNFIXED", "Severity": "UNKNOWN"},
                    {"VulnerabilityID": "FIXABLE", "Severity": "HIGH", "FixedVersion": "2.0"}]
        report = {"SchemaVersion": 2, "Results": [{"Vulnerabilities": findings}]}
        result = gate.assess(report)
        self.assertEqual(result["vulnerability_findings"], 2)
        self.assertEqual(result["blocker_ids"], ["FIXABLE"])
        self.assertFalse(result["passed"])
        findings.pop()
        self.assertTrue(gate.assess(report)["passed"])
        self.assertEqual(len(report["Results"][0]["Vulnerabilities"]), 1)

    def test_secret_and_incomplete_report_fail_closed(self):
        self.assertFalse(gate.assess({"SchemaVersion": 2, "Results": [{"Secrets": [{"RuleID": "private-key"}]}]})["passed"])
        with self.assertRaises(ValueError):
            gate.assess({})
