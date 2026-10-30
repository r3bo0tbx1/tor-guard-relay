#!/bin/sh
set -eu
cd /home/build
python3 /build/tor/preflight.py
mkdir -p recipe output .abuild
python3 /build/tor/source.py --destination /home/build/recipe
python3 - <<'PY'
import hashlib
import json
from pathlib import Path
root = Path('/home/build/recipe')
lock = json.loads((root / 'source.json').read_text())
archive = root / ('tor-' + lock['version'] + '.tar.gz')
with archive.open('rb') as source:
    digest = hashlib.file_digest(source, 'sha512').hexdigest()
recipe = Path('/build/tor/APKBUILD.in').read_text()
(root / 'APKBUILD').write_text(recipe.replace('@VERSION@', lock['version']).replace('@SHA512@', digest))
PY
# This disposable APK key signs only the local build artifact; it never enters the image.
openssl genrsa -out /home/build/.abuild/relay-tor-source.rsa 3072
openssl rsa -in /home/build/.abuild/relay-tor-source.rsa -pubout \
    -out /home/build/.abuild/relay-tor-source.rsa.pub
printf 'PACKAGER_PRIVKEY="/home/build/.abuild/relay-tor-source.rsa"\n' > .abuild/abuild.conf
cd recipe
APK="/sbin/apk --keys-dir /home/build/.abuild" abuild -d -m -P /home/build/packages
find /home/build/packages -name 'tor-*.apk' -type f -exec cp '{}' /home/build/output/ ';'
cp /home/build/.abuild/relay-tor-source.rsa.pub /home/build/output/
test "$(find /home/build/output -name '*.apk' -type f | wc -l)" -eq 1
