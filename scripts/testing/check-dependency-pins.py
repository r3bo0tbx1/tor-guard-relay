#!/usr/bin/env python3
"""Reject source/metadata pin drift, inconsistent builders and Tor floors."""
from pathlib import Path
import importlib.util
import re


def inspect_pins(root):
    revisions = []
    builders = []
    spec = importlib.util.spec_from_file_location('tor_source', root / 'build/tor/source.py')
    source = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(source)
    tor_source = source.load_lock(root / 'build/tor/source.json')
    for name in ('Dockerfile', 'Dockerfile.edge'):
        text = (root / name).read_text(encoding='utf-8')
        pins = re.findall(r'^ARG LYREBIRD_REVISION=(\S+)$', text, re.M)
        if len(pins) != 2 or any(not re.fullmatch(r'[a-f0-9]{40}', pin) for pin in pins):
            raise ValueError(f'{name}: expected two complete Lyrebird commit pins')
        revisions.extend(pins)
        builder = re.search(r'^FROM --platform=\$BUILDPLATFORM (golang:[^\s]+@sha256:[a-f0-9]{64}) AS builder$', text, re.M)
        if not builder:
            raise ValueError(f'{name}: pinned native Go builder missing')
        builders.append(builder[1])
        bases = re.findall(r'^FROM (alpine:\S+)(?: AS tor-builder)?$', text, re.M)
        if len(bases) != 2 or len(set(bases)) != 1:
            raise ValueError(f'{name}: Tor builder and runtime Alpine bases differ')
        if ('COPY build/tor/ /build/tor/' not in text or 'RUN sh /build/tor/build.sh' not in text
                or 'COPY --from=tor-builder /home/build/output/ /tmp/tor-package/' not in text
                or 'apk add --no-cache /tmp/tor-package/tor-*.apk' not in text
                or 'TOR_MIN_VERSION=' in text or '"tor>=' in text):
            raise ValueError(f'{name}: expected the authenticated Tor source-package build')
    if len(set(revisions)) != 1:
        raise ValueError('Lyrebird source/metadata pins differ between stages or variants')
    if len(set(builders)) != 1:
        raise ValueError('Go builder pins differ between variants')
    return {'lyrebird_revision': revisions[0], 'go_builder': builders[0],
            'tor_min_version': tor_source['version'], 'tor_source_sha256': tor_source['sha256']}


if __name__ == '__main__':
    print(inspect_pins(Path(__file__).resolve().parents[2]))
