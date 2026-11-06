#!/usr/bin/env python3
"""Select an immutable main rebuild or reviewed release-tag source."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import re
import subprocess as sp

LOCK = 'build/tor/source.json'
spec = importlib.util.spec_from_file_location('tor_source',
    Path(__file__).resolve().parents[2] / 'build/tor/source.py')
tor_source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tor_source)


def select(root, event, ref_name, revision, source_tag='', publish=False, previous_revision=''):
    root = Path(root).resolve()

    def git(*args):
        return sp.check_output(['git', '-C', str(root), *args], text=True, encoding='utf-8').strip()

    if event not in ('push', 'schedule', 'workflow_dispatch'):
        raise ValueError('Unsupported release event')
    policy_sha = git('rev-parse', 'origin/main^{commit}')
    latest = next((tag for tag in git('tag', '--sort=-v:refname').splitlines()
                   if re.fullmatch(r'v\d+\.\d+\.\d+', tag)), '')
    tor_push = event == 'push' and ref_name == 'main'
    tag_push = event == 'push' and not tor_push
    main_rebuild = tor_push or event == 'schedule' or (event == 'workflow_dispatch' and not source_tag)
    tag = ref_name if tag_push else source_tag or latest
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('Expected an existing stable release tag vX.Y.Z')
    tag_sha = git('rev-parse', tag + '^{commit}')
    # Even a main rebuild must use a released, reviewed version namespace.
    git('merge-base', '--is-ancestor', tag_sha, 'origin/main')
    if main_rebuild:
        if ref_name != 'main' or not re.fullmatch(r'[0-9a-f]{40}', revision):
            raise ValueError('Main rebuilds require the main branch and its full commit SHA')
        sha = git('rev-parse', revision + '^{commit}')
        git('merge-base', '--is-ancestor', sha, 'origin/main')
        git('merge-base', '--is-ancestor', tag_sha, sha)
        readme = git('show', sha + ':README.md')
        marker = re.search(r'<!-- RELAY_VERSION -->v(\d+\.\d+\.\d+)<!-- /RELAY_VERSION -->', readme)
        if not marker or marker[1] != tag[1:]:
            raise ValueError('Main version must match the latest release; publish a new release tag for a version bump')
    else:
        sha = tag_sha
    build = True
    if tor_push:
        if not re.fullmatch(r'[0-9a-f]{40}', previous_revision):
            raise ValueError('A Tor pin push requires the previous main commit SHA')
        git('merge-base', '--is-ancestor', previous_revision, sha)
        before, after = [tor_source.validate_lock(json.loads(git('show', f'{commit}:{LOCK}')))
                         for commit in (previous_revision, sha)]
        build = tor_source.version_tuple(after['version']) > tor_source.version_tuple(before['version'])
        if not build:
            print('The Tor version did not advance. Skipping the automatic rebuild.')
    return {'build': str(build).lower(), 'sha': sha, 'policy_sha': policy_sha, 'version': tag[1:],
            'publish': str(build and (event in ('push', 'schedule') or publish)).lower(),
            'release': str(tag_push).lower(),
            'source_ref': 'main' if main_rebuild else tag}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--event', required=True)
    parser.add_argument('--ref-name', required=True)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--previous-revision', default='')
    parser.add_argument('--source-tag', default='')
    parser.add_argument('--publish', choices=('', 'false', 'true'), default='false')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    result = select(Path(__file__).resolve().parents[2], args.event, args.ref_name,
                    args.revision, args.source_tag, args.publish == 'true', args.previous_revision)
    result['build_date'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    with Path(args.output).open('a', encoding='utf-8', newline='\n') as stream:
        for key, value in result.items():
            stream.write(f'{key}={value}\n')
    print(f"Selected {result['source_ref']} at {result['sha']} for {result['version']}; publish={result['publish']}")


if __name__ == '__main__':
    main()
