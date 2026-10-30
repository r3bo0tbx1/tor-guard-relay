#!/usr/bin/env python3
"""Authenticate an exact upstream Tor release without using a personal keyring."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess as sp
import tempfile
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
DIST = 'https://dist.torproject.org/'
# Authenticated against Tor's source-verification documentation. Key rotation is reviewed.
TRUSTED_SIGNERS = ('B74417EDDF22AC9F9E90F49142E86A2A11F48D36',
                   '514102454D0A87DB0767A1EBBE6A0531C18A9179')


def version_tuple(version):
    if not re.fullmatch(r'\d+\.\d+\.\d+\.\d+', version):
        raise ValueError('Expected a stable four-component Tor version')
    return tuple(map(int, version.split('.')))


def load_lock(path=HERE / 'source.json'):
    lock = json.loads(Path(path).read_text(encoding='utf-8'))
    if set(lock) != {'version', 'sha256', 'signing_fingerprint'}:
        raise ValueError('Unexpected Tor source lock fields')
    version_tuple(lock['version'])
    if not re.fullmatch(r'[a-f0-9]{64}', lock['sha256']):
        raise ValueError('Tor source checksum must be a complete SHA256')
    if lock['signing_fingerprint'] not in TRUSTED_SIGNERS:
        raise ValueError('Tor source signer requires independent review')
    return lock


def download(name, destination, limit=64 * 1024 * 1024):
    if not re.fullmatch(r'tor-\d+\.\d+\.\d+\.\d+\.tar\.gz(?:\.sha256sum(?:\.asc)?)?', name):
        raise ValueError('Unexpected Tor release asset name')
    request = Request(DIST + name, headers={'User-Agent': 'tor-relay-source-verifier'})
    with urlopen(request, timeout=45) as response, destination.open('wb') as output:
        if not response.url.startswith(DIST):
            raise ValueError('Tor release asset redirected outside the trusted origin')
        size = 0
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > limit:
                raise ValueError('Tor release asset exceeds the download limit')
            output.write(chunk)


def verify_signature(signature, checksum):
    gpg = shutil.which('gpg')
    if not gpg:
        raise ValueError('GnuPG is required to authenticate the Tor release')
    with tempfile.TemporaryDirectory(prefix='tor-release-keyring-') as directory:
        Path(directory).chmod(0o700)
        command = [gpg, '--no-options', '--batch', '--homedir', directory, '--no-auto-key-retrieve']
        sp.run([*command, '--import', str(HERE / 'release-key.asc'), str(HERE / 'ahf-release-key.asc')],
               check=True, capture_output=True)
        result = sp.run([*command, '--status-fd', '1', '--verify', str(signature), str(checksum)],
                        text=True, capture_output=True)
    rejected = ('BADSIG', 'ERRSIG', 'EXPKEYSIG', 'EXPSIG', 'REVKEYSIG', 'KEYEXPIRED', 'SIGEXPIRED')
    statuses = [line.split()[1:] for line in result.stdout.splitlines() if line.startswith('[GNUPG:] ')]
    if result.returncode or any(fields[0] in rejected for fields in statuses):
        raise ValueError('Tor checksum signature is invalid, expired, revoked or unverifiable')
    signers = {fields[1] for fields in statuses if fields[0] == 'VALIDSIG'}
    if not signers or not signers <= set(TRUSTED_SIGNERS):
        raise ValueError('Tor checksum was not signed by a reviewed release signer')
    return next(signer for signer in TRUSTED_SIGNERS if signer in signers)


def checksum_value(text, version):
    name = f'tor-{version}.tar.gz'
    match = re.fullmatch(r'([a-f0-9]{64}) [ *]' + re.escape(name) + r'\s*', text)
    if not match:
        raise ValueError('Signed checksum must name exactly the selected Tor archive')
    return match[1]


def fetch_release(version, destination, expected=None):
    version_tuple(version)
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / f'tor-{version}.tar.gz'
    checksum = destination / (archive.name + '.sha256sum')
    signature = destination / (checksum.name + '.asc')
    download(checksum.name, checksum, 16 * 1024)
    download(signature.name, signature, 64 * 1024)
    signer = verify_signature(signature, checksum)
    digest = checksum_value(checksum.read_text(encoding='ascii'), version)
    lock = {'version': version, 'sha256': digest, 'signing_fingerprint': signer}
    if expected is not None and lock != expected:
        raise ValueError('Authenticated Tor release differs from the reviewed source lock')
    download(archive.name, archive)
    with archive.open('rb') as source:
        actual = hashlib.file_digest(source, 'sha256').hexdigest()
    if actual != digest:
        raise ValueError('Tor source archive does not match its authenticated checksum')
    (destination / 'source.json').write_text(json.dumps(lock, indent=2) + '\n', encoding='utf-8')
    return lock


def latest_release():
    with urlopen(Request(DIST, headers={'Cache-Control': 'no-cache'}), timeout=45) as response:
        page = response.read(4 * 1024 * 1024).decode('utf-8')
    versions = set(re.findall(r'href="tor-(\d+\.\d+\.\d+\.\d+)\.tar\.gz"', page))
    if not versions:
        raise ValueError('No stable Tor source releases found at the upstream origin')
    return max(versions, key=version_tuple)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    lock = load_lock()
    fetch_release(lock['version'], args.destination, expected=lock)
    print(json.dumps({'verified': True, **lock}))


if __name__ == '__main__':
    main()
