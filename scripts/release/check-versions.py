#!/usr/bin/env python3
"""Synchronize supported Alpine examples and managed project-version fields."""
import argparse
import json
from pathlib import Path
import re
import subprocess as sp
import sys

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--write", action="store_true")
parser.add_argument("--version", help="Update explicit RELAY_VERSION markers and current image references")
parser.add_argument("--print-version", action="store_true", help="Print the managed source version without changing files")
args = parser.parse_args()
if not args.version:
    marker = re.search(r'<!-- RELAY_VERSION -->v(\d+\.\d+\.\d+)<!-- /RELAY_VERSION -->', (root / "README.md").read_text(encoding="utf-8"))
    if not marker: raise SystemExit("Managed project version marker missing")
    args.version = marker[1]
if not re.fullmatch(r"\d+\.\d+\.\d+", args.version): raise SystemExit("Version must be X.Y.Z")
if args.print_version:
    print(args.version)
    raise SystemExit(0)
source = (root / "Dockerfile").read_text(encoding="utf-8")
base = re.search(r"^FROM alpine:(\d+\.\d+\.\d+)", source, re.M)
if not base: raise SystemExit("Stable Alpine FROM missing")
alpine = base[1]
files = sp.check_output(["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard"], text=True).splitlines()
failures = []
checked = 0
for rel in sorted(set(files)):
    p = root / rel
    if p.suffix not in (".md", ".sh", ".yml", ".json") and p.name not in ("Dockerfile", "Dockerfile.edge"):
        continue
    # Published release notes describe their original source, not today's base image.
    if rel.startswith("docs/releases/"):
        checked += 1
        continue
    text = p.read_text(encoding="utf-8")
    # Only the current header/Unreleased section can contain managed project fields.
    history = ""
    if rel == "CHANGELOG.md":
        release = re.search(r"(?m)^## \[v\d+\.\d+\.\d+\]", text)
        if release:
            text, history = text[:release.start()], text[release.start():]
    old = text
    # Changelog dependency versions are change records, even before release.
    if rel != "CHANGELOG.md":
        text = re.sub(r"alpine:\d+\.\d+\.\d+", "alpine:" + alpine, text) if p.name not in ("Dockerfile", "Dockerfile.edge") else text
        text = re.sub(r"Alpine(?: Linux)? \d+\.\d+\.\d+", lambda m: re.sub(r"\d+\.\d+\.\d+", alpine, m[0]), text)
        text = re.sub(r"(docker\.io/library/alpine:)\d+\.\d+\.\d+", r"\g<1>" + alpine, text)
        text = re.sub(r"\balpine(?=\s+(?:tar|sh|bash|chown|chmod|cat|grep|ls|find|rm|test)\b)", "alpine:" + alpine, text)
    if args.version:
        if not re.fullmatch(r"\d+\.\d+\.\d+", args.version): raise SystemExit("Version must be X.Y.Z")
        # Historical guides keep their target release semantics and tag references.
        if rel not in ("docs/MIGRATION-V1.1.X.md", "docs/TROUBLESHOOTING-BRIDGE-MIGRATION.md") and not rel.startswith("docs/releases/"):
            text = re.sub(r"(onion-relay:)\d+\.\d+\.\d+(?![\d.])", r"\g<1>" + args.version, text)
        text = re.sub(r"(<!-- RELAY_VERSION -->).*?(<!-- /RELAY_VERSION -->)", r"\g<1>v" + args.version + r"\g<2>", text)
        text = re.sub(r"(<!-- RELAY_IMAGE_VERSION -->`?).*?((?:-edge)?`?<!-- /RELAY_IMAGE_VERSION -->)", r"\g<1>" + args.version + r"\g<2>", text)
        if rel == "docs/TOOLS.md":
            text = re.sub(r'("build_version":\s*")\d+\.\d+\.\d+(")', r'\g<1>' + args.version + r'\g<2>', text)
            text = re.sub(r'(Tor Relay Status · )\d+\.\d+\.\d+', r'\g<1>' + args.version, text)
        if rel.startswith("templates/"):
            text = re.sub(r'("cosmos-version":\s*")[^"]+("|$)', r'\g<1>' + args.version + r'\g<2>', text)
            text = re.sub(r'(?m)^(\s+version: )"\d+\.\d+\.\d+"', r'\g<1>"' + args.version + '"', text)
    if text != old:
        if args.write: p.write_text(text + history, encoding="utf-8", newline="\n"); print("Synchronized", rel)
        else: failures.append(rel)
    checked += 1
if checked < 23: raise SystemExit("Documentation discovery unexpectedly empty/incomplete")
required = ["README.md", "docs/README.md", "docs/BACKUP.md", "docs/TOOLS.md", "scripts/release/README.md"]
if any(not (root / name).is_file() for name in required): failures.append("required documentation missing")
if failures: raise SystemExit("Version drift: " + ", ".join(failures))
print(f"Alpine {alpine}: {checked} text files checked")
