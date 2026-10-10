#!/usr/bin/env python3
"""Remove only a release's unwanted tags while retaining its image manifests."""
import argparse
import json
from pathlib import Path
import re
import subprocess as sp

from registry_tools import Client, architecture_digests, public_tags


def snapshot(client, registry, tags):
    roots, manifests = {}, {}

    def visit(digest):
        if digest in manifests:
            return
        manifest = client.manifest(registry + '@' + digest)
        manifests[digest] = manifest
        for child in manifest.get('manifests', []):
            visit(child['digest'])

    for tag in tags:
        digest = client.run('image', 'digest', registry + ':' + tag)
        roots[tag] = digest
        visit(digest)
    return {'roots': roots, 'manifests': manifests}


def verify_snapshot(client, registry, before):
    for tag, digest in before['roots'].items():
        if client.run('image', 'digest', registry + ':' + tag) != digest:
            raise ValueError('Protected registry tag changed: ' + tag)
    for digest, manifest in before['manifests'].items():
        if client.manifest(registry + '@' + digest) != manifest:
            raise ValueError('Protected image manifest changed: ' + digest)


def delete_dummy_version(client, registry, tag, original):
    # GHCR does not always expose registry manifest deletion. Only remove the
    # unique replacement made by regctl; never delete the released image version.
    dummy = client.run('image', 'digest', registry + ':' + tag)
    if dummy == original:
        raise ValueError('Tag removal did not replace the original image; refusing package deletion')
    manifest = client.manifest(registry + '@' + dummy)
    config = json.loads(client.run('blob', 'get', registry, manifest['config']['digest']))
    if config.get('config', {}).get('Labels', {}).get('delete-tag') != tag:
        raise ValueError('Replacement image is not the expected tag-removal placeholder')
    owner = registry.split('/')[1]
    pages = json.loads(sp.check_output(['gh', 'api', '--paginate', '--slurp',
                                     f'users/{owner}/packages/container/onion-relay/versions?per_page=100'], text=True))
    matches = [item for page in pages for item in page if item['name'] == dummy]
    if len(matches) != 1 or matches[0]['metadata']['container']['tags'] != [tag]:
        raise ValueError('Placeholder package version is missing or has other tags')
    sp.run(['gh', 'api', '--method', 'DELETE',
            f'users/{owner}/packages/container/onion-relay/versions/{matches[0]["id"]}'], check=True)


def tidy(client, registry, version, source, apply, output):
    if not re.fullmatch(r'[0-9a-f]{40}', source):
        raise ValueError('Expected the complete released source SHA')
    public_tags(registry, version, 'stable')
    tags = client.run('tag', 'ls', registry).splitlines()
    pattern = re.compile(r'validated-' + source[:12] + r'-\d+-\d+-(stable|edge)-(amd64|arm64)')
    targets = [tag for tag in tags if pattern.fullmatch(tag)]
    if not registry.startswith('ghcr.io/') and version + '-edge' in tags:
        targets.append(version + '-edge')
    protected = [tag for tag in tags if tag not in targets]
    before = snapshot(client, registry, protected)
    for variant in ('stable', 'edge'):
        expected_tags = public_tags(registry, version, variant)
        roots = {before['roots'].get(tag) for tag in expected_tags}
        if None in roots or len(roots) != 1:
            raise ValueError('Release version and aliases do not match')
        digest, = roots
        architecture_digests(before['manifests'][digest])
    originals = {}
    for tag in targets:
        reference = registry + ':' + tag
        digest = client.run('image', 'digest', reference)
        if digest not in before['manifests']:
            raise ValueError('Cleanup target is not referenced by a retained release: ' + tag)
        manifest = before['manifests'][digest]
        for image_digest in (architecture_digests(manifest).values() if 'manifests' in manifest else [digest]):
            image = before['manifests'][image_digest]
            config = json.loads(client.run('blob', 'get', registry, image['config']['digest']))
            labels = config.get('config', {}).get('Labels', {})
            if (labels.get('org.opencontainers.image.revision') != source
                    or labels.get('org.opencontainers.image.version') not in (version, version + '-edge')):
                raise ValueError('Cleanup target is not from the expected release')
        originals[tag] = digest
    report = {'registry': registry, 'targets': originals, 'protected': before, 'applied': False}
    Path(output).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    if not apply:
        return report
    # Recheck the entire retained graph immediately before changing any tag.
    verify_snapshot(client, registry, before)
    for tag, original in originals.items():
        if client.run('image', 'digest', registry + ':' + tag) != original:
            raise ValueError('Cleanup target changed after planning')
        try:
            client.run('tag', 'delete', registry + ':' + tag)
        except sp.CalledProcessError:
            if not registry.startswith('ghcr.io/'):
                raise
            delete_dummy_version(client, registry, tag, original)
        verify_snapshot(client, registry, before)
    remaining = client.run('tag', 'ls', registry).splitlines()
    if any(tag in remaining for tag in targets):
        raise ValueError('Registry still lists a cleanup target')
    report['applied'] = True
    Path(output).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--registry', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    report = tidy(Client(), args.registry, args.version, args.source, args.apply, args.output)
    print('Removed' if report['applied'] else 'Planned', ', '.join(report['targets']) or '(nothing to remove)')


if __name__ == '__main__':
    try:
        main()
    except sp.CalledProcessError as error:
        raise SystemExit(error.stderr or str(error)) from error
