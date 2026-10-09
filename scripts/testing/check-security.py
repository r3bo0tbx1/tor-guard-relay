#!/usr/bin/env python3
"""Gate a complete Trivy report without discarding unresolved findings."""
import json
from pathlib import Path
import sys


def assess(report):
    if report.get("SchemaVersion") != 2 or not isinstance(report.get("Results"), list):
        raise ValueError("Expected a complete Trivy schema-v2 report")
    vulnerabilities = []
    secrets = []
    for result in report["Results"]:
        vulnerabilities.extend(result.get("Vulnerabilities") or [])
        secrets.extend(result.get("Secrets") or [])
    blockers = [finding for finding in vulnerabilities
                if finding.get("Severity") in ("HIGH", "CRITICAL")
                and finding.get("FixedVersion")]
    return {"vulnerability_findings": len(vulnerabilities),
            "fixable_high_critical": len(blockers), "secret_findings": len(secrets),
            "blocker_ids": [finding["VulnerabilityID"] for finding in blockers],
            "passed": not blockers and not secrets}


if __name__ == "__main__":
    summary = assess(json.loads(Path(sys.argv[1]).read_text()))
    print(json.dumps(summary, indent=2))
    raise SystemExit(0 if summary["passed"] else 1)
