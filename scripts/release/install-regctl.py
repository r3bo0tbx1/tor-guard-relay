#!/usr/bin/env python3
"""Install the reviewed registry client after verifying its pinned checksum."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request


def main():
    root = Path(__file__).resolve().parents[2]
    pin = json.loads((root / 'build/registry-tools.json').read_text())
    target = Path(os.environ['RUNNER_TEMP']) / 'relay-registry-tools' / 'regctl'
    target.parent.mkdir(parents=True, exist_ok=True)
    url = f'https://github.com/regclient/regclient/releases/download/{pin["regctl"]}/regctl-linux-amd64'
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != pin['linux-amd64-sha256']:
        raise ValueError('Registry client checksum mismatch; review the version and checksum together')
    target.write_bytes(data)
    target.chmod(0o755)
    subprocess.run([str(target), 'version'], check=True)
    with open(os.environ['GITHUB_PATH'], 'a', encoding='utf-8') as output:
        output.write(str(target.parent) + '\n')


if __name__ == '__main__':
    main()
