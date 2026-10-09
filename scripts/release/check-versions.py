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
args = parser.parse_args()
if not args.version:
    marker = re.search(r'<!-- RELAY_VERSION -->v(\d+\.\d+\.\d+)<!-- /RELAY_VERSION -->', (root / "README.md").read_text())
    if not marker: raise SystemExit("Managed project version marker missing")
    args.version = marker[1]
source = (root / "Dockerfile").read_text()
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
    text = p.read_text()
    # Preserve historical changelog entries, validating current Unreleased/new release text only.
    history = ""
    if rel == "CHANGELOG.md" and "## [v2.1.0]" in text:
        text, history = text.split("## [v2.1.0]", 1)
        history = "## [v2.1.0]" + history
    old = text
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
        if rel.startswith("templates/"):
            text = re.sub(r'("cosmos-version":\s*")[^"]+("|$)', r'\g<1>' + args.version + r'\g<2>', text)
            text = re.sub(r'(?m)^(\s+version: )"\d+\.\d+\.\d+"', r'\g<1>"' + args.version + '"', text)
    if text != old:
        if args.write: p.write_text(text + history, newline="\n"); print("Synchronized", rel)
        else: failures.append(rel)
    checked += 1
if checked < 23: raise SystemExit("Documentation discovery unexpectedly empty/incomplete")
required = ["README.md", "docs/README.md", "docs/BACKUP.md", "docs/TOOLS.md", "scripts/release/README.md"]
if any(not (root / name).is_file() for name in required): failures.append("required documentation missing")
if failures: raise SystemExit("Version drift: " + ", ".join(failures))
print(f"Alpine {alpine}: {checked} text files checked")
