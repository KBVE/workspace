"""Whole-site SEO auditing for Astro content collections.

Static frontmatter and MDX analysis: it reads the files a site is authored
from, so it runs in CI with no build, no browser and no network. What it cannot
see -- rendered output, Core Web Vitals, what search engines actually did with
a page -- belongs to other tools, and the page-keyed JSON this emits is shaped
to be enriched by them rather than replaced.

Point it at a content directory::

    kbve-seo-audit  --content apps/website/example.com/src/content
    kbve-seo-report --content apps/website/example.com/src/content --rule desc-length

Thresholds and per-collection switches live in a ``seo.toml`` the site owns,
found automatically beside the content or at the project root. Without one the
built-in defaults apply, and those are limited to what is true of any indexed
page -- a title, a description that survives the search result, headings that
descend, images with alt text.
"""

# Exported as audit_content, not audit: `from kbve.seo import audit`
# would otherwise be ambiguous with the kbve.seo.audit module that
# holds it, and which of the two you got would depend on import order.
from .audit import audit_build, audit_content, audit_pages  # noqa: F401
from .html import iter_built_pages, parse_html  # noqa: F401
from .config import ProfileError, find_config, load_profiles  # noqa: F401
from .models import (AuditResult, Finding, Frontmatter, Page,  # noqa: F401
                     ProfileSet, SeoProfile)
from .pages import find_content_dir, iter_pages  # noqa: F401
from .rules import RULES, build_ctx  # noqa: F401

__all__ = [
    "audit_build",
    "audit_content",
    "audit_pages",
    "AuditResult",
    "Finding",
    "Frontmatter",
    "Page",
    "ProfileError",
    "ProfileSet",
    "SeoProfile",
    "RULES",
    "build_ctx",
    "find_config",
    "find_content_dir",
    "iter_built_pages",
    "iter_pages",
    "parse_html",
    "load_profiles",
]
