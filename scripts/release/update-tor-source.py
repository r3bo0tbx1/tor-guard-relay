#!/usr/bin/env python3
"""Detect a stable Tor release and prepare its authenticated source pin locally."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('tor_source', ROOT / 'build/tor/source.py')
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


def published_versions(directory, owner):
    """Read this run's complete, digest-bound installed-version assessments."""
    if not re.fullmatch(r'[a-zA-Z0-9-]+', owner):
        raise ValueError('Expected the registry repository owner')
    installed = []
    for registry in ('dockerhub', 'ghcr'):
        repository = owner.lower() + '/onion-relay'
        if registry == 'ghcr':
            repository = 'ghcr.io/' + repository
        for variant in ('stable', 'edge'):
            for arch in ('amd64', 'arm64'):
                work = directory / f'watched-{registry}-{variant}-{arch}'
                assessment = json.loads((work / 'tor-version.json').read_text(encoding='utf-8'))
                manifest = json.loads((work / 'manifest.json').read_text(encoding='utf-8'))
                digests = [entry.get('digest', '') for entry in manifest.get('manifests', [])
                           if entry.get('platform', {}).get('os') == 'linux'
                           and entry.get('platform', {}).get('architecture') == arch]
                if len(digests) != 1 or not re.fullmatch(r'sha256:[a-f0-9]{64}', digests[0]):
                    raise ValueError('Expected one published architecture digest per assessment')
                image = repository + '@' + digests[0]
                if (assessment.get('image') != image or assessment.get('architecture') != arch
                        or (work / 'image-reference.txt').read_text(encoding='utf-8').strip() != image
                        or type(assessment.get('passed')) is not bool):
                    raise ValueError('Published Tor assessment does not match its image identity')
                versions = re.findall(r'(?m)^Tor version (\d+\.\d+\.\d+\.\d+)\.?(?=\s|$)',
                                      assessment.get('tor', ''))
                if len(versions) != 1:
                    raise ValueError('Expected one stable installed Tor version per published image')
                source.version_tuple(versions[0])
                installed.append({'image': image, 'architecture': arch, 'variant': variant,
                                  'version': versions[0]})
    return installed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', help='Select an exact stable upstream release instead of discovering it')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--write', action='store_true', help='Update only the local source lock after verification')
    mode.add_argument('--proposal-only', action='store_true', help='Return success for an authenticated proposal')
    parser.add_argument('--output', type=Path, help='Retain the current/proposed lock and update status as JSON')
    parser.add_argument('--published-reports', type=Path,
                        help="This workflow run's complete eight published-image assessments")
    parser.add_argument('--owner', help='Expected Docker Hub/GHCR owner for published assessments')
    args = parser.parse_args()
    if (args.published_reports is not None or args.owner) and not (args.published_reports and args.owner and args.version):
        parser.error('--published-reports and --owner require an explicit --version together')
    current = source.load_lock()
    report = {'current': current}
    try:
        latest = args.version or source.latest_release()
        source.version_tuple(latest)
        report.update(latest=latest, update_available=latest != current['version'])
        if source.version_tuple(latest) < source.version_tuple(current['version']):
            raise ValueError('Refusing to downgrade the reviewed Tor source version')
        installed = published_versions(args.published_reports, args.owner) if args.published_reports else []
        report['installed'] = installed
        report['minimum_allowed_version'] = max([current['version'], *[item['version'] for item in installed]],
                                                key=source.version_tuple)
        if source.version_tuple(latest) < source.version_tuple(report['minimum_allowed_version']):
            raise ValueError('Refusing to downgrade below Tor already installed in a published image')
        # An explicit request authenticates even an equal version. This proves
        # existence and rejects a changed checksum for the already reviewed pin.
        if report['update_available'] or args.version:
            with tempfile.TemporaryDirectory(prefix='tor-source-update-') as directory:
                verified = source.fetch_release(latest, directory,
                                                **({'expected': current} if not report['update_available'] else {}))
            report['verified'] = verified
            if report['update_available']:
                report['proposed'] = verified
            if args.write and report['update_available']:
                (ROOT / 'build/tor/source.json').write_text(json.dumps(verified, indent=2) + '\n',
                                                           encoding='utf-8', newline='\n')
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        if args.output:
            args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
        print(json.dumps(report, indent=2))
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
                summary.write('## 🧅 Tor source review\n\n')
                summary.write('Reviewed pin: `' + current['version'] + '`\n\n')
                if report.get('minimum_allowed_version'):
                    summary.write('Minimum allowed version: `' + report['minimum_allowed_version'] + '`\n\n')
                if 'error' in report:
                    summary.write('🚫 Request rejected or verification failed. See `tor-upstream.json`; no pin was written.\n')
                elif report['update_available']:
                    summary.write('🔎 Authenticated update `' + report['latest'] + '` requires review. '
                                  'See the retained source proposal.\n')
                else:
                    summary.write('✅ Selected/discovered version matches the reviewed pin. No update is needed.\n')
    return 1 if report['update_available'] and not (args.write or args.proposal_only) else 0


if __name__ == '__main__':
    raise SystemExit(main())
