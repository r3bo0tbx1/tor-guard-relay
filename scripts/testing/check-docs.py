#!/usr/bin/env python3
"""Check local and current-source GitHub documentation links and anchors."""
from pathlib import Path
import re
import subprocess as sp
import sys

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "scripts/release"))
from markdown_links import local_target, transform_links


def main():
    paths = sp.check_output(["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard"], text=True).splitlines()
    documents = sorted({root / p for p in paths if p.endswith(".md")})
    version = re.search(r'<!-- RELAY_VERSION -->v(\d+\.\d+\.\d+)<!-- /RELAY_VERSION -->', (root / "README.md").read_text(encoding="utf-8"))
    if not version:
        raise SystemExit("Managed project version marker missing")
    failures = []
    for document in documents:
        def check(target):
            try:
                local_target(target, document, root, version[1])
            except ValueError as error:
                failures.append(f"{document.relative_to(root)}: {error}")
            return target
        transform_links(document.read_text(encoding="utf-8"), check)
    if failures:
        raise SystemExit("\n".join(sorted(set(failures))))
    print(f"Validated local and current-source GitHub links, images and anchors in {len(documents)} Markdown documents")


if __name__ == "__main__":
    main()
