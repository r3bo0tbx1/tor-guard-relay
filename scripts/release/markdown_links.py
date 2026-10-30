"""Resolve local and same-repository Markdown links without network access."""
import re
from urllib.parse import unquote, urlsplit

REPOSITORY = "r3bo0tbx1/tor-guard-relay"
FENCES = re.compile(r"(?ms)^([~`]{3,})[^\n]*\n.*?^\1[ \t]*(?:\n|$)")
LINK_PATTERNS = (
    re.compile(r"!?\[[^\n\]]*\]\((?P<target><?[^\s)]+>?)(?:\s+[^)]*)?\)"),
    re.compile(r'<(?:img|a)\b[^>]*\b(?:src|href)=["\'](?P<target>[^"\']+)["\']'),
    re.compile(r"(?m)^ {0,3}\[[^\]\n]+\]:[ \t]*(?P<target><?[^\s]+>?)"),
)


def prose(text):
    return FENCES.sub("", text)


def transform_links(text, replace):
    """Transform link destinations while preserving fenced examples and formatting."""
    def block(value):
        for pattern in LINK_PATTERNS:
            def link(match):
                target = match["target"]
                updated = replace(target.strip("<>"))
                if target.startswith("<"):
                    updated = f"<{updated}>"
                start = match.start("target") - match.start()
                end = match.end("target") - match.start()
                return match[0][:start] + updated + match[0][end:]
            value = pattern.sub(link, value)
        return value

    result, previous = [], 0
    for fence in FENCES.finditer(text):
        result.extend((block(text[previous:fence.start()]), fence[0]))
        previous = fence.end()
    result.append(block(text[previous:]))
    return "".join(result)


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


def github_target(parsed, repository=REPOSITORY):
    """Return (ref, repository path, route) for this repository's file URLs."""
    path = unquote(parsed.path)
    prefix = f"/{repository}/"
    if parsed.netloc.lower() == "raw.githubusercontent.com":
        if path.lower().startswith(prefix.lower()):
            ref, separator, relative = path[len(prefix):].partition("/")
            return (ref, relative, "raw") if separator else None
    elif not parsed.netloc or parsed.netloc.lower() == "github.com":
        for route in ("blob", "tree"):
            start = f"{prefix}{route}/"
            if path.lower().startswith(start.lower()):
                ref, separator, relative = path[len(start):].partition("/")
                return (ref, relative, route) if separator else None
    return None


def local_target(target, document, root, version, repository=REPOSITORY, strict_release=False):
    parsed = urlsplit(target)
    github = github_target(parsed, repository)
    if github:
        ref, path, _ = github
        if ref not in ("main", "HEAD", f"v{version}"):
            if strict_release:
                raise ValueError(f"repository documentation must target v{version}: {target}")
            return None
        path = f"/{path}"
    elif parsed.scheme or parsed.netloc:
        return None
    else:
        path = unquote(parsed.path)
    if any(c in path for c in ("<", ">", "{", "}")):
        return None
    resolved = root / path.lstrip("/") if path.startswith("/") else document.parent / path
    resolved = resolved.resolve() if path else document.resolve()
    if not resolved.is_relative_to(root.resolve()):
        raise ValueError(f"link escapes repository: {target}")
    if not resolved.exists() or (github and github[2] in ("blob", "raw") and not resolved.is_file()):
        raise ValueError(f"missing {target}")
    if parsed.fragment and resolved.suffix.lower() == ".md" and unquote(parsed.fragment) not in anchors(resolved):
        raise ValueError(f"missing anchor {target}")
    return resolved
