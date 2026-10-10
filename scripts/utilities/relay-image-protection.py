#!/usr/bin/env python3
"""Read Docker image identities without reading relay ENV, torrc, keys or logs."""
import argparse
from datetime import datetime, timezone
import json
import re
import subprocess as sp


def collect(call, owner):
    containers = call('ps', '-aq').split()
    image_ids, digests = set(), set()
    count = 0
    for identity in containers:
        # A narrow format avoids collecting container ENV/mounts/relay keys.
        container = json.loads(call('inspect', '--format', '{{json .Image}}', identity))
        # Read just the fields needed for image protection.
        fields = json.loads(call('image', 'inspect', '--format',
                                 '{"id":{{json .Id}},"tags":{{json .RepoTags}},"digests":{{json .RepoDigests}},"source":{{with (index .Config "Labels")}}{{json (index . "org.opencontainers.image.source")}}{{else}}null{{end}}}', container))
        refs = (fields['tags'] or []) + (fields['digests'] or [])
        project = fields['source'] == f'https://github.com/{owner}/tor-guard-relay'
        belongs = lambda ref: re.fullmatch(r'(?:docker\.io/)?' + re.escape(owner) + r'/onion-relay(?::[^@]+|@sha256:[0-9a-f]{64})', ref) or re.fullmatch(r'ghcr\.io/' + re.escape(owner) + r'/onion-relay(?::[^@]+|@sha256:[0-9a-f]{64})', ref)
        if not project and not any(belongs(ref) for ref in refs):
            continue
        if not re.fullmatch(r'sha256:[0-9a-f]{64}', fields['id']):
            raise ValueError('Relay image has no valid Docker image identity')
        count += 1
        image_ids.add(fields['id'])
        for ref in fields['digests'] or []:
            if belongs(ref) and '@' in ref:
                digests.add(ref.rsplit('@', 1)[1])
    return {'observed_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
            'scope': 'One Docker engine; running AND stopped containers. This is not a fleet coverage assertion.',
            'relay_containers': count, 'protected_image_ids': sorted(image_ids),
            'protected_digests': sorted(digests), 'deployment_review_complete': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--docker', default='docker', help='Docker CLI executable; docker.exe also works from WSL')
    parser.add_argument('--context', help='An existing Docker context to inspect')
    parser.add_argument('--owner', default='r3bo0tbx1')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9-]+', args.owner):
        raise ValueError('Invalid relay repository owner')
    command = [args.docker] + (['--context', args.context] if args.context else [])

    def call(*parts):
        return sp.check_output([*command, *parts], text=True, encoding='utf-8', timeout=30).strip()

    print(json.dumps(collect(call, args.owner.lower()), indent=2))


if __name__ == '__main__':
    main()
