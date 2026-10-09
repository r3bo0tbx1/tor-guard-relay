#!/usr/bin/env python3
"""Offline Docker recovery rehearsal using synthetic named-volume and bind fixtures."""
import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess as sp
import tarfile
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("recovery", ROOT / "scripts/utilities/relay_backup.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)
parser = argparse.ArgumentParser()
parser.add_argument("--image", default="tor-relay:2.2.0-local")
parser.add_argument("--bind-parent", required=True, help="Task-owned scratch parent accessible to the Docker daemon")
args = parser.parse_args()
cli = backup.docker_cli()

def run(*argv, **kwargs):
    return sp.run([cli, *argv], check=True, stdout=sp.PIPE, stderr=sp.PIPE, **kwargs)

with tempfile.TemporaryDirectory(dir="/dev/shm" if Path("/dev/shm").exists() else None) as recovery_dir:
    recovery = Path(recovery_dir)
    identity = recovery / "identity"
    sp.run(["age-keygen", "-o", str(identity)], check=True, stderr=sp.DEVNULL)
    recipients = recovery / "recipients"
    recipients.write_bytes(sp.check_output(["age-keygen", "-y", str(identity)]))
    for layout in ("volume", "bind"):
        name = "relay-recovery-" + uuid.uuid4().hex[:12]
        volume = name + "-data"
        bind = tempfile.TemporaryDirectory(prefix="relay-bind-", dir=args.bind_parent) if layout == "bind" else None
        source = volume
        try:
            if bind:
                source = bind.name
                if cli.endswith(".exe"):
                    source = sp.check_output(["wslpath", "-w", source], text=True).strip()
            else:
                run("volume", "create", volume)
            mount = "type=" + ("bind" if bind else "volume") + ",source=" + source + ",target=/var/lib/tor"
            run("run", "--rm", "--network", "none", "--user", "0", "--mount", mount,
                "--entrypoint", "sh", args.image, "-ec", "chown 100:101 /var/lib/tor; chmod 700 /var/lib/tor")
            run("create", "--name", name, "--network", "none", "--mount", mount,
                "-e", "TOR_CONFIG=/etc/tor/recovery.conf", "-e", "TOR_RELAY_MODE=guard", args.image)
            config = b"Nickname RecoveryFixture\nContactInfo operator@example.com\nSocksPort 0\nORPort 9001\nExitRelay 0\nDataDirectory /var/lib/tor\nLog notice file /var/log/tor/notices.log\n%include /etc/tor/includes/*.conf\n"
            files = {"etc/tor/recovery.conf": config,
                     "etc/tor/includes/accounting.conf": b"AccountingMax 1 GB\nAccountingStart month 1 00:00\n"}
            bundle = io.BytesIO()
            with tarfile.open(fileobj=bundle, mode="w") as archive:
                for path, content in files.items():
                    member = tarfile.TarInfo(path); member.size = len(content)
                    member.uid = 100; member.gid = 101; member.mode = 0o600
                    archive.addfile(member, io.BytesIO(content))
            run("cp", "-", name + ":/", input=bundle.getvalue())
            run("start", name)
            for _ in range(100):
                try:
                    fingerprint = backup.read_file(name, "/var/lib/tor/fingerprint")
                    break
                except ValueError:
                    time.sleep(0.2)
            else:
                raise AssertionError("Synthetic fixture failed to generate identity")
            key = backup.read_file(name, "/var/lib/tor/keys/secret_id_key")
            # Volume tests explicitly stop/restart; bind tests preserve an already-stopped source.
            if bind:
                run("stop", "--time", "45", name)
            create = argparse.Namespace(container=name, recipients=str(recipients), passphrase=False,
                output_dir=str(recovery), stop=True, stop_timeout=45, max_bytes=20*1024**3,
                deployment_file=[], logs=True, dry_run=False)
            with contextlib.redirect_stdout(io.StringIO()) as output:
                backup.create(create)
            archive_path = output.getvalue().strip()
            verify = argparse.Namespace(archive=archive_path, identity=str(identity), max_bytes=20*1024**3,
                                        destination=str(recovery / layout), validation_image=args.image)
            manifest = backup.validate_archive(verify)
            backup.restore(verify)
            restored = Path(verify.destination)
            assert (restored / "data/fingerprint").read_bytes() == fingerprint
            assert (restored / "data/keys/secret_id_key").read_bytes() == key
            assert (restored / "config/etc/tor/recovery.conf").read_bytes() == config
            assert (restored / "config/etc/tor/includes/accounting.conf").read_bytes() == files["etc/tor/includes/accounting.conf"]
            assert backup.inspect(name)["State"]["Running"] == (layout == "volume")
            print(layout + ": encrypted create, full verify, include recovery, identity continuity and offline validation passed")
        finally:
            sp.run([cli, "rm", "-f", name], stdout=sp.DEVNULL, stderr=sp.DEVNULL)
            if not bind:
                sp.run([cli, "volume", "rm", volume], stdout=sp.DEVNULL, stderr=sp.DEVNULL)
            if bind:
                # Return only this newly created synthetic bind fixture to the host user.
                run("run", "--rm", "--network", "none", "--user", "0", "--mount", mount,
                    "--entrypoint", "chown", args.image, "-R", f"{os.getuid()}:{os.getgid()}", "/var/lib/tor")
                bind.cleanup()
