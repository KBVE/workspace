"""The rule registry.

A rule is ``(page, ctx, profile) -> list[Finding]``. Registering one means
appending to :data:`RULES`; nothing else changes. `ctx` carries whole-site
state built once per run, which is what lets a rule about one page know about
the others.

Every rule that encodes a site's convention rather than a property of the web
reads a switch off the profile and returns nothing when it is off. Upstream
two of them did not, and pointing the auditor at a second site reported every
page as failing for want of frontmatter that site had never defined.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Callable

from .models import ERROR, INFO, WARN, Finding, Page, SeoProfile

Ctx = dict[str, Any]
Rule = Callable[[Page, Ctx, SeoProfile], list[Finding]]

# Markdown images and links, ignoring the escaped and code-fenced cases that a
# real parser would catch and a regex cannot. This is a linter for authored
# prose, not a renderer.
_IMAGE = re.compile(r"!\[(?P<alt>[^\]]*)\]\((?P<src>[^)\s]*)")
_LINK = re.compile(r"(?<!!)\[(?P<text>[^\]]*)\]\((?P<href>[^)\s]*)")
_HEADING = re.compile(r"^(?P<hashes>#{1,6})\s+\S", re.M)
_FENCE = re.compile(r"^```.*?^```", re.M | re.S)


def _body_without_code(page: Page) -> str:
    """Fenced blocks hold example markdown; linting it reports the example."""
    return _FENCE.sub("", page.body)


# ── length and presence ──────────────────────────────────────────────

def rule_title_length(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    title = page.frontmatter.title
    if not title:
        if not profile.require_title:
            return []
        return [Finding(rule="title-length", severity=ERROR, message="missing title")]
    n = len(title)
    if n < profile.title_min:
        return [Finding(rule="title-length", severity=WARN,
                        message=f"title {n} chars < {profile.title_min}")]
    if n > profile.title_max:
        over = f"title {n} chars > {profile.title_max} (truncated in search results)"
        return [Finding(rule="title-length", severity=WARN, message=over)]
    return []


def rule_desc_length(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    desc = page.frontmatter.description
    if not desc:
        if not profile.require_description:
            return []
        return [Finding(rule="desc-length", severity=ERROR,
                        message="missing description")]
    n = len(desc)
    if n < profile.desc_min:
        return [Finding(rule="desc-length", severity=WARN,
                        message=f"description {n} chars < {profile.desc_min}")]
    if n > profile.desc_max:
        over = (f"description {n} chars > {profile.desc_max} "
                "(truncated in search results)")
        return [Finding(rule="desc-length", severity=WARN, message=over)]
    return []


def rule_body_thin(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    floor = profile.body_min_chars
    if not floor:
        return []
    n = len(page.body.strip())
    if n < floor:
        return [Finding(rule="body-thin", severity=WARN,
                        message=f"body {n} chars < {floor}")]
    return []


# ── whole-site ───────────────────────────────────────────────────────

def rule_title_duplicate(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    if not profile.check_duplicates:
        return []
    title = page.frontmatter.title
    others = ctx["titles"].get(title, ()) if title else ()
    if len(others) > 1:
        return [Finding(rule="title-duplicate", severity=ERROR,
                        message=f"title shared with {len(others) - 1} other pages")]
    return []


def rule_desc_duplicate(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    if not profile.check_duplicates:
        return []
    desc = page.frontmatter.description
    others = ctx["descs"].get(desc, ()) if desc else ()
    if len(others) > 1:
        return [Finding(rule="desc-duplicate", severity=ERROR,
                        message=f"description shared with {len(others) - 1} other pages")]
    return []


# ── body structure ───────────────────────────────────────────────────

def rule_heading_order(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    """Heading levels must descend one at a time.

    A jump from ## to #### leaves a hole in the document outline, which is what
    both screen readers and result snippets are built from. Reported once per
    page: the first skip is the fix, and the rest usually follow from it.
    """
    if not profile.check_headings:
        return []
    levels = [len(m.group("hashes"))
              for m in _HEADING.finditer(_body_without_code(page))]
    previous = None
    for level in levels:
        if previous is not None and level > previous + 1:
            return [Finding(rule="heading-order", severity=WARN,
                            message=f"heading jumps from h{previous} to h{level}")]
        previous = level
    return []


def rule_heading_single_h1(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    """The title is the h1, so a second one in the body competes with it."""
    if not profile.check_headings:
        return []
    count = sum(1 for m in _HEADING.finditer(_body_without_code(page))
                if len(m.group("hashes")) == 1)
    if count and page.frontmatter.title:
        return [Finding(rule="heading-single-h1", severity=WARN,
                        message=f"{count} h1 in the body; the title is already one")]
    if count > 1:
        return [Finding(rule="heading-single-h1", severity=WARN,
                        message=f"{count} h1 headings; a page has one")]
    return []


def rule_image_alt(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    """Every body image needs alt text.

    An empty alt is valid HTML for a decorative image, but in authored prose it
    is almost always an omission, so it is reported and silenced per page by
    turning the check off in that collection's profile.
    """
    if not profile.check_image_alt:
        return []
    missing = [m.group("src") or "?"
               for m in _IMAGE.finditer(_body_without_code(page))
               if not m.group("alt").strip()]
    if missing:
        shown = ", ".join(missing[:3])
        more = f" (+{len(missing) - 3} more)" if len(missing) > 3 else ""
        return [Finding(rule="image-alt", severity=WARN,
                        message=f"{len(missing)} image(s) without alt text: {shown}{more}")]
    return []


def rule_internal_links(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    """Relative links to content files that are not there.

    Only file-relative links are checked -- ``./other.mdx``, ``../guide`` --
    because those resolve on disk. Site-absolute links like ``/about/`` are
    left alone: mapping one to a file needs the site's routing, and guessing at
    it would report working links as broken.
    """
    if not profile.check_internal_links:
        return []
    known: set[Path] = ctx["files"]
    here = Path(page.path).parent
    broken = []
    for match in _LINK.finditer(_body_without_code(page)):
        href = match.group("href").split("#")[0].split("?")[0]
        if not href or not href.startswith((".", "../")):
            continue
        target = (here / href).resolve()
        if target in known or target.exists():
            continue
        if any((target.with_suffix(s)) in known for s in (".md", ".mdx")):
            continue
        broken.append(href)
    if broken:
        return [Finding(rule="internal-link", severity=ERROR,
                        message=f"broken relative link(s): {', '.join(broken[:3])}")]
    return []


# ── indexability ─────────────────────────────────────────────────────

def rule_noindex(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    """Surfaced, not judged: noindex is usually deliberate and never visible."""
    if page.frontmatter.noindex:
        return [Finding(rule="noindex", severity=INFO,
                        message="excluded from search results (noindex)")]
    return []


def rule_draft(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    if page.frontmatter.draft:
        return [Finding(rule="draft", severity=INFO, message="draft")]
    return []


def rule_canonical_absolute(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    """A relative canonical resolves against whatever page emitted it.

    That makes it a no-op at best and a self-reference loop at worst, and
    neither is visible in the rendered page.
    """
    canonical = page.frontmatter.canonical
    if canonical and not canonical.startswith(("http://", "https://")):
        return [Finding(rule="canonical-absolute", severity=ERROR,
                        message=f"canonical is not an absolute URL: {canonical}")]
    return []


def rule_social_image(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    if not profile.require_social_image:
        return []
    fm = page.frontmatter
    if not fm.image:
        return [Finding(rule="social-image", severity=WARN,
                        message="no social card image")]
    if not fm.image_alt:
        return [Finding(rule="social-image", severity=WARN,
                        message="social card image has no alt text")]
    return []


# ── per-site conventions ─────────────────────────────────────────────

def rule_tags_present(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    if not profile.require_tags:
        return []
    if not page.frontmatter.tags:
        return [Finding(rule="tags-present", severity=WARN, message="no tags")]
    return []


def rule_sem_tracked(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    if not profile.require_sem:
        return []
    if page.frontmatter.sem is None:
        return [Finding(rule="sem-tracked", severity=INFO,
                        message="not yet SEO-audited (sem unset)")]
    return []


def rule_software_jsonld(page: Page, ctx: Ctx, profile: SeoProfile) -> list[Finding]:
    """Software JSON-LD is derived from source_path / app_name.

    A page missing both ships no SoftwareSourceCode node, which is invisible
    in the rendered page and absent from the result.
    """
    if not profile.require_software_jsonld:
        return []
    fm = page.frontmatter
    if not (fm.source_path or fm.app_name):
        return [Finding(rule="software-jsonld", severity=WARN,
                        message="no source_path/app_name -> no SoftwareSourceCode JSON-LD")]
    return []


RULES: list[Rule] = [
    rule_title_length,
    rule_desc_length,
    rule_body_thin,
    rule_title_duplicate,
    rule_desc_duplicate,
    rule_heading_order,
    rule_heading_single_h1,
    rule_image_alt,
    rule_internal_links,
    rule_noindex,
    rule_draft,
    rule_canonical_absolute,
    rule_social_image,
    rule_tags_present,
    rule_sem_tracked,
    rule_software_jsonld,
]


def build_ctx(pages: list[Page]) -> Ctx:
    """Whole-site state the cross-page rules read."""
    titles: dict[str, list[str]] = {}
    descs: dict[str, list[str]] = {}
    for page in pages:
        title = page.frontmatter.title
        desc = page.frontmatter.description
        if title:
            titles.setdefault(title, []).append(page.slug)
        if desc:
            descs.setdefault(desc, []).append(page.slug)
    return {
        "titles": titles,
        "descs": descs,
        "files": {Path(p.path).resolve() for p in pages},
    }
