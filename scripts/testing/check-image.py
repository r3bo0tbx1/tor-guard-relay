#!/usr/bin/env python3
"""Check component floors with the policy's pinned, native Go inspector."""
import importlib.util
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
    cli = (os.environ.get('DOCKER') or (shutil.which('docker.exe') if os.environ.get('WSL_DISTRO_NAME') else None)
           or shutil.which('docker'))
    if not cli:
        raise RuntimeError('Docker is required')
    image = sys.argv[1]
    arch = run(cli, 'image', 'inspect', '--format', '{{.Architecture}}', image).decode().strip()
    if arch not in ('amd64', 'arm64'):
        raise ValueError('Unsupported candidate architecture')
    command = ('run', '--rm', '--pull=never', '--platform', 'linux/' + arch, '--network', 'none')
    tor = run(cli, *command, '--entrypoint', 'tor', image, '--version').decode()
    assert tuple(map(int, re.search(r'Tor version (\d+)\.(\d+)\.(\d+)\.(\d+)', tor).groups())) >= (0, 4, 9, 14)
    packages = run(cli, *command, '--entrypoint', 'cat', image, '/lib/apk/db/installed').decode()
    openssl = re.search(r'(?m)^P:libssl3\nV:([^\n]+)', packages)[1]
    assert tuple(map(int, re.match(r'(\d+)\.(\d+)\.(\d+)', openssl).groups())) >= (3, 5, 9), openssl
    binary = run(cli, *command, '--entrypoint', 'cat', image, '/usr/bin/lyrebird')
    build_info = inspect_transport(cli, binary)
    match = re.search(r'github.com/pion/stun/v3\s+v(\d+)\.(\d+)\.(\d+)', build_info)
    assert match and tuple(map(int, match.groups())) >= (3, 1, 5), 'STUN floor failed'
    print(json.dumps({'tor': tor.strip(), 'openssl': openssl, 'stun': '.'.join(match.groups())}))


if __name__ == '__main__':
    main()
