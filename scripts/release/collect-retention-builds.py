#!/usr/bin/env python3
"""Collect reviewed publication evidence; never guess unrecorded Hub digests."""
import argparse
from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import re
import subprocess as sp
import tarfile
import tempfile

spec = importlib.util.spec_from_file_location('readiness', Path(__file__).with_name('check-retention-ready.py'))
ready = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ready)


def api(path):
    return json.loads(sp.check_output(['gh', 'api', '--paginate', '--slurp', path],
                                     text=True, encoding='utf-8'))


def original_ids(archive, version, source):
    expected = {f'candidate-{variant}-{arch}/image.json': (variant, arch)
                for variant in ('stable', 'edge') for arch in ('amd64', 'arm64')}
    found = {}
    with tarfile.open(archive, 'r:gz') as bundle:
        for member in bundle:
            name = member.name.removeprefix('./')
            if name not in expected:
                continue
            if not member.isfile() or member.size > 4 * 1024 * 1024 or name in found:
                raise ValueError('Invalid or duplicate original-release image evidence')
            image, = json.load(bundle.extractfile(member))
            variant, arch = expected[name]
            labels = image.get('Config', {}).get('Labels', {})
            if (image.get('Architecture') != arch or image.get('Os') != 'linux'
                    or labels.get('org.opencontainers.image.version') != version + ('-edge' if variant == 'edge' else '')
                    or labels.get('org.opencontainers.image.revision') != source
                    or not re.fullmatch(r'sha256:[0-9a-f]{64}', image.get('Id', ''))):
                raise ValueError('Original-release image identity does not match the Git tag')
            found[name] = image['Id']
    if found.keys() != expected.keys():
        raise ValueError('Original-release evidence must contain all four image identities')
    return sorted(found.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--readiness', type=Path, required=True)
    parser.add_argument('--current', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9-]+/tor-guard-relay', args.repository):
        raise ValueError('Expected the relay repository')
    current = json.loads(args.current.read_text(encoding='utf-8'))
    version, = {row['tags'][0] for row in current if row['variant'] == 'stable'}
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Current publication has no stable release version')
    latest = json.loads(args.readiness.read_text(encoding='utf-8'))
    publications, skipped = [], []
    cutoff = datetime.now(timezone.utc) - timedelta(days=90)
    pages = api(f'repos/{args.repository}/actions/workflows/release.yml/runs?status=completed&per_page=100')
    audits = [run for page in api(f'repos/{args.repository}/actions/workflows/security.yml/runs?event=workflow_run&status=success&per_page=100')
              for run in page['workflow_runs']]
    with tempfile.TemporaryDirectory(prefix='relay-retention-evidence-') as work:
        work = Path(work)
        for run in (run for page in pages for run in page['workflow_runs']):
            if run['conclusion'] != 'success' or datetime.fromisoformat(run['updated_at'].replace('Z', '+00:00')) < cutoff:
                continue
            try:
                ready.choose([run], audits)
            except ValueError:
                skipped.append(run['id'])
                continue
            artifacts = [item for page in api(f'repos/{args.repository}/actions/runs/{run["id"]}/artifacts?per_page=100')
                         for item in page['artifacts'] if item['name'] == 'published-manifests' and not item['expired']]
            if not artifacts:
                skipped.append(run['id'])
                continue
            if len(artifacts) != 1:
                raise ValueError('Ambiguous publication evidence')
            sp.run(['git', 'merge-base', '--is-ancestor', run['head_sha'], 'origin/main'], check=True)
            dest = work / str(run['id'])
            sp.run(['gh', 'run', 'download', str(run['id']), '--repo', args.repository,
                    '--name', 'published-manifests', '--dir', str(dest)], check=True)
            evidence = dest / 'published-manifests.json'
            if not evidence.is_file():
                # Older pipelines uploaded text summaries, not a deletion contract.
                skipped.append(run['id'])
                continue
            publications.append({'run_id': run['id'], 'published_at': run['updated_at'],
                                 'rows': json.loads(evidence.read_text(encoding='utf-8'))})
        if latest['publication_run'] not in {item['run_id'] for item in publications}:
            raise ValueError('Current publication evidence was not collected')
        release = work / 'original'
        release.mkdir()
        sp.run(['gh', 'release', 'download', 'v' + version, '--repo', args.repository,
                '--pattern', 'release-evidence.tar.gz', '--dir', str(release)], check=True)
        source = sp.check_output(['git', 'rev-parse', 'v' + version + '^{commit}'], text=True).strip()
        ids = original_ids(release / 'release-evidence.tar.gz', version, source)
    result = {'current': current, 'publications': publications, 'original_image_ids': ids,
              'publication_run': latest['publication_run'], 'skipped_runs_without_evidence': skipped}
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f'Collected {len(publications)} publications; {len(skipped)} runs have no usable evidence and cannot authorize deletion.')


if __name__ == '__main__':
    main()
