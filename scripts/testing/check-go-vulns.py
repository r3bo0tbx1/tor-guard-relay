#!/usr/bin/env python3
"""Analyze the pinned source/lock with the actual builder, without runtime tools."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess as sp
import tempfile
import uuid

from security_policy import assess_go

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('pins', ROOT / 'scripts/testing/check-dependency-pins.py')
pins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pins)


def native_path(path, cli):
    path = str(Path(path).resolve())
    if cli.endswith('.exe') and os.environ.get('WSL_DISTRO_NAME'):
        return sp.check_output(['wslpath', '-w', path], text=True).strip()
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=['amd64', 'arm64'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--image', help='Also prove the analyzed builder binary matches this candidate')
    parser.add_argument('--builder', help='Optional existing buildx builder')
    parser.add_argument('--source-root', type=Path, default=ROOT,
                        help='Released source to analyze when this checker comes from newer policy')
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    dependency = pins.inspect_pins(source_root)
    version = json.loads((ROOT / 'build/security-tools.json').read_text())['govulncheck']
    if not re.fullmatch(r'v\d+\.\d+\.\d+', version):
        raise ValueError('Scanner must have an explicit release version')
    cli = (os.environ.get('DOCKER') or (shutil.which('docker.exe') if os.environ.get('WSL_DISTRO_NAME') else None)
           or shutil.which('docker'))
    if not cli:
        raise RuntimeError('Docker is required')
    host_arch = sp.check_output([cli, 'version', '--format', '{{.Server.Arch}}'], text=True).strip()
    if host_arch not in ('amd64', 'arm64'):
        raise ValueError('Unsupported Docker build-host architecture')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    builder_image = 'relay-go-audit:' + uuid.uuid4().hex
    containers = []
    metadata = {**dependency, 'arch': args.arch, 'govulncheck_version': version}
    metadata['source_revision'] = sp.check_output(['git', '-C', str(source_root), 'rev-parse', 'HEAD'], text=True).strip()
    metadata['policy_revision'] = sp.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    metadata['policy_sha256'] = hashlib.sha256((ROOT / 'scripts/testing/security_policy.py').read_bytes()).hexdigest()

    def copy_binary(image, destination, arch):
        container = sp.check_output([cli, 'create', '--platform', 'linux/' + arch, image], text=True).strip()
        containers.append(container)
        sp.run([cli, 'cp', container + ':/usr/bin/lyrebird', native_path(destination, cli)], check=True)
        return hashlib.sha256(destination.read_bytes()).hexdigest()

    try:
        command = [cli, 'buildx', 'build']
        if args.builder:
            command += ['--builder', args.builder]
        command += ['--load', '--provenance=false', '--sbom=false', '--platform', 'linux/' + host_arch,
                    '--target', 'builder', '--build-arg', 'TARGETOS=linux', '--build-arg', 'TARGETARCH=' + args.arch,
                    '--tag', builder_image, '--file', native_path(source_root / 'Dockerfile', cli), native_path(source_root, cli)]
        sp.run(command, check=True)
        if args.image:
            inspected = json.loads(sp.check_output([cli, 'image', 'inspect', args.image]))[0]
            if inspected['Architecture'] != args.arch:
                raise ValueError('Candidate architecture differs from scan target')
            labels = inspected['Config'].get('Labels') or {}
            if labels.get('org.torproject.lyrebird.revision') != dependency['lyrebird_revision']:
                raise ValueError('Candidate Lyrebird source label differs from checked source')
            with tempfile.TemporaryDirectory(dir=args.output.parent) as directory:
                directory = Path(directory)
                expected = copy_binary(builder_image, directory / 'builder-lyrebird', host_arch)
                actual = copy_binary(args.image, directory / 'candidate-lyrebird', args.arch)
                if actual != expected:
                    raise ValueError('Candidate transport differs from analyzed builder source/lock/toolchain')
            metadata.update(image_id=inspected['Id'], lyrebird_binary_sha256=actual)
        shell = '''set -eu
test "$(git rev-parse HEAD)" = "$REVISION"
go mod verify >&2
GOBIN=/tmp/audit-bin go install "golang.org/x/vuln/cmd/govulncheck@$SCANNER_VERSION" >&2
CGO_ENABLED=0 GOOS=linux GOARCH="$SCAN_ARCH" GOFLAGS=-mod=readonly /tmp/audit-bin/govulncheck -format=json -scan=symbol ./cmd/lyrebird
'''
        with args.output.open('w', encoding='utf-8') as output:
            scanner_container = 'relay-go-scan-' + uuid.uuid4().hex
            containers.append(scanner_container)
            sp.run([cli, 'run', '--rm', '--name', scanner_container, '--memory=4g', '--entrypoint', 'sh',
                    '-e', 'REVISION=' + dependency['lyrebird_revision'], '-e', 'SCAN_ARCH=' + args.arch,
                    '-e', 'SCANNER_VERSION=' + version, builder_image, '-ec', shell], check=True, stdout=output, timeout=1200)
        summary = assess_go(args.output.read_text(encoding='utf-8'))
        metadata['assessment'] = summary
        args.output.with_suffix('.metadata.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(metadata, indent=2))
        return 0 if summary['passed'] else 1
    finally:
        for container in containers:
            sp.run([cli, 'rm', '-f', container], stdout=sp.DEVNULL, stderr=sp.DEVNULL)
        sp.run([cli, 'image', 'rm', builder_image], stdout=sp.DEVNULL, stderr=sp.DEVNULL)


if __name__ == '__main__':
    raise SystemExit(main())
