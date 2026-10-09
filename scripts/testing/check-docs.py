#!/usr/bin/env python3
"""Check repository-local Markdown links, images and heading anchors."""
from pathlib import Path
import re
import subprocess as sp
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parents[2]
paths = sp.check_output(["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard"], text=True).splitlines()
documents = sorted({root / p for p in paths if p.endswith(".md")})
failures = []

def prose(text):
    return re.sub(r"(?ms)^([~`]{3,})[^\n]*\n.*?^\1[ \t]*$", "", text)

def anchors(path):
    text = prose(path.read_text(encoding="utf-8"))
    found = set(re.findall(r'<[^>]+\b(?:id|name)=["\']([^"\']+)', text))
    counts = {}
    for heading in re.findall(r"(?m)^#{1,6}\s+(.+?)(?:\s+#+)?$", text):
        heading = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", heading)
        slug = re.sub(r"[^\w\- ]", "", re.sub(r"<[^>]*>", "", heading).strip().lower()).replace(" ", "-")
        count = counts.get(slug, 0)
        found.add(slug if count == 0 else f"{slug}-{count}")
        counts[slug] = count + 1
    return found

for document in documents:
    text = prose(document.read_text(encoding="utf-8"))
    targets = re.findall(r"!?\[[^\n\]]*\]\((<?[^\s]+?>?)(?:\s+[^)]*)?\)", text)
    targets += re.findall(r'<(?:img|a)\b[^>]*\b(?:src|href)=["\']([^"\']+)', text)
    for target in targets:
        target = target.strip("<>")
        parsed = urlsplit(target)
        if parsed.scheme or parsed.netloc or target.startswith("//"):
            continue
        path = unquote(parsed.path)
        if any(c in path for c in ("<", ">", "{", "}")):
            continue
        resolved = (root / path.lstrip("/")) if path.startswith("/") else document.parent / path
        resolved = resolved.resolve() if path else document
        if not resolved.exists():
            failures.append(f"{document.relative_to(root)}: missing {target}")
        elif parsed.fragment and resolved.suffix == ".md" and unquote(parsed.fragment) not in anchors(resolved):
            failures.append(f"{document.relative_to(root)}: missing anchor {target}")
if failures:
    raise SystemExit("\n".join(sorted(set(failures))))
print(f"Validated local links, images and anchors in {len(documents)} Markdown documents")
