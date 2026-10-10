#!/usr/bin/env python3
"""Require a completed image publication and a later successful full audit."""
import argparse
import json
from pathlib import Path
import re
import subprocess as sp


def api(path):
    return json.loads(sp.check_output(['gh', 'api', path], text=True, encoding='utf-8'))


def choose(releases, audits):
    if any(run['status'] in ('queued', 'in_progress', 'waiting', 'requested', 'pending') for run in releases):
        raise ValueError('Wait for active release runs before registry retirement')
    completed = [run for run in releases if run['status'] == 'completed' and run['conclusion'] == 'success']
    if not completed:
        raise ValueError('A successful publication is required')
    release = completed[0]
    matching = [run for run in audits if run['event'] == 'workflow_run'
                and run['status'] == 'completed' and run['conclusion'] == 'success'
                and run['head_sha'] == release['head_sha']
                and run['created_at'] >= release['updated_at']]
    if not matching:
        raise ValueError('Wait for the successful full audit following the latest publication')
    return release, matching[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9-]+/tor-guard-relay', args.repository):
        raise ValueError('Expected the tor-guard-relay repository')
    prefix = f'repos/{args.repository}/actions/workflows/'
    release, audit = choose(api(prefix + 'release.yml/runs?per_page=30')['workflow_runs'],
                            api(prefix + 'security.yml/runs?per_page=100')['workflow_runs'])
    sp.run(['git', 'merge-base', '--is-ancestor', release['head_sha'], 'origin/main'], check=True)
    result = {'publication_run': release['id'], 'publication_source': release['head_sha'],
              'audit_run': audit['id'], 'publication_completed': release['updated_at']}
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
    # Missing/expired evidence fails before any deletion.
    sp.run(['gh', 'run', 'download', str(release['id']), '--repo', args.repository,
            '--name', 'published-manifests', '--dir', 'retention-publication'], check=True)
    print(f"Publication {release['id']} and audit {audit['id']} passed.")


if __name__ == '__main__':
    main()
