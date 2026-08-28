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
from .models import (AuditResult, AuditSummary, CollectionSummary, PageAudit,
                     ProfileSet)
from .pages import find_content_dir, iter_pages
from .rules import RULES, build_ctx


def audit_content(content_dir: str | os.PathLike[str],
                  profiles: ProfileSet | None = None,
                  only: str | None = None) -> AuditResult:
    """Audit every page under `content_dir`."""
    pages = list(iter_pages(content_dir, only=only))
    ctx = build_ctx(pages)
    profiles = profiles or ProfileSet()

    result = AuditResult(summary=AuditSummary(pages=len(pages)))
    for page in pages:
        profile = profiles.for_collection(page.collection)
        # Parse findings come first: a mistyped title is why the title rule
        # then reports it missing, and the order is what makes that readable.
        findings = list(page.parse_findings)
        for rule in RULES:
            findings.extend(rule(page, ctx, profile))

        collection = result.summary.collections.setdefault(
            page.collection, CollectionSummary())
        collection.pages += 1
        for finding in findings:
            setattr(result.summary, finding.severity,
                    getattr(result.summary, finding.severity) + 1)
            setattr(collection, finding.severity,
                    getattr(collection, finding.severity) + 1)

        url = f"/{page.collection}/{page.slug}/"
        result.pages[url] = PageAudit(
            collection=page.collection, path=page.path, findings=findings)
    return result


def resolve(args: argparse.Namespace) -> tuple[Path, ProfileSet]:
    """Content directory and profiles, from the arguments and the site."""
    content_dir = find_content_dir(args.content, args.root)
    config = Path(args.profiles) if args.profiles else find_config(content_dir)
    return content_dir, load_profiles(config)


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--content", default=None,
                        help="content directory (e.g. <site>/src/content)")
    parser.add_argument("--root", default=None,
                        help="search here for a single src/content")
    parser.add_argument("--profiles", default=None,
                        help="profile TOML (default: seo.toml beside the site)")
    parser.add_argument("--only", default=None,
                        help="restrict to one collection")


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

    result = audit_content(content_dir, profiles, only=args.only)
    if args.json:
        Path(args.json).write_text(
            result.model_dump_json(indent=2), encoding="utf-8")

    s = result.summary
    print(f"audited {s.pages} pages in {content_dir}: "
          f"{s.error} error, {s.warn} warn, {s.info} info")
    return 1 if s.error else 0


if __name__ == "__main__":
    sys.exit(main())
