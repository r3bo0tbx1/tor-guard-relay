#!/usr/bin/env python3
import argparse
from collections import defaultdict
import re
import subprocess as sp

parser = argparse.ArgumentParser(description="Generate an editable release summary from local conventional commits.")
parser.add_argument("version")
parser.add_argument("previous", nargs="?")
parser.add_argument("-o", "--output")
parser.add_argument("-f", "--format", choices=("markdown", "github", "plain"), default="markdown")
parser.add_argument("--no-emoji", action="store_true")
parser.add_argument("--breaking-only", action="store_true")
args = parser.parse_args()
version = args.version.removeprefix("v")
previous = args.previous
if not previous:
    tags = sp.check_output(["git", "tag", "--sort=-v:refname"], text=True).splitlines()
    previous = next((t for t in tags if re.fullmatch(r"v\d+\.\d+\.\d+", t) and t != "v" + version), None)
if not previous:
    previous = sp.check_output(["git", "rev-list", "--max-parents=0", "HEAD"], text=True).strip()
if re.fullmatch(r"\d+\.\d+\.\d+", previous): previous = "v" + previous
hashes = sp.check_output(["git", "rev-list", "--reverse", previous + "..HEAD"], text=True).splitlines()
types = {"feat": "Added", "fix": "Fixed", "perf": "Performance", "docs": "Documentation",
         "build": "Dependencies", "ci": "Release and CI", "refactor": "Internal changes",
         "test": "Validation", "chore": "Maintenance", "style": "Presentation", "revert": "Reverted"}
groups = defaultdict(list)
for commit in hashes:
    subject, body = sp.check_output(["git", "show", "-s", "--format=%s%x00%b", commit], text=True).split("\0", 1)
    match = re.match(r"^[^\w]*(feat|fix|perf|docs|build|ci|refactor|test|chore|style|revert)(?:\([^)\r\n]+\))?(!)?:\s*(.+)$", subject.strip())
    title = match[3] if match else subject.strip()
    if args.no_emoji: title = re.sub(r"^[^\w]+", "", title)
    tick = chr(96)
    entry = f"- {title} ({tick}{commit[:8]}{tick})"
    if (match and match[2]) or re.search(r"^BREAKING[ -]CHANGE:", body, re.M):
        groups["Compatibility and breaking changes"].append(entry)
    if not args.breaking_only: groups[types.get(match[1], "Other") if match else "Other"].append(entry)
icons = {"Added": "✨", "Fixed": "🐛", "Performance": "⚡", "Documentation": "📚",
         "Dependencies": "📦", "Release and CI": "🚀", "Internal changes": "♻️",
         "Validation": "🧪", "Maintenance": "🔧", "Presentation": "🎨", "Reverted": "↩️",
         "Compatibility and breaking changes": "💥", "Other": "📋"}
show_emoji = not args.no_emoji and args.format != "plain"
lines = [f"# {'🧅 ' if show_emoji else ''}Tor Guard Relay v{version}", "", "Review this generated draft against the implemented behavior and validation evidence.", ""]
for heading in ["Compatibility and breaking changes", *dict.fromkeys(types.values()), "Other"]:
    icon = icons[heading] + " " if show_emoji else ""
    if groups[heading]: lines.extend(["## " + icon + heading, "", *groups[heading], ""])
result = "\n".join(lines) + "\n"
if args.format == "plain":
    result = re.sub(r"(?m)^#+ ", "", result).replace(chr(96), "")
if args.output:
    with open(args.output, "w", encoding="utf-8", newline="\n") as out: out.write(result)
else: print(result, end="")
