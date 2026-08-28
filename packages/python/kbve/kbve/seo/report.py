"""Human summary of an audit run. Read-only.

    kbve-seo-report --content <dir> [--rule <rule-id>]
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter

from .audit import add_common_arguments, audit_content, resolve
from .config import ProfileError


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="kbve-seo-report",
        description="Summarize an SEO audit.")
    add_common_arguments(parser)
    parser.add_argument("--rule", default=None,
                        help="list the pages hitting this rule")
    args = parser.parse_args()

    try:
        content_dir, profiles = resolve(args)
    except (FileNotFoundError, ProfileError) as exc:
        print(f"kbve-seo-report: {exc}", file=sys.stderr)
        return 2

    result = audit_content(content_dir, profiles, only=args.only)
    s = result.summary

    print("== SEO audit ==")
    print(f"{content_dir}")
    print(f"pages {s.pages} | error {s.error} | warn {s.warn} | info {s.info}\n")

    print("per collection:")
    for name, c in sorted(s.collections.items(),
                          key=lambda kv: -(kv[1].error + kv[1].warn)):
        print(f"  {name:<14} pages {c.pages:<4} error {c.error:<3} "
              f"warn {c.warn:<3} info {c.info:<3}")

    counts = Counter(f.rule for page in result.pages.values() for f in page.findings)
    if counts:
        print("\nby rule:")
        for rule, n in counts.most_common():
            print(f"  {rule:<20} {n}")

    if args.rule:
        print(f"\npages hitting {args.rule}:")
        for url, page in sorted(result.pages.items()):
            for finding in page.findings:
                if finding.rule == args.rule:
                    print(f"  {url:<40} {finding.message}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
