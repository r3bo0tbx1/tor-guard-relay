#!/usr/bin/env python3
"""Gate a complete Trivy report without discarding unresolved findings."""
import json
import argparse
from pathlib import Path
import sys
from security_policy import assess


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--image-metadata', type=Path, help='Require the report to match this inspected image ID')
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    if args.image_metadata:
        metadata = json.loads(args.image_metadata.read_text())
        if report.get('Metadata', {}).get('ImageID') != metadata[0]['Id']:
            raise SystemExit('Security report does not match inspected image identity')
    summary = assess(report)
    print(json.dumps(summary, indent=2))
    raise SystemExit(0 if summary["passed"] else 1)
