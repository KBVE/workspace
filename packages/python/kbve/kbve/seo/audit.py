"""Run the rule registry over a site's content.

    kbve-seo-audit --content apps/website/example.com/src/content [--json out.json]

Exit status is non-zero when any error-severity finding is present, so the same
command that reports also gates CI.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from .config import ProfileError, find_config, load_profiles
from .html import iter_built_pages
from .models import (AuditResult, AuditSummary, CollectionSummary, Page,
                     PageAudit, ProfileSet)
from .pages import find_content_dir, iter_pages
from .rules import RULES, applies, build_ctx


def audit_pages(pages: list[Page],
                profiles: ProfileSet | None = None) -> AuditResult:
    """Audit an already-loaded set of pages, whatever they were read from."""
    profiles = profiles or ProfileSet()
    ctx = build_ctx(pages)
    result = AuditResult(summary=AuditSummary(pages=len(pages)))
    for page in pages:
        profile = profiles.for_collection(page.collection)
        # Parse findings come first: a mistyped title is why the title rule
        # then reports it missing, and the order is what makes that readable.
        findings = list(page.parse_findings)
        for rule in RULES:
            if applies(rule, page):
                findings.extend(rule(page, ctx, profile))

        collection = result.summary.collections.setdefault(
            page.collection, CollectionSummary())
        collection.pages += 1
        for finding in findings:
            setattr(result.summary, finding.severity,
                    getattr(result.summary, finding.severity) + 1)
            setattr(collection, finding.severity,
                    getattr(collection, finding.severity) + 1)

        result.pages[page.url] = PageAudit(
            collection=page.collection, path=page.path, findings=findings)
    return result


def audit_content(content_dir: str | os.PathLike[str],
                  profiles: ProfileSet | None = None,
                  only: str | None = None) -> AuditResult:
    """Audit the source a site is authored from."""
    return audit_pages(list(iter_pages(content_dir, only=only)), profiles)


def audit_build(dist_dir: str | os.PathLike[str],
                profiles: ProfileSet | None = None) -> AuditResult:
    """Audit the HTML a site actually ships.

    Sees what the layout computed -- the wrapped title, the fallback
    description, the derived canonical -- which source mode cannot. Costs a
    build, and its findings name generated files.
    """
    return audit_pages(list(iter_built_pages(dist_dir)), profiles)


def resolve(args: argparse.Namespace) -> tuple[Path, ProfileSet]:
    """The directory to audit and the profiles to audit it with.

    --dist takes precedence over --content when both are given, because asking
    for both is asking for the mode that sees more.
    """
    if getattr(args, "dist", None):
        target = Path(args.dist)
        if not target.is_dir():
            raise FileNotFoundError(f"no build directory at {target}")
        # seo.toml sits at the project root, which is dist/'s parent.
        config = Path(args.profiles) if args.profiles else find_config(target)
        return target, load_profiles(config)

    content_dir = find_content_dir(args.content, args.root)
    config = Path(args.profiles) if args.profiles else find_config(content_dir)
    return content_dir, load_profiles(config)


def run(args: argparse.Namespace, target: Path,
        profiles: ProfileSet) -> AuditResult:
    if getattr(args, "dist", None):
        return audit_build(target, profiles)
    return audit_content(target, profiles, only=args.only)


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--content", default=None,
                        help="content directory (e.g. <site>/src/content)")
    parser.add_argument("--dist", default=None,
                        help="built output to audit instead of the source; "
                             "sees the rendered title, description and canonical")
    parser.add_argument("--root", default=None,
                        help="search here for a single src/content")
    parser.add_argument("--profiles", default=None,
                        help="profile TOML (default: seo.toml beside the site)")
    parser.add_argument("--only", default=None,
                        help="restrict to one collection (source mode)")


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="kbve-seo-audit",
        description="Audit the SEO metadata of an Astro content collection.")
    add_common_arguments(parser)
    parser.add_argument("--json", default=None, help="write findings to this path")
    args = parser.parse_args()

    try:
        content_dir, profiles = resolve(args)
    except (FileNotFoundError, ProfileError) as exc:
        print(f"kbve-seo-audit: {exc}", file=sys.stderr)
        return 2

    result = run(args, content_dir, profiles)
    if args.json:
        Path(args.json).write_text(
            result.model_dump_json(indent=2), encoding="utf-8")

    s = result.summary
    print(f"audited {s.pages} pages in {content_dir}: "
          f"{s.error} error, {s.warn} warn, {s.info} info")
    return 1 if s.error else 0


if __name__ == "__main__":
    sys.exit(main())
