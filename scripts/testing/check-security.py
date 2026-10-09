#!/usr/bin/env python3
"""Gate a complete Trivy report without discarding unresolved findings."""
import json
import argparse
import html
from pathlib import Path
from security_policy import assess


def append_summary(destination, report, assessment, image):
    def cell(value):
        return html.escape(str(value), quote=False).replace('|', '\\|').replace('`', '').replace('\r', ' ').replace('\n', ' ')

    labels = image.get('Config', {}).get('Labels') or {}
    outcome = '✅ Passed' if assessment['passed'] else '🚨 Blocked'
    lines = ['## 🛡️ Published image security assessment', '',
             '| Detail | Value |', '| --- | --- |',
             f"| Outcome | {outcome} |",
             f"| Published version | {cell(labels.get('org.opencontainers.image.version', 'unknown'))} |",
             f"| Published source | {cell(labels.get('org.opencontainers.image.revision', 'unknown'))} |",
             f"| Scanned image | {cell(report.get('ArtifactName', image['Id']))} |",
             f"| HIGH/CRITICAL findings | {assessment['high_critical']} |",
             f"| With a reported fix | {assessment['fixable_high_critical']} |",
             f"| Without a reported fix | {assessment['unfixed_high_critical']} |",
             f"| Secret findings | {assessment['secret_findings']} |", '']
    if assessment['high_critical']:
        lines += ['| Advisory | Package | Installed | Fixed version(s) | Severity |',
                  '| --- | --- | --- | --- | --- |']
        for result in report['Results']:
            for finding in result.get('Vulnerabilities') or []:
                if finding['Severity'] not in ('HIGH', 'CRITICAL'):
                    continue
                values = [finding['VulnerabilityID'], finding.get('PkgName', 'unknown'),
                          finding.get('InstalledVersion', 'unknown'),
                          finding.get('FixedVersion') or 'No fix reported', finding['Severity']]
                lines.append('| ' + ' | '.join(cell(value) for value in values) + ' |')
        lines.append('')
    if not assessment['passed']:
        lines += ['Merging source into main does not replace published images. Publish a reviewed release after all candidate gates pass, verify the registry digests, and rescan those digests. Findings without a fix require exposure assessment and mitigation.', '']
    lines += ['📎 The retained artifacts contain the complete report and inspected image identity.', '']
    with destination.open('a', encoding='utf-8', newline='\n') as output:
        output.write('\n'.join(lines) + '\n')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--image-metadata', type=Path, help='Require the report to match this inspected image ID')
    parser.add_argument('--summary', type=Path, help='Append a published-image assessment to a GitHub job summary')
    args = parser.parse_args()
    if args.summary and not args.image_metadata:
        parser.error('--summary requires --image-metadata')
    report = json.loads(args.report.read_text())
    if args.image_metadata:
        metadata = json.loads(args.image_metadata.read_text())
        if report.get('Metadata', {}).get('ImageID') != metadata[0]['Id']:
            raise SystemExit('Security report does not match inspected image identity')
    summary = assess(report)
    print(json.dumps(summary, indent=2))
    if args.summary:
        append_summary(args.summary, report, summary, metadata[0])
    raise SystemExit(0 if summary["passed"] else 1)
