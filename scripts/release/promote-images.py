#!/usr/bin/env python3
"""Publish the exact verified release archives without visible staging tags."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

from registry_tools import ARCHES, VARIANTS, Client, prepare_archive, promote, public_tags


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidates', required=True, type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--owner', required=True)
    parser.add_argument('--output', default='published-manifests.json', type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', args.source) or not re.fullmatch(r'[A-Za-z0-9-]+', args.owner):
        raise ValueError('Invalid release source or registry owner')
    public_tags('ghcr.io/' + args.owner.lower() + '/onion-relay', args.version, 'stable')
    output = args.output.resolve()
    with tempfile.TemporaryDirectory(prefix='relay-promotion-') as work:
        client = Client(work)
        # Verify every archive before performing any registry mutation.
        prepared = [prepare_archive(client, args.candidates / f'candidate-{variant}-{arch}',
                                    variant, arch, args.version, args.source)
                    for variant in VARIANTS for arch in ARCHES]
        rows = promote(client, prepared, ['r3bo0tbx1/onion-relay',
                                        f'ghcr.io/{args.owner.lower()}/onion-relay'], args.version, output)
    for row in rows:
        print(row['registry'], row['variant'], ', '.join(row['tags']), row['index_digest'])


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stderr or str(error)) from error
