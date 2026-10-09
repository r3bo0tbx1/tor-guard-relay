#!/usr/bin/env python3
"""Host-only streaming age backup. No Python is added to the relay image."""
import argparse
import datetime as dt
import fnmatch
import gzip
import hashlib
import io
import json
import os
import re
from pathlib import Path, PurePosixPath
import shlex
import shutil
import subprocess as sp
import sys
import tarfile
import uuid

LIMIT = 20 * 1024**3
MAX_META = 4 * 1024**2


def docker_cli():
    # Desktop exposes a native stub even when this distro's integration is off.
    return (os.environ.get("DOCKER", "") or
            (shutil.which("docker.exe") if os.environ.get("WSL_DISTRO_NAME") else None) or
            shutil.which("docker") or shutil.which("docker.exe"))


def docker(*args, **kwargs):
    cli = docker_cli()
    if not cli:
        raise ValueError("Docker CLI missing; enable Desktop/WSL integration or install Linux Docker")
    return sp.run([cli, *args], check=True, **kwargs)


def docker_pipe(*args):
    cli = docker_cli()
    return sp.Popen([cli, *args], stdout=sp.PIPE, stderr=sp.PIPE)


def inspect(container):
    return json.loads(docker("inspect", container, capture_output=True).stdout)[0]


def safe_name(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name or any(ord(c) < 32 for c in name):
        raise ValueError("Unsafe archive path")
    return str(path)


def read_file(container, path):
    p = docker_pipe("cp", f"{container}:{path}", "-")
    result = None
    try:
        with tarfile.open(fileobj=p.stdout, mode="r|") as archive:
            for member in archive:
                if result is not None or not member.isfile() or member.size > MAX_META:
                    raise ValueError("Required metadata is missing, too large or a link")
                result = archive.extractfile(member).read(MAX_META + 1)
        if p.wait() or result is None:
            raise ValueError("Docker could not read required metadata")
        return result
    except tarfile.TarError as error:
        # A newly started fixture may not have created its fingerprint yet.
        # docker cp then emits no tar stream; callers can retry ValueError.
        raise ValueError("Docker could not read required metadata") from error
    finally:
        p.stdout.close()
        p.stderr.close()
        if p.poll() is None: p.kill(); p.wait()


def config_files(container, config):
    found = {}

    def visit(path):
        if not path.startswith("/") or ".." in PurePosixPath(path).parts:
            raise ValueError("Config and include paths must be absolute, without traversal")
        if path in found:
            return
        data = read_file(container, path)
        found[path] = data
        if sum(map(len, found.values())) > MAX_META:
            raise ValueError("Configuration exceeds 4 MiB memory limit")
        for line in data.decode("utf-8").splitlines():
            fields = shlex.split(line, comments=True)
            if not fields or fields[0].lower() != "%include":
                continue
            if len(fields) != 2:
                raise ValueError("Invalid include directive")
            include = fields[1]
            if any(c in include for c in "*?[") or include.endswith("/"):
                parent = str(PurePosixPath(include).parent) if not include.endswith("/") else include.rstrip("/")
                pattern = PurePosixPath(include).name if not include.endswith("/") else "*"
                p = docker_pipe("cp", f"{container}:{parent}/.", "-")
                matches = []
                try:
                    with tarfile.open(fileobj=p.stdout, mode="r|") as archive:
                        for member in archive:
                            name = safe_name(member.name)
                            if member.isdir():
                                continue
                            if not member.isfile():
                                raise ValueError("Links in include directories are unsupported")
                            if "/" not in name and fnmatch.fnmatch(name, pattern):
                                matches.append(parent + "/" + name)
                    if p.wait():
                        raise ValueError("Cannot enumerate includes")
                finally:
                    p.stdout.close(); p.stderr.close()
                    if p.poll() is None: p.kill(); p.wait()
                if not matches:
                    raise ValueError("Include pattern matched no files")
                for match in sorted(matches): visit(match)
            else:
                visit(include)
    visit(config)
    return found


def source_paths(info):
    env = dict(item.split("=", 1) for item in info["Config"].get("Env", []) if "=" in item)
    config = env.get("TOR_CONFIG", "/etc/tor/torrc")
    cmd = info["Config"].get("Cmd") or []
    if "-f" in cmd:
        candidate = cmd[cmd.index("-f") + 1]
        if candidate != "/etc/tor/torrc" or config == "/etc/tor/torrc":
            config = candidate
    data = env.get("TOR_DATA_DIR", "/var/lib/tor")
    return config, data, env


def component_metadata(container, info):
    versions = {"tor": "unavailable", "openssl": "unavailable"}
    try:
        if info["State"]["Running"]:
            raw = docker("exec", container, "tor", "--version", capture_output=True).stdout.decode()
        else:
            raw = docker("run", "--rm", "--network", "none", "--entrypoint", "tor", info["Image"],
                         "--version", capture_output=True).stdout.decode()
        match = re.search(r"Tor version ([0-9.]+)", raw)
        if match: versions["tor"] = match[1].rstrip(".")
    except Exception:
        pass  # Older/custom source images may not expose this executable contract.
    try:
        packages = read_file(container, "/lib/apk/db/installed").decode()
        match = re.search(r"(?m)^P:libssl3\nV:([^\n]+)", packages)
        if match: versions["openssl"] = match[1]
    except Exception:
        pass
    return versions


def ensure_quiescent(container, info, data):
    if info["State"]["Running"] or info["State"]["Pid"]:
        raise ValueError("Source is not stopped")
    relevant = []
    for mount in info["Mounts"]:
        target = mount["Destination"].rstrip("/")
        if data == target or data.startswith(target + "/") or target.startswith(data.rstrip("/") + "/"):
            relevant.append(mount)
    ids = docker("ps", "-q", capture_output=True).stdout.decode().split()
    for cid in ids:
        other = inspect(cid)
        for one in relevant:
            for two in other["Mounts"]:
                same = one.get("Name") and one.get("Name") == two.get("Name")
                a, b = one.get("Source", "").rstrip("/"), two.get("Source", "").rstrip("/")
                overlap = bool(a and b) and (a == b or a.startswith(b + "/") or b.startswith(a + "/"))
                if (same or overlap) and two.get("RW", True):
                    raise ValueError("A running container can write shared source storage")


class DigestReader:
    def __init__(self, source):
        self.source = source
        self.digest = hashlib.sha256()

    def read(self, size=-1):
        data = self.source.read(size)
        self.digest.update(data)
        return data


def add_bytes(archive, name, data, records, mode=0o600):
    if name in records:
        raise ValueError("Duplicate archive entry")
    member = tarfile.TarInfo(name)
    member.size = len(data); member.mode = mode; member.uid = 100; member.gid = 101
    archive.addfile(member, io.BytesIO(data))
    records[name] = {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data), "mode": mode}


def add_tree(archive, container, source, prefix, records, budget):
    p = docker_pipe("cp", f"{container}:{source}/.", "-")
    try:
        with tarfile.open(fileobj=p.stdout, mode="r|") as incoming:
            for member in incoming:
                name = safe_name(member.name)
                if name == ".":
                    continue
                output = prefix + "/" + name
                if output in records:
                    raise ValueError("Duplicate source entry")
                if not (member.isfile() or member.isdir()):
                    raise ValueError("Source links and special files are unsupported")
                member.name = output; member.uid = 100; member.gid = 101
                member.uname = "tor"; member.gname = "tor"
                if member.isdir():
                    member.mode = 0o700; archive.addfile(member)
                    records[output] = {"directory": True, "mode": member.mode}
                else:
                    budget[0] += member.size
                    if budget[0] > budget[1]:
                        raise ValueError("Backup exceeds --max-bytes")
                    member.mode &= 0o777
                    reader = DigestReader(incoming.extractfile(member))
                    archive.addfile(member, reader)
                    records[output] = {"sha256": reader.digest.hexdigest(), "size": member.size, "mode": member.mode}
        if p.wait():
            raise ValueError("Docker archive producer failed")
    finally:
        p.stdout.close(); p.stderr.close()
        if p.poll() is None: p.kill(); p.wait()


def create(args):
    if not shutil.which("age"):
        raise ValueError("age missing")
    info = inspect(args.container)
    config, data, env = source_paths(info)
    configs = config_files(args.container, config)
    # Read supported absolute DataDirectory directives, including include files.
    data_directives = set()
    for content in configs.values():
        for line in content.decode().splitlines():
            fields = shlex.split(line, comments=True)
            if fields and fields[0].lower() == "datadirectory":
                if len(fields) != 2: raise ValueError("Invalid DataDirectory")
                data_directives.add(fields[1])
    if len(data_directives) > 1:
        raise ValueError("Ambiguous DataDirectory overrides; use one explicit data path")
    if data_directives: data = data_directives.pop()
    if not data.startswith("/") or data == "/" or ".." in PurePosixPath(data).parts:
        raise ValueError("Unsafe data directory")
    fingerprint = read_file(args.container, data + "/fingerprint").decode().strip()
    if not fingerprint:
        raise ValueError("Identity fingerprint missing; do not claim a complete identity backup")
    components = component_metadata(args.container, info)
    # Preflight recipient syntax without private source data.
    age_cmd = ["age", "-p"] if args.passphrase else ["age", "-R", args.recipients]
    if not args.passphrase:
        sp.run(age_cmd, input=b"", stdout=sp.DEVNULL, check=True)
    output_dir = Path(args.output_dir).resolve()
    if args.dry_run:
        print(json.dumps({"container": info["Name"], "config_files": len(configs), "data_path": data,
                          "running": info["State"]["Running"], "requires_stop": info["State"]["Running"],
                          "offline_keys": "Keep external/offline master material separately."}))
        return
    output_dir.mkdir(parents=True, exist_ok=True)
    was_running = info["State"]["Running"]
    if was_running and not args.stop:
        raise ValueError("Running source requires explicit --stop")
    filename = "relay-backup-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8] + ".tar.gz.age"
    final = output_dir / filename
    part = output_dir / (filename + ".part")
    stopped_by_us = False
    encryptor = None
    error = None
    try:
        if was_running:
            stopped_by_us = True
            docker("stop", "--time", str(args.stop_timeout), args.container, stdout=sp.DEVNULL)
        info = inspect(args.container)
        ensure_quiescent(args.container, info, data)
        # Re-read configuration after stop to catch changes during preflight.
        stopped_configs = config_files(args.container, config)
        if stopped_configs != configs:
            raise ValueError("Configuration changed during preflight; rerun backup")
        if read_file(args.container, data + "/fingerprint").decode().strip() != fingerprint:
            raise ValueError("Source identity changed during preflight")
        records = {}
        fd = os.open(part, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as ciphertext:
            encryptor = sp.Popen(age_cmd, stdin=sp.PIPE, stdout=ciphertext)
            try:
                with gzip.GzipFile(fileobj=encryptor.stdin, mode="wb", mtime=0) as compressed:
                    with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.PAX_FORMAT) as archive:
                        budget = [0, args.max_bytes]
                        add_tree(archive, args.container, data, "data", records, budget)
                        if not any(name.startswith("data/keys/") and "sha256" in item for name, item in records.items()):
                            raise ValueError("Required key files missing")
                        for path, content in configs.items():
                            add_bytes(archive, "config" + path, content, records)
                        for path in args.deployment_file:
                            src = Path(path)
                            if src.is_symlink() or src.stat().st_size > MAX_META:
                                raise ValueError("Deployment file too large or a link")
                            add_bytes(archive, "deployment/" + src.name, src.read_bytes(), records)
                        if args.logs:
                            add_tree(archive, args.container, env.get("TOR_LOG_DIR", "/var/log/tor"), "logs", records, budget)
                        manifest = {"format": 1, "created": dt.datetime.now(dt.timezone.utc).isoformat(),
                                    "container": info["Name"], "image_id": info["Image"],
                                    "image_reference": info["Config"]["Image"],
                                    "components": components,
                                    "image_labels": {key: value for key, value in (info["Config"].get("Labels") or {}).items()
                                                     if key.startswith("org.opencontainers.image.") or key == "org.torproject.lyrebird.revision"},
                                    "build_info": read_file(args.container, "/build-info.txt").decode() if
                                        (info["Config"].get("Labels") or {}).get("org.torproject.lyrebird.revision") else "Unavailable in source image",
                                    "config_path": config,
                                    "data_path": data, "fingerprint": fingerprint,
                                    "offline_master_keys": "External/offline material is NOT included.",
                                    "files": records}
                        raw = json.dumps(manifest, sort_keys=True).encode()
                        if len(raw) > MAX_META: raise ValueError("Manifest exceeds memory limit")
                        if sum(item.get("size", 0) for item in records.values()) + len(raw) > args.max_bytes:
                            raise ValueError("Backup exceeds --max-bytes including metadata")
                        add_bytes(archive, "manifest.json", raw, {}, 0o600)
                encryptor.stdin.close()
                if encryptor.wait(): raise ValueError("age encryption failed")
            except BaseException:
                encryptor.stdin.close()
                encryptor.terminate(); encryptor.wait()
                raise
            ciphertext.flush(); os.fsync(ciphertext.fileno())
        os.link(part, final)  # Atomic no-overwrite publication on the same filesystem.
        part.unlink()
        print(str(final))
    except BaseException as exc:
        error = exc
    finally:
        if part.exists(): part.unlink()
        if stopped_by_us:
            try:
                docker("start", args.container, stdout=sp.DEVNULL)
            except Exception as exc:
                if error: print("Source restart also failed; inspect container manually.", file=sys.stderr)
                else: error = ValueError("Backup published, but source restart failed")
    if error: raise error


def validate_archive(args, extract=None):
    age_cmd = ["age", "-d"]
    if args.identity: age_cmd += ["-i", args.identity]
    age_cmd += [str(Path(args.archive).resolve())]
    decoder = sp.Popen(age_cmd, stdout=sp.PIPE)
    actual = {}; total = 0; manifest = None
    try:
        with gzip.GzipFile(fileobj=decoder.stdout, mode="rb") as compressed:
            with tarfile.open(fileobj=compressed, mode="r|", ignore_zeros=True) as archive:
                for member in archive:
                    name = safe_name(member.name)
                    if name in actual or len(actual) >= 100000:
                        raise ValueError("Duplicate or excessive archive entries")
                    if not (member.isdir() or member.isfile()) or member.mode & 0o7000:
                        raise ValueError("Unsafe archive member type/permissions")
                    if name != "manifest.json" and name.split("/")[0] not in ("data", "config", "logs", "deployment"):
                        raise ValueError("Unexpected archive member")
                    total += member.size
                    if total > args.max_bytes: raise ValueError("Archive exceeds --max-bytes")
                    actual[name] = {"directory": True, "mode": member.mode} if member.isdir() else {"size": member.size, "mode": member.mode}
                    target = extract / name if extract else None
                    if member.isdir():
                        if target: target.mkdir(parents=True, exist_ok=True); target.chmod(0o700)
                        continue
                    incoming = archive.extractfile(member)
                    digest = hashlib.sha256()
                    chunks = [] if name == "manifest.json" else None
                    if chunks is not None and member.size > MAX_META: raise ValueError("Oversized manifest")
                    sink = None
                    if target:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        sink = open(target, "xb")
                    try:
                        while chunk := incoming.read(1024 * 1024):
                            digest.update(chunk)
                            if chunks is not None: chunks.append(chunk)
                            if sink: sink.write(chunk)
                    finally:
                        if sink: sink.close(); target.chmod(member.mode & 0o777)
                    actual[name]["sha256"] = digest.hexdigest()
                    if chunks is not None: manifest = json.loads(b"".join(chunks))
            while compressed.read(1024 * 1024):
                pass
        if decoder.wait(): raise ValueError("age authentication failed")
    finally:
        decoder.stdout.close()
        if decoder.poll() is None: decoder.terminate(); decoder.wait()
    if not isinstance(manifest, dict) or manifest.get("format") != 1:
        raise ValueError("Unsupported or missing manifest")
    del actual["manifest.json"]
    if actual != manifest.get("files"):
        raise ValueError("Archive content does not match encrypted manifest")
    if not any(n.startswith("data/keys/") and "sha256" in f for n, f in actual.items()):
        raise ValueError("Identity keys missing")
    if "data/fingerprint" not in actual:
        raise ValueError("Fingerprint missing")
    required_config = "config" + manifest["config_path"]
    if required_config not in actual: raise ValueError("Active config missing")
    if extract:
        fp = (extract / "data/fingerprint").read_text().strip()
        if fp != manifest["fingerprint"]: raise ValueError("Restored fingerprint mismatch")
    return manifest


def file_hash(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        while chunk := source.read(1024 * 1024): digest.update(chunk)
    return digest.hexdigest()


def validate_restored_config(destination, manifest, image):
    if not image or image.startswith("-") or any(c.isspace() for c in image):
        raise ValueError("Invalid validation image")
    docker("image", "inspect", image, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
    config_tar = io.BytesIO()
    with tarfile.open(fileobj=config_tar, mode="w") as archive:
        for name, record in manifest["files"].items():
            if name.startswith("config/") and "sha256" in record:
                member = tarfile.TarInfo(name[len("config/"):])
                content = (destination / name).read_bytes()
                member.size = len(content); member.mode = 0o600; member.uid = 100; member.gid = 101
                archive.addfile(member, io.BytesIO(content))
    helper = docker("create", "--network", "none", "--entrypoint", "tor", image,
                    "--verify-config", "-f", manifest["config_path"], capture_output=True).stdout.decode().strip()
    try:
        docker("cp", "-", helper + ":/", input=config_tar.getvalue(), stdout=sp.DEVNULL)
        docker("start", "-a", helper, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
        if inspect(helper)["State"]["ExitCode"]:
            raise ValueError("Restored torrc/includes failed offline validation")
    finally:
        docker("rm", "-f", helper, stdout=sp.DEVNULL)


def restore(args):
    # Authenticate and check everything before writing any plaintext.
    before = file_hash(args.archive)
    manifest = validate_archive(args)
    destination = Path(args.destination).absolute()
    if destination.exists():
        raise ValueError("Restore destination must not exist")
    destination.mkdir(mode=0o700, parents=False)
    try:
        validate_archive(args, destination)
        after = file_hash(args.archive)
        if after != before: raise ValueError("Archive changed during restore")
        validate_restored_config(destination, manifest, args.validation_image or manifest["image_id"])
        for p in destination.rglob("*"):
            if p.is_file() and "keys" in p.parts: p.chmod(0o600)
            if p.is_dir(): p.chmod(0o700)
            if os.geteuid() == 0: os.chown(p, 100, 101)
        if os.geteuid() == 0: os.chown(destination, 100, 101)
        print(json.dumps({"restored": str(destination), "config_path": manifest["config_path"],
                          "config_valid": True, "activation": "Map config/includes before explicit activation; no relay was started."}))
    except BaseException:
        # This is a newly created task-owned path, never existing relay data.
        shutil.rmtree(destination)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    create_parser = sub.add_parser("create")
    create_parser.add_argument("--container", required=True)
    encryption = create_parser.add_mutually_exclusive_group(required=True)
    encryption.add_argument("--recipients")
    encryption.add_argument("--passphrase", action="store_true")
    create_parser.add_argument("--output-dir", required=True)
    create_parser.add_argument("--stop", action="store_true")
    create_parser.add_argument("--stop-timeout", type=int, default=45)
    create_parser.add_argument("--dry-run", action="store_true")
    create_parser.add_argument("--logs", action="store_true")
    create_parser.add_argument("--deployment-file", action="append", default=[])
    create_parser.add_argument("--max-bytes", type=int, default=LIMIT)
    for command in ("verify", "restore"):
        p = sub.add_parser(command)
        p.add_argument("archive"); p.add_argument("--identity")
        p.add_argument("--max-bytes", type=int, default=LIMIT)
        if command == "restore":
            p.add_argument("--destination", required=True)
            p.add_argument("--validation-image", help="Locally available compatible image; defaults to original image ID")
    args = parser.parse_args()
    if args.command == "create": create(args)
    elif args.command == "restore": restore(args)
    else:
        manifest = validate_archive(args)
        print(json.dumps({"verified": True, "files": len(manifest["files"]), "format": manifest["format"]}))


if __name__ == "__main__":
    try:
        main()
    except (Exception, KeyboardInterrupt) as exc:
        # Never echo raw subprocess commands, private config or recipient contents.
        print("Backup operation failed: " + (str(exc) if isinstance(exc, ValueError) else type(exc).__name__), file=sys.stderr)
        sys.exit(1)
