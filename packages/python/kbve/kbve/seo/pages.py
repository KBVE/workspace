"""Content discovery and parsing, for any Astro site.

Upstream this was `_pages`, private and pointed at one hardcoded path:
``apps/kbve/astro-kbve/src/content/docs``. It walked up from its own
``__file__`` looking for that directory, so the auditor could only ever run
against the repository it was written in.

The content directory is an argument now. What did not need changing is the
shape it expects, because that shape is Astro's own: a collection is a
directory under ``src/content``, so the first path segment is the collection
name on every Astro site there is.
"""

from __future__ import annotations

import os
import re
from collections.abc import Iterator
from pathlib import Path

import yaml

from .models import ERROR, Finding, Frontmatter, Page

_FRONTMATTER = re.compile(r"^---\n(.*?)\n---\n?(.*)$", re.S)

CONTENT_SUFFIXES = (".md", ".mdx")


def find_content_dir(explicit: str | os.PathLike[str] | None = None,
                     root: str | os.PathLike[str] | None = None) -> Path:
    """Resolve a content directory.

    `explicit` wins and is used as given. Otherwise `root` is searched for a
    single ``src/content``: an Astro project root has one, and a workspace with
    several sites in it has several, which is ambiguous rather than a default
    worth guessing at.
    """
    if explicit is not None:
        path = Path(explicit)
        if not path.is_dir():
            raise FileNotFoundError(f"no content directory at {path}")
        return path

    base = Path(root) if root is not None else Path.cwd()
    if not base.is_dir():
        raise FileNotFoundError(f"no directory at {base}")

    direct = base / "src" / "content"
    if direct.is_dir():
        return direct

    found = sorted(
        p for p in base.glob("*/*/*/src/content") if p.is_dir()
    ) or sorted(p for p in base.glob("*/*/src/content") if p.is_dir())

    if len(found) == 1:
        return found[0]
    if not found:
        raise FileNotFoundError(
            f"no src/content under {base}; pass --content <dir>")
    listed = ", ".join(str(p.relative_to(base)) for p in found)
    raise FileNotFoundError(
        f"{len(found)} content directories under {base} ({listed}); "
        "pass --content <dir> to choose one")


def _url(collection: str, slug: str) -> str:
    return f"/{collection}/{slug}/"


def split_frontmatter(text: str) -> tuple[object, str]:
    """Return (raw_frontmatter, body). The frontmatter is not yet validated."""
    match = _FRONTMATTER.match(text)
    if not match:
        return {}, text
    try:
        return yaml.safe_load(match.group(1)) or {}, match.group(2)
    except yaml.YAMLError as exc:
        return _YamlError(str(exc)), match.group(2)


class _YamlError(str):
    """Marks frontmatter that would not parse, carrying the parser's message."""


def iter_pages(content_dir: str | os.PathLike[str],
               only: str | None = None) -> Iterator[Page]:
    """Yield a Page per content file under `content_dir`.

    `only` restricts the walk to one collection. The slug keeps the path below
    the collection rather than just the filename: a site that files pages by
    locale (`pages/en/about.mdx`) has one `about` per language, and flattening
    them would report every translation as a duplicate of the others.
    """
    root = Path(content_dir)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        here = Path(dirpath)
        rel = here.relative_to(root)
        parts = rel.parts
        collection = parts[0] if parts else ""
        if only is not None and collection != only:
            continue
        for name in sorted(filenames):
            if not name.endswith(CONTENT_SUFFIXES):
                continue
            path = here / name
            text = path.read_text(encoding="utf-8")
            raw, body = split_frontmatter(text)

            if isinstance(raw, _YamlError):
                yield Page(
                    collection=collection or "content",
                    slug="/".join([*parts[1:], Path(name).stem]),
                    url=_url(collection or "content",
                             "/".join([*parts[1:], Path(name).stem])),
                    path=str(path),
                    frontmatter=Frontmatter(),
                    body=body,
                    parse_findings=(
                        Finding(rule="frontmatter-parse", severity=ERROR,
                                message=f"unparseable YAML: {raw}"),
                    ),
                )
                continue

            frontmatter, findings = Frontmatter.parse(raw)
            slug = "/".join([*parts[1:], Path(name).stem])
            yield Page(
                collection=collection or "content",
                slug=slug,
                url=_url(collection or "content", slug),
                path=str(path),
                frontmatter=frontmatter,
                body=body,
                parse_findings=tuple(findings),
            )
