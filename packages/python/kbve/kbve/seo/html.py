"""Reading a built page back out of rendered HTML.

Source mode audits what an author edits, which is what makes a finding
actionable -- it names a file you can open. What it cannot see is everything
the layout computes on the way out, and on a real site that is most of the
metadata: rentearth.com's Base.astro renders ``title: About`` as
``About — RentEarth``, so a source-only auditor measures 5 characters where 17
ship, and reports a title as too short when it is not.

Build mode closes that gap by reading the output instead. The rendered title is
the title, so nothing has to be told what template produced it. The trade is
the one source mode was built to avoid: a finding here names a generated file,
and cannot say which .mdx to edit.

Neither is a replacement for the other, so the auditor runs either.

Parsing uses html.parser from the standard library rather than a real HTML
library. What is needed is head metadata, heading levels, image alt attributes
and hrefs -- all of it flat, none of it needing a correct tree.
"""

from __future__ import annotations

import os
from collections.abc import Iterator
from html.parser import HTMLParser
from pathlib import Path

from .models import BUILD, Finding, Frontmatter, Page

# Rendered documents that are not pages: an error page has no audience in
# search, and a redirect stub is a <meta http-equiv> with no content at all.
SKIP_DIRS = {"_astro", "assets", "node_modules"}


class _PageParser(HTMLParser):
    """Pulls the handful of things the rules read out of a rendered page."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title: str | None = None
        self.description: str | None = None
        self.canonical: str | None = None
        self.robots: str | None = None
        self.og_image: str | None = None
        self.og_image_alt: str | None = None
        self.is_redirect = False
        # Rebuilt into the markdown the body rules already understand, so one
        # implementation of "is this heading level a skip" serves both modes.
        self.body: list[str] = []

        self._in_title = False
        self._in_body = False
        self._skip_depth = 0
        self._heading: int | None = None
        self._heading_text: list[str] = []

    # -- head ------------------------------------------------------------
    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        a = {k: (v or "") for k, v in attrs}

        if tag == "title":
            self._in_title = True
        elif tag == "body":
            self._in_body = True
        elif tag in ("script", "style", "template", "noscript"):
            self._skip_depth += 1
        elif tag == "meta":
            name = (a.get("name") or "").lower()
            prop = (a.get("property") or "").lower()
            content = a.get("content", "")
            if name == "description":
                self.description = content
            elif name == "robots":
                self.robots = content.lower()
            elif prop == "og:image":
                self.og_image = content
            elif prop == "og:image:alt":
                self.og_image_alt = content
            elif (a.get("http-equiv") or "").lower() == "refresh":
                self.is_redirect = True
        elif tag == "link" and (a.get("rel") or "").lower() == "canonical":
            self.canonical = a.get("href")
        elif tag == "img" and self._in_body:
            alt = a.get("alt", "").strip()
            src = a.get("src", "?")
            self.body.append(f"![{alt}]({src})")
        elif tag == "a" and self._in_body and a.get("href"):
            self._pending_href = a["href"]
        elif tag in ("h1", "h2", "h3", "h4", "h5", "h6") and self._in_body:
            self._heading = int(tag[1])
            self._heading_text = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._in_title = False
        elif tag in ("script", "style", "template", "noscript"):
            self._skip_depth = max(0, self._skip_depth - 1)
        elif tag in ("h1", "h2", "h3", "h4", "h5", "h6") and self._heading:
            text = " ".join("".join(self._heading_text).split())
            self.body.append(f"{'#' * self._heading} {text or '-'}")
            self._heading = None
        elif tag == "a":
            href = getattr(self, "_pending_href", None)
            if href and self._in_body:
                self.body.append(f"[link]({href})")
            self._pending_href = None

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self.title = (self.title or "") + data
        elif self._heading is not None:
            self._heading_text.append(data)
        elif self._in_body and not self._skip_depth:
            stripped = data.strip()
            if stripped:
                self.body.append(stripped)


def parse_html(text: str) -> tuple[Frontmatter, str, bool]:
    """Return (frontmatter-equivalent, body, is_redirect) for a rendered page."""
    parser = _PageParser()
    parser.feed(text)
    parser.close()

    robots = parser.robots or ""
    fields = {
        "title": " ".join((parser.title or "").split()) or None,
        "description": parser.description or None,
        "canonical": parser.canonical or None,
        "noindex": "noindex" in robots,
        "image": parser.og_image or None,
        "imageAlt": parser.og_image_alt or None,
    }
    frontmatter, _ = Frontmatter.parse(
        {k: v for k, v in fields.items() if v not in (None, False)})
    return frontmatter, "\n\n".join(parser.body), parser.is_redirect


def url_for(path: Path, dist: Path) -> str:
    """The URL a built file is served at, which is what a reader will see."""
    rel = path.relative_to(dist)
    if rel.name == "index.html":
        parent = rel.parent.as_posix()
        return "/" if parent == "." else f"/{parent}/"
    return f"/{rel.with_suffix('').as_posix()}/"


def iter_built_pages(dist_dir: str | os.PathLike[str]) -> Iterator[Page]:
    """Yield a Page per rendered HTML file under `dist_dir`.

    Redirect stubs are skipped: Astro emits one per aliased route, they carry a
    meta refresh and nothing else, and auditing them would report a missing
    description on every alias a site has.
    """
    dist = Path(dist_dir)
    for dirpath, dirnames, filenames in os.walk(dist):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        here = Path(dirpath)
        for name in sorted(filenames):
            if not name.endswith(".html"):
                continue
            path = here / name
            url = url_for(path, dist)
            frontmatter, body, is_redirect = parse_html(
                path.read_text(encoding="utf-8", errors="replace"))
            if is_redirect:
                continue

            segments = [s for s in url.strip("/").split("/") if s]
            parse_findings: tuple[Finding, ...] = ()
            yield Page(
                collection=segments[0] if len(segments) > 1 else "",
                slug="/".join(segments[1:]) if len(segments) > 1 else (
                    segments[0] if segments else "index"),
                url=url,
                path=str(path),
                frontmatter=frontmatter,
                body=body,
                origin=BUILD,
                parse_findings=parse_findings,
            )
