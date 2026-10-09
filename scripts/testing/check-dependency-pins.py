#!/usr/bin/env python3
"""Reject source/metadata pin drift and inconsistent Go builders."""
from pathlib import Path
import re


def inspect_pins(root):
    revisions = []
    builders = []
    for name in ('Dockerfile', 'Dockerfile.edge'):
        text = (root / name).read_text()
        pins = re.findall(r'^ARG LYREBIRD_REVISION=(\S+)$', text, re.M)
        if len(pins) != 2 or any(not re.fullmatch(r'[a-f0-9]{40}', pin) for pin in pins):
            raise ValueError(f'{name}: expected two complete Lyrebird commit pins')
        revisions.extend(pins)
        builder = re.search(r'^FROM --platform=\$BUILDPLATFORM (golang:[^\s]+@sha256:[a-f0-9]{64}) AS builder$', text, re.M)
        if not builder:
            raise ValueError(f'{name}: pinned native Go builder missing')
        builders.append(builder[1])
    if len(set(revisions)) != 1:
        raise ValueError('Lyrebird source/metadata pins differ between stages or variants')
    if len(set(builders)) != 1:
        raise ValueError('Go builder pins differ between variants')
    return {'lyrebird_revision': revisions[0], 'go_builder': builders[0]}


if __name__ == '__main__':
    print(inspect_pins(Path(__file__).resolve().parents[2]))
