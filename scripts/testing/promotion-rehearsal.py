#!/usr/bin/env python3
"""Exercise archive identity, digest promotion and tag-only cleanup locally."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess as sp
import sys
import tarfile
import tempfile
import time
import uuid
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/release'))
from registry_tools import ARCHES, VARIANTS, Client, prepare_archive, promote, sha256

spec = importlib.util.spec_from_file_location('tidy', ROOT / 'scripts/release/tidy-release-tags.py')
tidy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tidy)
SOURCE = '1' * 40


def fixture(directory, variant, arch):
    directory.mkdir()
    layer = io.BytesIO()
    with tarfile.open(fileobj=layer, mode='w') as archive:
        content = (variant + '/' + arch + '\n').encode()
        item = tarfile.TarInfo('fixture.txt')
        item.size = len(content)
        archive.addfile(item, io.BytesIO(content))
    labels = {'org.opencontainers.image.version': '2.2.0' + ('-edge' if variant == 'edge' else ''),
              'org.opencontainers.image.revision': SOURCE}
    config = json.dumps({'architecture': arch, 'os': 'linux', 'config': {'Labels': labels},
                         'rootfs': {'type': 'layers', 'diff_ids': ['sha256:' + hashlib.sha256(layer.getvalue()).hexdigest()]}}).encode()
    config_id = hashlib.sha256(config).hexdigest()
    members = {config_id + '.json': config, 'layer/layer.tar': layer.getvalue(),
               'manifest.json': json.dumps([{'Config': config_id + '.json',
                   'RepoTags': [f'relay-candidate:{variant}-{arch}'], 'Layers': ['layer/layer.tar']}]).encode()}
    with tarfile.open(directory / 'image.tar', 'w') as archive:
        for name, data in members.items():
            item = tarfile.TarInfo(name)
            item.size = len(data)
            archive.addfile(item, io.BytesIO(data))
    (directory / 'image.tar.sha256').write_text(sha256(directory / 'image.tar') + '  image.tar\n')
    (directory / 'image.json').write_text(json.dumps([{'Id': 'sha256:' + config_id, 'Os': 'linux',
                                                       'Architecture': arch, 'Config': {'Labels': labels}}]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--registry', help='Reuse an explicitly supplied localhost fixture registry')
    args = parser.parse_args()
    name = 'relay-promotion-' + uuid.uuid4().hex[:10]
    try:
        if args.registry:
            host = args.registry
            if not host.startswith('localhost:'):
                raise ValueError('Rehearsal registry must be localhost')
        else:
            sp.run(['docker', 'run', '--detach', '--name', name, '--publish', '127.0.0.1::5000',
                    '--env', 'REGISTRY_STORAGE_DELETE_ENABLED=true',
                    'registry:3@sha256:ddf754342cfc8acc51a56d5d0ab6af06826461864460636d8bd5c546dab2a7b8'], check=True)
            port = sp.check_output(['docker', 'port', name, '5000/tcp'], text=True).strip().rsplit(':', 1)[1]
            host = 'localhost:' + port
        with tempfile.TemporaryDirectory(prefix='relay-registry-rehearsal-') as work:
            work = Path(work)
            client = Client(work, f'reg={host},tls=disabled')
            registry = host + '/' + name
            for attempt in range(20):
                try:
                    with urllib.request.urlopen('http://' + host + '/v2/', timeout=2):
                        break
                except OSError:
                    if attempt == 19:
                        raise
                    time.sleep(1)
            prepared = []
            for variant in VARIANTS:
                for arch in ARCHES:
                    directory = work / f'candidate-input-{variant}-{arch}'
                    fixture(directory, variant, arch)
                    prepared.append(prepare_archive(client, directory, variant, arch, '2.2.0', SOURCE))
            rows = promote(client, prepared, [registry], '2.2.0', work / 'published.json')
            assert set(client.run('tag', 'ls', registry).splitlines()) == {'2.2.0', 'latest', 'edge'}
            # Add exactly the legacy clutter, plus an old rollback alias.
            client.run('image', 'copy', registry + ':2.2.0', registry + ':2.1.0')
            client.run('image', 'copy', registry + ':edge', registry + ':2.2.0-edge')
            for item in prepared:
                client.run('image', 'copy', registry + '@' + item['digest'],
                           registry + f':validated-{SOURCE[:12]}-123-1-{item["variant"]}-{item["arch"]}')
            tidy.tidy(client, registry, '2.2.0', SOURCE, False, work / 'plan.json')
            assert len(client.run('tag', 'ls', registry).splitlines()) == 9
            report = tidy.tidy(client, registry, '2.2.0', SOURCE, True, work / 'applied.json')
            assert report['applied'] and len(report['targets']) == 5
            assert set(client.run('tag', 'ls', registry).splitlines()) == {'2.1.0', '2.2.0', 'latest', 'edge'}
            for row in rows:
                for arch, digest in row['architectures'].items():
                    assert client.manifest(registry + '@' + digest)['config']['digest'] == row['image_ids'][arch]
                    config = json.loads(client.run('blob', 'get', registry, row['image_ids'][arch]))
                    assert config['architecture'] == arch
            again = tidy.tidy(client, registry, '2.2.0', SOURCE, True, work / 'again.json')
            assert not again['targets']
            print('PASS: four exact archive identities; digest-only publication; three public tags;')
            print('      five tag-only removals; retained architecture/rollback manifests; idempotent cleanup.')
    finally:
        if not args.registry:
            sp.run(['docker', 'rm', '--force', '--volumes', name], check=False, stdout=sp.DEVNULL)


if __name__ == '__main__':
    main()
