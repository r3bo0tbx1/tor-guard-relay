#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess as sp
import sys
cli = os.environ.get("DOCKER", "") or (shutil.which("docker.exe") if os.environ.get("WSL_DISTRO_NAME") else None) or shutil.which("docker")
image = sys.argv[1]
def run(*args, **kwargs):
    return sp.run([cli, *args], check=True, stdout=sp.PIPE, **kwargs).stdout
tor = run("run", "--rm", "--network", "none", "--entrypoint", "tor", image, "--version").decode()
assert tuple(map(int, re.search(r"Tor version (\d+)\.(\d+)\.(\d+)\.(\d+)", tor).groups())) >= (0,4,9,14)
packages = run("run", "--rm", "--network", "none", "--entrypoint", "cat", image, "/lib/apk/db/installed").decode()
openssl = re.search(r"(?m)^P:libssl3\nV:([^\n]+)", packages)[1]
assert tuple(map(int, re.match(r"(\d+)\.(\d+)\.(\d+)", openssl).groups())) >= (3,5,9), openssl
binary = run("run", "--rm", "--network", "none", "--entrypoint", "cat", image, "/usr/bin/lyrebird")
build_info = run("run", "-i", "--rm", "--network", "none", "--entrypoint", "sh", "golang:1.27.2-alpine3.24", "-ec",
                 "cat > /tmp/lyrebird; go version -m /tmp/lyrebird", input=binary).decode()
match = re.search(r"github.com/pion/stun/v3\s+v(\d+)\.(\d+)\.(\d+)", build_info)
assert match and tuple(map(int, match.groups())) >= (3,1,5), "STUN floor failed"
print(json.dumps({"tor": tor.strip(), "openssl": openssl, "stun": ".".join(match.groups())}))
