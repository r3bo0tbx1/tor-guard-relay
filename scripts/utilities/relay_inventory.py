#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess as sp

cli = (os.environ.get("DOCKER", "") or
       (shutil.which("docker.exe") if os.environ.get("WSL_DISTRO_NAME") else None) or
       shutil.which("docker") or shutil.which("docker.exe"))
if not cli:
    raise SystemExit("Docker CLI missing")


def call(*args):
    return sp.run([cli, *args], stdout=sp.PIPE, stderr=sp.DEVNULL)


parser = argparse.ArgumentParser(description="Read-only local relay inventory and metrics; does not probe the public network.")
group = parser.add_mutually_exclusive_group()
group.add_argument("--json", action="store_true")
group.add_argument("--prometheus", action="store_true")
parser.add_argument("containers", nargs="*")
args = parser.parse_args()
containers = args.containers or call("ps", "-aq", "--filter", "label=org.opencontainers.image.source=https://github.com/r3bo0tbx1/tor-guard-relay").stdout.decode().split()
rows = []
for container in containers:
    result = call("inspect", container)
    if result.returncode: raise SystemExit("Container inspect failed")
    info = json.loads(result.stdout)[0]
    image = json.loads(call("image", "inspect", info["Image"]).stdout)[0]
    health = None
    if info["State"]["Running"]:
        result = call("exec", container, "health")
        try: health = json.loads(result.stdout)
        except (ValueError, UnicodeError): pass
    labels = info["Config"].get("Labels") or {}
    rows.append({"container": info["Name"].lstrip("/"), "image_id": info["Image"],
                 "image_digests": image.get("RepoDigests", []), "running": info["State"]["Running"],
                 "project_version": labels.get("org.opencontainers.image.version", "unknown"),
                 "lyrebird_revision": labels.get("org.torproject.lyrebird.revision", "unknown"),
                 "health": health})
if args.prometheus:
    print("# HELP tor_relay_running Docker running state.\n# TYPE tor_relay_running gauge")
    for row in rows:
        name = json.dumps(row["container"])
        labels = "{container=" + name + "}"
        print("tor_relay_running" + labels + " " + str(int(row["running"])))
        health = row["health"] or {}
        print("tor_relay_observation_available" + labels + " " + str(int(bool(health))))
        for field in ("liveness", "readiness", "config_valid", "fresh"):
            print("tor_relay_" + field + labels + " " + str(int(health.get(field, False))))
        print("tor_relay_bootstrap_percent" + labels + " " + str(int(health.get("bootstrap", 0))))
elif args.json:
    print(json.dumps(rows, indent=2))
else:
    for row in rows:
        health = row["health"] or {}
        print(f'{row["container"]}: project={row["project_version"]} Tor={health.get("tor_version", "unknown")} running={row["running"]} readiness={health.get("readiness", "unknown")} reason={health.get("reason", "observation_unavailable")}')
