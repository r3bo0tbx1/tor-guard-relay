#!/usr/bin/env python3
"""Plan and remove explicitly retired image versions, preserving retained graphs."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess as sp

from registry_tools import Client, architecture_digests, is_ghcr, public_tags

spec = importlib.util.spec_from_file_location('tag_tidy', Path(__file__).with_name('tidy-release-tags.py'))
tidy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tidy)
DIGEST = re.compile(r'sha256:[0-9a-f]{64}')


def api(*args):
    return json.loads(sp.check_output(['gh', 'api', *args], text=True, encoding='utf-8'))


class Packages:
    def __init__(self, registry):
        if not is_ghcr(registry) or not re.fullmatch(r'ghcr\.io/[a-zA-Z0-9-]+/onion-relay', registry):
            raise ValueError('Expected the exact GHCR onion-relay package')
        self.path = f'users/{registry.split("/")[1]}/packages/container/onion-relay/versions'

    def versions(self):
        return [item for page in api('--paginate', '--slurp', self.path + '?per_page=100') for item in page]

    def get(self, identity):
        return api(f'{self.path}/{identity}')

    def delete(self, identity):
        sp.run(['gh', 'api', '--method', 'DELETE', f'{self.path}/{identity}'], check=True)


class Graph:
    def __init__(self, client, registry):
        self.client, self.registry = client, registry
        self.manifests, self.configs = {}, {}
        self.package_digests = None
        self.missing = set()

    def visit(self, digest):
        if not DIGEST.fullmatch(digest):
            raise ValueError('Invalid manifest digest')
        if digest in self.manifests:
            return
        try:
            manifest = self.client.manifest(self.registry + '@' + digest)
        except sp.CalledProcessError as error:
            # Historical indexes may already reference deleted children. Only
            # tolerate an explicit manifest 404 for an unlisted child; any
            # retained graph containing it is rejected below before deletion.
            if (self.package_digests is None or digest in self.package_digests
                    or 'http 404' not in str(error.stderr) or 'MANIFEST_UNKNOWN' not in str(error.stderr)):
                raise
            self.missing.add(digest)
            self.manifests[digest] = {'_missing': True}
            return
        self.manifests[digest] = manifest
        for child in self.children(manifest):
            self.visit(child)
        if manifest.get('config'):
            config_digest = manifest['config']['digest']
            self.configs[config_digest] = json.loads(self.client.run('blob', 'get', self.registry, config_digest))

    @staticmethod
    def children(manifest):
        children = [item['digest'] for item in manifest.get('manifests', [])]
        if manifest.get('subject'):
            children.append(manifest['subject']['digest'])
        return children

    def closure(self, roots):
        result = set()

        def visit(digest):
            if digest in result:
                return
            result.add(digest)
            for child in self.children(self.manifests[digest]):
                visit(child)

        for root in roots:
            visit(root)
        return result

    def versions(self, root):
        found = set()
        for digest in self.closure([root]):
            manifest = self.manifests[digest]
            if digest in self.missing:
                continue
            if 'manifests' in manifest:
                continue
            config = self.configs.get(manifest.get('config', {}).get('digest'), {})
            version = config.get('config', {}).get('Labels', {}).get('org.opencontainers.image.version')
            if version:
                found.add(version.removeprefix('v'))
            elif not (manifest.get('layers') and all(
                    layer.get('mediaType') == 'application/vnd.in-toto+json' for layer in manifest['layers'])):
                found.add('?')
        return found


def package_identity(item):
    return {'id': item['id'], 'digest': item['name'], 'tags': sorted(item['metadata']['container']['tags'])}


def plan_registry(client, registry, keep, retired, packages=None):
    if not re.fullmatch(r'\d+\.\d+\.\d+', keep) or not retired:
        raise ValueError('Expected current and explicitly retired release versions')
    for version in retired:
        if (not re.fullmatch(r'\d+\.\d+\.\d+', version)
                or tuple(map(int, version.split('.'))) >= tuple(map(int, keep.split('.')))):
            raise ValueError('Only older explicitly retired versions may be removed')
    old_labels = {label for version in retired for label in (version, version + '-edge')}
    tags = client.run('tag', 'ls', registry).splitlines()
    graph = Graph(client, registry)
    roots = {}
    for tag in tags:
        roots[tag] = client.run('image', 'digest', registry + ':' + tag)
        graph.visit(roots[tag])
    targets = {tag: digest for tag, digest in roots.items() if tag in old_labels}
    protected_roots = {tag: digest for tag, digest in roots.items() if tag not in targets}
    for variant in ('stable', 'edge'):
        expected_tags = public_tags(registry, keep, variant)
        expected = {protected_roots.get(tag) for tag in expected_tags}
        if None in expected or len(expected) != 1:
            raise ValueError('Current version and aliases must match before cleanup')
        digest, = expected
        for arch, image_digest in architecture_digests(graph.manifests[digest]).items():
            manifest = graph.manifests[image_digest]
            config = graph.configs[manifest['config']['digest']]
            if config.get('architecture') != arch or graph.versions(image_digest) != {keep + ('-edge' if variant == 'edge' else '')}:
                raise ValueError('Current architecture/version identity does not match')

    entries = [] if packages is None else packages.versions()
    graph.package_digests = {item['name'] for item in entries} if packages else None
    by_digest = {}
    identities = set()
    for item in entries:
        identity = package_identity(item)
        if (not isinstance(identity['id'], int) or identity['id'] <= 0
                or identity['id'] in identities or identity['digest'] in by_digest):
            raise ValueError('Invalid or duplicate package version identity')
        identities.add(identity['id'])
        by_digest[identity['digest']] = identity
        graph.visit(identity['digest'])
        for tag in identity['tags']:
            if roots.get(tag) != identity['digest']:
                raise ValueError('Package metadata and registry tags disagree')
    if packages and any(digest not in by_digest for digest in roots.values()):
        raise ValueError('Package inventory is incomplete')

    # Include older untagged indexes and their architecture/attestation children.
    retired_roots = [digest for digest in by_digest
                     if graph.versions(digest) and graph.versions(digest) <= old_labels]
    candidates = graph.closure(retired_roots)
    retained_roots = [digest for digest in by_digest if digest not in candidates]
    retained_roots.extend(protected_roots.values())
    protected = graph.closure(retained_roots)
    if protected.intersection(graph.missing):
        raise ValueError('A retained package graph contains a missing manifest; refusing cleanup')
    deletions = [identity for digest, identity in by_digest.items()
                 if digest in candidates and digest not in protected]
    for item in deletions:
        if any(tag not in targets for tag in item['tags']):
            raise ValueError('Package deletion would remove a retained tag')
    # Delete parents before children. Shared retained children are never targets.
    deletions.sort(key=lambda item: (-len(graph.closure([item['digest']])), item['id']))
    deleted_digests = {item['digest'] for item in deletions}
    return {'registry': registry, 'keep_version': keep, 'retired_versions': sorted(retired),
            'tag_targets': targets, 'tag_only': {tag: digest for tag, digest in targets.items()
                                                if digest not in deleted_digests},
            'package_targets': deletions,
            'missing_retired_references': sorted(graph.missing),
            'protected': {'roots': protected_roots,
                          'manifests': {digest: graph.manifests[digest] for digest in sorted(protected)}},
            'protected_configs': {manifest['config']['digest']: graph.configs[manifest['config']['digest']]
                                  for digest, manifest in graph.manifests.items()
                                  if digest in protected and manifest.get('config')},
            'applied': False, 'removed_tags': [], 'removed_packages': []}


def verify(client, report, heads_only=False):
    before = report['protected']
    if heads_only:
        for tag, digest in before['roots'].items():
            if client.run('image', 'digest', report['registry'] + ':' + tag) != digest:
                raise ValueError('Protected registry tag changed: ' + tag)
        return
    tidy.verify_snapshot(client, report['registry'], before)
    for digest, config in report['protected_configs'].items():
        actual = json.loads(client.run('blob', 'get', report['registry'], digest))
        if actual != config:
            raise ValueError('Protected image config changed')


def apply_registry(client, report, packages=None, save=lambda: None):
    verify(client, report)
    registry = report['registry']
    protected = report['protected']['manifests']
    for item in report['package_targets']:
        if item['digest'] in protected or any(tag in report['protected']['roots'] for tag in item['tags']):
            raise ValueError('Package target overlaps protected images')
        if packages is None or package_identity(packages.get(item['id'])) != item:
            raise ValueError('Package identity or tags changed after planning')
        verify(client, report, heads_only=True)
        packages.delete(item['id'])
        report['removed_packages'].append(item)
        save()
        verify(client, report, heads_only=True)
    for tag, original in report['tag_only'].items():
        if tag in report['protected']['roots'] or client.run('image', 'digest', registry + ':' + tag) != original:
            raise ValueError('Tag changed after planning')
        verify(client, report, heads_only=True)
        try:
            client.run('tag', 'delete', registry + ':' + tag)
        except sp.CalledProcessError:
            if not is_ghcr(registry):
                raise
            tidy.delete_dummy_version(client, registry, tag, original)
        report['removed_tags'].append(tag)
        save()
        verify(client, report, heads_only=True)
    remaining_tags = set(client.run('tag', 'ls', registry).splitlines())
    if remaining_tags.intersection(report['tag_targets']):
        raise ValueError('Retired tags remain after cleanup')
    if packages:
        remaining = {item['id'] for item in packages.versions()}
        if remaining.intersection(item['id'] for item in report['package_targets']):
            raise ValueError('Retired package versions remain after cleanup')
    verify(client, report)
    report['applied'] = True
    save()


def release_snapshot(repository):
    pages = api('--paginate', '--slurp', f'repos/{repository}/releases?per_page=100')
    return [{'id': item['id'], 'tag': item['tag_name'], 'name': item['name'], 'body': item['body'],
             'draft': item['draft'], 'prerelease': item['prerelease'],
             'assets': [{'id': asset['id'], 'name': asset['name'], 'size': asset['size'],
                         'digest': asset.get('digest')} for asset in item['assets']]}
            for page in pages for item in page]


def verify_publication(report, evidence):
    rows = [item for item in evidence if item['registry'] == report['registry']]
    if len(rows) != 2 or {item['variant'] for item in rows} != {'stable', 'edge'}:
        raise ValueError('Expected publication evidence for both variants in each registry')
    for item in rows:
        if item['tags'] != public_tags(report['registry'], report['keep_version'], item['variant']):
            raise ValueError('Publication tags do not match current version')
        for tag in item['tags']:
            if report['protected']['roots'].get(tag) != item['index_digest']:
                raise ValueError('Current registry differs from validated publication evidence')
        manifest = report['protected']['manifests'][item['index_digest']]
        if architecture_digests(manifest) != item['architectures']:
            raise ValueError('Current architectures differ from publication evidence')
        for arch, digest in item['architectures'].items():
            if report['protected']['manifests'][digest]['config']['digest'] != item['image_ids'][arch]:
                raise ValueError('Current image identity differs from publication evidence')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owner', required=True)
    parser.add_argument('--keep-version', required=True)
    parser.add_argument('--remove-version', action='append', required=True)
    parser.add_argument('--publication-evidence', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9-]+', args.owner):
        raise ValueError('Invalid repository owner')
    repository = args.owner + '/tor-guard-relay'
    releases = release_snapshot(repository)
    evidence = json.loads(args.publication_evidence.read_text())
    client = Client()
    registries = [args.owner + '/onion-relay', 'ghcr.io/' + args.owner + '/onion-relay']
    report = {'releases_before': releases, 'registries': [], 'completed': False}

    def save():
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')

    # Complete and retain both plans before any registry mutation.
    for registry in registries:
        packages = Packages(registry) if is_ghcr(registry) else None
        planned = plan_registry(client, registry, args.keep_version, args.remove_version, packages)
        verify_publication(planned, evidence)
        report['registries'].append(planned)
        save()
        print(f"Planned {registry}: {len(planned['tag_targets'])} tags, {len(planned['package_targets'])} retired package versions", flush=True)
    if args.apply:
        for planned in report['registries']:
            packages = Packages(planned['registry']) if is_ghcr(planned['registry']) else None
            apply_registry(client, planned, packages, save)
        report['releases_after'] = release_snapshot(repository)
        if report['releases_after'] != releases:
            raise ValueError('GitHub release records or assets changed during registry cleanup')
        report['completed'] = True
        save()
        print('Cleanup complete; protected images and GitHub release assets are unchanged.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except sp.CalledProcessError as error:
        raise SystemExit(error.stderr or str(error)) from error
