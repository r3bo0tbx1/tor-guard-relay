"""Promote verified archives by digest and preserve registry-specific public tags."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess as sp

ARCHES = ('amd64', 'arm64')
VARIANTS = ('stable', 'edge')


class Client:
    def __init__(self, cwd=None, host=None):
        self.cwd = cwd
        self.executable = os.environ.get('REGCTL', 'regctl')
        self.options = ['--host', host] if host else []

    def run(self, *args):
        return sp.check_output([self.executable, *self.options, *args], cwd=self.cwd,
                               text=True, stderr=sp.PIPE).strip()

    def manifest(self, reference):
        return json.loads(self.run('manifest', 'get', reference, '--format', 'raw-body'))


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def public_tags(registry, version, variant):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or variant not in VARIANTS:
        raise ValueError('Expected a release version and supported variant')
    if variant == 'stable':
        return [version, 'latest']
    return [version + '-edge', 'edge'] if registry.startswith('ghcr.io/') else ['edge']


def architecture_digests(manifest):
    entries = manifest.get('manifests', [])
    result = {}
    if len(entries) != len(ARCHES):
        raise ValueError('Expected exactly two released architecture manifests')
    for entry in entries:
        platform = entry.get('platform', {})
        arch = platform.get('architecture')
        digest = entry.get('digest', '')
        if (platform.get('os') != 'linux' or arch not in ARCHES or arch in result
                or not re.fullmatch(r'sha256:[0-9a-f]{64}', digest)):
            raise ValueError('Invalid or duplicate released architecture')
        result[arch] = digest
    return result


def prepare_archive(client, directory, variant, arch, version, source):
    directory = Path(directory).resolve()
    archive = directory / 'image.tar'
    checksum = (directory / 'image.tar.sha256').read_text().split()
    if len(checksum) != 2 or checksum[1] != 'image.tar' or sha256(archive) != checksum[0]:
        raise ValueError('Candidate archive checksum mismatch')
    image, = json.loads((directory / 'image.json').read_text())
    labels = image.get('Config', {}).get('Labels', {})
    expected_version = version + ('-edge' if variant == 'edge' else '')
    if (image.get('Architecture') != arch or image.get('Os') != 'linux'
            or labels.get('org.opencontainers.image.version') != expected_version
            or labels.get('org.opencontainers.image.revision') != source):
        raise ValueError('Candidate source, version or architecture does not match')
    local = f'ocidir://candidate-{variant}-{arch}:local'
    client.run('image', 'import', local, str(archive), '--name', f'relay-candidate:{variant}-{arch}')
    digest = client.run('image', 'digest', local, '--platform', f'linux/{arch}')
    local = local.split(':local')[0] + '@' + digest
    manifest = client.manifest(local)
    if manifest.get('config', {}).get('digest') != image['Id']:
        raise ValueError('Imported image identity differs from the scanned candidate')
    return {'variant': variant, 'arch': arch, 'local': local, 'digest': digest, 'image_id': image['Id']}


def promote(client, prepared, registries, version, output):
    # Reject an incomplete candidate set before publishing either variant.
    for variant in VARIANTS:
        candidates = [item for item in prepared if item['variant'] == variant]
        if len(candidates) != 2 or {item['arch'] for item in candidates} != set(ARCHES):
            raise ValueError('Promotion requires both verified architectures')
    for registry in registries:
        public_tags(registry, version, 'stable')
    evidence = []
    for registry in registries:
        for variant in VARIANTS:
            candidates = [item for item in prepared if item['variant'] == variant]
            digests = {}
            for item in candidates:
                target = registry + '@' + item['digest']
                # A digest destination never creates a public architecture/staging tag.
                client.run('image', 'copy', item['local'], target)
                if client.manifest(target)['config']['digest'] != item['image_id']:
                    raise ValueError('Published image identity differs from the scanned candidate')
                digests[item['arch']] = item['digest']
            tags = public_tags(registry, version, variant)
            first = registry + ':' + tags[0]
            command = ['index', 'create', first]
            for arch in ARCHES:
                command.extend(['--ref', registry + '@' + digests[arch]])
            client.run(*command)
            if architecture_digests(client.manifest(first)) != digests:
                raise ValueError('Published index differs from the verified architecture set')
            index_digest = client.run('image', 'digest', first)
            for tag in tags[1:]:
                client.run('image', 'copy', registry + '@' + index_digest, registry + ':' + tag)
                if client.run('image', 'digest', registry + ':' + tag) != index_digest:
                    raise ValueError('Published alias differs from its released index')
            evidence.append({'registry': registry, 'variant': variant, 'tags': tags,
                             'index_digest': index_digest, 'architectures': digests,
                             'image_ids': {item['arch']: item['image_id'] for item in candidates}})
    Path(output).write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    return evidence
