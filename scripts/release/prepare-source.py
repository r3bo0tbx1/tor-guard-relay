#!/usr/bin/env python3
"""Materialize immutable release trees only from reviewed main ancestors."""
import argparse
from pathlib import Path
import re
import subprocess as sp


def prepare(root, source_sha, policy_sha):
    root = Path(root).resolve()
    # Validate both before creating either tree. Never execute tag-supplied helpers.
    for revision in (source_sha, policy_sha):
        if not re.fullmatch(r'[0-9a-f]{40}', revision):
            raise ValueError('Expected a full lowercase commit SHA')
        sp.run(['git', '-C', str(root), 'merge-base', '--is-ancestor',
                revision, 'origin/main'], check=True)
    for name in ('.release-source', '.release-policy'):
        if (root / name).exists():
            raise ValueError('Release workspace must be new: ' + name)
    for name, revision in (('.release-source', source_sha), ('.release-policy', policy_sha)):
        sp.run(['git', '-C', str(root), 'worktree', 'add', '--detach',
                str(root / name), revision], check=True)
    return root / '.release-source', root / '.release-policy'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--policy', required=True)
    args = parser.parse_args()
    prepare(Path(__file__).resolve().parents[2], args.source, args.policy)


if __name__ == '__main__':
    main()
