#!/usr/bin/env python3
"""Offline image acceptance for local candidates and release jobs."""
import argparse
import json
import os
import shutil
import subprocess as sp
import time
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("image")
parser.add_argument("--platform", default="linux/amd64")
args = parser.parse_args()
cli = os.environ.get("DOCKER", "") or (shutil.which("docker.exe") if os.environ.get("WSL_DISTRO_NAME") else None) or shutil.which("docker")
def run(*argv, check=True):
    result = sp.run([cli, *argv], stdout=sp.PIPE, stderr=sp.PIPE, text=True)
    if check and result.returncode:
        raise RuntimeError(f"Docker fixture command failed: {argv}: {result.stdout} {result.stderr}")
    return result
def execute(name, *argv, check=True):
    return run("exec", name, *argv, check=check)

version = run("run", "--rm", "--platform", args.platform, "--network", "none", "--entrypoint", "tor", args.image, "--version").stdout
parts = tuple(map(int, version.split("Tor version ")[1].split(".")[:3] + [version.split("Tor version ")[1].split(".")[3]]))
assert parts >= (0,4,9,14), version
for role in ("guard", "exit", "bridge"):
    name = "relay-accept-" + uuid.uuid4().hex[:10]
    try:
        run("run", "-d", "--name", name, "--platform", args.platform, "--network", "none",
            "-e", "TOR_NICKNAME=LocalTestRelay", "-e", "TOR_CONTACT_INFO=operator@example.com",
            "-e", "TOR_RELAY_MODE=" + role, "-e", "TOR_CONFIG=/etc/tor/test.conf",
            "-e", "TOR_ACCOUNTING_MAX=1 GB", "-e", "TOR_ACCOUNTING_START=month 1 00:00", args.image)
        health = None
        for _ in range(50):
            result = execute(name, "health", check=False)
            if result.returncode == 0:
                health = json.loads(result.stdout); break
            time.sleep(0.2)
        assert health is not None, run("logs", name).stdout
        assert health["liveness"] and health["config_valid"] and not health["readiness"], health
        assert health["config_path"] == "/etc/tor/test.conf" and health["config_source"] == "environment", health
        execute(name, "config", "validate")
        before_config = execute(name, "sha256sum", "/etc/tor/test.conf").stdout
        execute(name, "sh", "-c", "printf 'InvalidOptionForRegression 1\\n' > /tmp/invalid.torrc")
        assert execute(name, "config", "apply", "/tmp/invalid.torrc", check=False).returncode != 0
        assert execute(name, "sha256sum", "/etc/tor/test.conf").stdout == before_config
        execute(name, "sh", "-c", "cp /etc/tor/test.conf /tmp/valid.torrc")
        execute(name, "config", "apply", "/tmp/valid.torrc", "--reload")
        # Inject a current-run bootstrap event, then force a restart boundary.
        execute(name, "sh", "-c", "printf 'Bootstrapped 100%%\\n' >> /var/log/tor/notices.log")
        assert json.loads(execute(name, "health").stdout)["bootstrap"] == 100
        first = json.loads(execute(name, "health").stdout)
        execute(name, "refresh")
        second = json.loads(execute(name, "health").stdout)
        assert first["pid"] == second["pid"], "Refresh changed PID"
        run("restart", "--time", "45", name)
        for _ in range(50):
            result = execute(name, "health", check=False)
            if result.returncode == 0: break
            time.sleep(0.2)
        updated = json.loads(result.stdout)
        assert updated["bootstrap"] < 100 and not updated["readiness"], updated
        if role == "bridge":
            for _ in range(150):
                result = execute(name, "bridge-line", "--json", "--address", "192.0.2.10", "--port", "9443", check=False)
                bridge = json.loads(result.stdout)
                if bridge["reason"] == "ready": break
                time.sleep(0.2)
            assert bridge["reason"] == "ready" and "192.0.2.10:9443" in bridge["line"], bridge
            ipv6 = execute(name, "bridge-line", "--plain", "--address", "2001:db8::10").stdout
            assert "[2001:db8::10]:" in ipv6, ipv6
        run("stop", "--time", "45", name)
        state = json.loads(run("inspect", name).stdout)[0]["State"]
        assert not state["Running"] and state["ExitCode"] == 0, state
        print(role + ": offline startup, config, health freshness, refresh and shutdown passed")
    except Exception:
        logs = run("logs", "--tail", "35", name, check=False)
        print(logs.stdout + logs.stderr)
        raise
    finally:
        run("rm", "-f", name, check=False)
print(args.platform + ": Tor " + version.strip())
