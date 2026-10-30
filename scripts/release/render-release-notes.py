#!/usr/bin/env python3
"""Validate curated notes and make repository links portable to GitHub Releases."""
import argparse
from pathlib import Path
import re
import sys
from urllib.parse import quote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from markdown_links import REPOSITORY, github_target, local_target, transform_links


def render(root, version, repository=REPOSITORY):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Version must be X.Y.Z")
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository):
        raise ValueError("Repository must be owner/name")
    root = root.resolve()
    document = root / "docs/releases" / f"v{version}.md"

    def portable(target):
        resolved = local_target(target, document, root, version, repository, strict_release=True)
        if resolved is None:
            return target
        parsed = urlsplit(target)
        # Keep release-body navigation inside the published body.
        if not parsed.path and parsed.fragment:
            return target
        github = github_target(parsed, repository)
        relative = quote(resolved.relative_to(root).as_posix(), safe="/")
        if (github and github[2] == "raw") or resolved.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg"):
            url = f"https://raw.githubusercontent.com/{repository}/v{version}/{relative}"
        else:
            route = "blob" if resolved.is_file() else "tree"
            url = f"https://github.com/{repository}/{route}/v{version}/{relative}"
        if parsed.query:
            url += f"?{parsed.query}"
        if parsed.fragment:
            url += f"#{parsed.fragment}"
        return url

    text = document.read_text(encoding="utf-8")
    if not text.strip():
        raise ValueError(f"Empty curated release notes: {document}")
    return transform_links(text, portable)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--repository", default=REPOSITORY)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        rendered = render(args.root, args.version, args.repository)
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
    args.output.write_bytes(rendered.encode("utf-8"))
    print(f"Validated and rendered v{args.version} release notes")


if __name__ == "__main__":
    main()
