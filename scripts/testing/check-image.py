#!/usr/bin/env python3
"""Check component floors with the policy's pinned, native Go inspector."""
import importlib.util
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess as sp
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('pins', ROOT / 'scripts/testing/check-dependency-pins.py')
pins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pins)


def check_tor_version(output, minimum):
    """Require an identifiable stable Tor version at the reviewed policy floor."""
    match = re.search(r'(?m)^Tor version (\d+\.\d+\.\d+\.\d+)\.?(?=\s|$)', output)
    if not match:
        raise ValueError('Expected a stable Tor version in --version output')
    version = match[1]
    if tuple(map(int, version.split('.'))) < tuple(map(int, minimum.split('.'))):
        raise ValueError(f'Tor {version} is below the required minimum {minimum}; upgrade the image')
    return version


def check_tor_source(output, source, expected):
    if source != expected:
        raise ValueError('Candidate Tor source provenance differs from the reviewed policy lock')
    if check_tor_version(output, expected['version']) != source['version']:
        raise ValueError('Candidate Tor binary version differs from its source provenance')


def run(cli, *args, **kwargs):
    return sp.run([cli, *args], check=True, stdout=sp.PIPE, **kwargs).stdout


def ensure_inspector(cli, image, platform):
    """Reuse an exact local pin, or retry only its fetch with a fixed budget."""
    inspected = sp.run([cli, 'image', 'inspect', '--format', '{{.Os}}/{{.Architecture}}', image],
                       stdout=sp.PIPE, stderr=sp.DEVNULL, text=True, timeout=30)
    if inspected.returncode == 0 and inspected.stdout.strip() == platform:
        return
    for attempt in range(1, 4):
        try:
            sp.run([cli, 'pull', '--platform', platform, image], check=True, timeout=120)
            return
        except (sp.CalledProcessError, sp.TimeoutExpired):
            if attempt == 3:
                raise
            delay = attempt * 10
            print(f'Go inspector fetch failed ({attempt}/3); retrying in {delay}s',
                  file=sys.stderr, flush=True)
            time.sleep(delay)


def inspect_transport(cli, binary):
    image = pins.inspect_pins(ROOT)['go_builder']
    arch = run(cli, 'version', '--format', '{{.Server.Arch}}').decode().strip()
    if arch not in ('amd64', 'arm64'):
        raise ValueError('Unsupported Docker inspection-host architecture')
    platform = 'linux/' + arch
    ensure_inspector(cli, image, platform)
    return run(cli, 'run', '-i', '--rm', '--pull=never', '--platform', platform,
               '--network', 'none', '--entrypoint', 'sh', image, '-ec',
               'cat > /tmp/lyrebird; go version -m /tmp/lyrebird', input=binary).decode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image')
    parser.add_argument('--tor-only', action='store_true', help='Check the current Tor floor without inspecting Lyrebird')
    parser.add_argument('--summary', type=Path, help='Append the Tor-only assessment to a job summary')
    args = parser.parse_args()
    if args.summary and not args.tor_only:
        parser.error('--summary requires --tor-only')
    cli = (os.environ.get('DOCKER') or (shutil.which('docker.exe') if os.environ.get('WSL_DISTRO_NAME') else None)
           or shutil.which('docker'))
    if not cli:
        raise RuntimeError('Docker is required')
    image = args.image
    arch = run(cli, 'image', 'inspect', '--format', '{{.Architecture}}', image).decode().strip()
    if arch not in ('amd64', 'arm64'):
        raise ValueError('Unsupported candidate architecture')
    command = ('run', '--rm', '--pull=never', '--platform', 'linux/' + arch, '--network', 'none')
    tor = run(cli, *command, '--entrypoint', 'tor', image, '--version').decode()
    minimum = pins.inspect_pins(ROOT)['tor_min_version']
    if args.tor_only:
        assessment = {'tor': tor.strip(), 'tor_min_version': minimum, 'passed': True}
        try:
            version = check_tor_version(tor, minimum)
            message = f'✅ Tor {version} meets the required minimum {minimum}.'
        except ValueError as error:
            assessment.update(passed=False, reason=str(error))
            message = '🚨 ' + str(error)
        print(json.dumps(assessment))
        if args.summary:
            with args.summary.open('a', encoding='utf-8', newline='\n') as output:
                output.write('\n## 🧅 Published Tor version policy\n\n' + message + '\n')
        if not assessment['passed']:
            raise SystemExit(1)
        return
    check_tor_version(tor, minimum)
    source = json.loads(run(cli, *command, '--entrypoint', 'cat', image, '/usr/share/tor/source.json'))
    expected_source = json.loads((ROOT / 'build/tor/source.json').read_text(encoding='utf-8'))
    check_tor_source(tor, source, expected_source)
    packages = run(cli, *command, '--entrypoint', 'cat', image, '/lib/apk/db/installed').decode()
    openssl = re.search(r'(?m)^P:libssl3\nV:([^\n]+)', packages)[1]
    assert tuple(map(int, re.match(r'(\d+)\.(\d+)\.(\d+)', openssl).groups())) >= (3, 5, 9), openssl
    binary = run(cli, *command, '--entrypoint', 'cat', image, '/usr/bin/lyrebird')
    build_info = inspect_transport(cli, binary)
    match = re.search(r'github.com/pion/stun/v3\s+v(\d+)\.(\d+)\.(\d+)', build_info)
    assert match and tuple(map(int, match.groups())) >= (3, 1, 5), 'STUN floor failed'
    print(json.dumps({'tor': tor.strip(), 'tor_source': source, 'openssl': openssl, 'stun': '.'.join(match.groups())}))


if __name__ == '__main__':
    main()
