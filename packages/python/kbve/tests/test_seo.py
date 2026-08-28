"""Tests for kbve.seo.

The upstream module had 2.5K of tests against an API that assumed one site.
These cover the parts that make it work against any of them: the typed
boundaries, the profile file, and the fact that a site-specific rule stays
quiet on a site that never adopted the convention.
"""

from __future__ import annotations

import json
import textwrap
from pathlib import Path

import pytest
from pydantic import ValidationError

from kbve.seo import (Frontmatter, ProfileError, ProfileSet, SeoProfile,
                      audit_content, find_config, find_content_dir, iter_pages,
                      load_profiles)
from kbve.seo import rules as R


def write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(text).lstrip(), encoding="utf-8")
    return path


def page(body: str = "", **frontmatter):
    """A Page built straight from values, bypassing the filesystem."""
    from kbve.seo.models import Page
    fm, _ = Frontmatter.parse(frontmatter)
    return Page(collection="pages", slug="p", path="/tmp/p.mdx",
                frontmatter=fm, body=body)


# ── Frontmatter ──────────────────────────────────────────────────────

def test_frontmatter_keeps_unknown_keys():
    """Every site invents its own fields; rejecting them would help no one."""
    fm, findings = Frontmatter.parse({"title": "T", "rentearthOnly": 3})
    assert findings == []
    assert fm.title == "T"


def test_frontmatter_strips_whitespace():
    fm, _ = Frontmatter.parse({"title": "  T  ", "description": "\n"})
    assert fm.title == "T"
    assert fm.description is None, "whitespace-only is absent, not present"


def test_frontmatter_accepts_the_astro_alias():
    fm, findings = Frontmatter.parse({"imageAlt": "a cat"})
    assert findings == []
    assert fm.image_alt == "a cat"


def test_frontmatter_reports_a_mistyped_field_as_mistyped():
    """Upstream a `title: 123` was indistinguishable from a missing title."""
    fm, findings = Frontmatter.parse({"title": 123, "description": "ok"})
    assert fm.title is None
    assert fm.description == "ok", "one bad field must not discard the others"
    assert [f.rule for f in findings] == ["frontmatter-type"]
    assert "title" in findings[0].message


def test_frontmatter_reports_every_bad_field_not_just_the_first():
    _, findings = Frontmatter.parse({"title": 1, "tags": "a,b"})
    fields = {f.message.split(":")[0] for f in findings}
    assert fields == {"title", "tags"}


def test_frontmatter_rejects_a_non_mapping():
    fm, findings = Frontmatter.parse(["not", "a", "mapping"])
    assert fm.title is None
    assert findings[0].rule == "frontmatter-shape"


# ── SeoProfile / ProfileSet ──────────────────────────────────────────

def test_profile_defaults_are_site_agnostic():
    """The conventions of one site must not be another site's failures."""
    p = SeoProfile()
    assert p.require_tags is False
    assert p.require_sem is False
    assert p.require_software_jsonld is False
    assert p.require_social_image is False
    # What is true of any indexed page stays on.
    assert p.require_title and p.require_description and p.check_headings


def test_profile_rejects_an_unknown_key():
    """A misspelled threshold silently ignored is a check that never runs."""
    with pytest.raises(ValidationError):
        SeoProfile(desc_minimum=50)


def test_profile_rejects_an_inverted_window():
    with pytest.raises(ValidationError) as excinfo:
        SeoProfile(desc_min=200, desc_max=100)
    assert "below desc_min" in str(excinfo.value)


def test_profile_set_falls_back_to_default():
    ps = ProfileSet(default=SeoProfile(desc_min=1),
                    collections={"blog": SeoProfile(desc_min=99)})
    assert ps.for_collection("blog").desc_min == 99
    assert ps.for_collection("anything-else").desc_min == 1


# ── config ───────────────────────────────────────────────────────────

def test_load_profiles_without_a_file_is_the_defaults():
    assert load_profiles(None).default == SeoProfile()


def test_load_profiles_reads_collections(tmp_path):
    cfg = write(tmp_path / "seo.toml", """
        [default]
        desc_min = 40

        [collections.blog]
        body_min_chars = 800
        require_tags = true
    """)
    ps = load_profiles(cfg)
    assert ps.default.desc_min == 40
    assert ps.for_collection("blog").require_tags is True
    assert ps.for_collection("blog").body_min_chars == 800


def test_load_profiles_names_the_bad_field(tmp_path):
    cfg = write(tmp_path / "seo.toml", """
        [default]
        desc_minimum = 40
    """)
    with pytest.raises(ProfileError) as excinfo:
        load_profiles(cfg)
    assert "desc_minimum" in str(excinfo.value)


def test_load_profiles_reports_malformed_toml(tmp_path):
    cfg = write(tmp_path / "seo.toml", "[default\n")
    with pytest.raises(ProfileError):
        load_profiles(cfg)


def test_find_config_looks_beside_the_content_and_at_the_project_root(tmp_path):
    content = tmp_path / "site" / "src" / "content"
    content.mkdir(parents=True)
    assert find_config(content) is None

    cfg = write(tmp_path / "site" / "seo.toml", "[default]\n")
    assert find_config(content) == cfg


def test_find_config_stops_below_a_sibling_project(tmp_path):
    """Picking up another site's thresholds is worse than having none."""
    write(tmp_path / "seo.toml", "[default]\ndesc_min = 1\n")
    content = tmp_path / "apps" / "site" / "src" / "content"
    content.mkdir(parents=True)
    assert find_config(content) is None


# ── pages ────────────────────────────────────────────────────────────

def test_iter_pages_uses_the_directory_as_the_collection(tmp_path):
    write(tmp_path / "docs" / "a.mdx", "---\ntitle: A\n---\nbody\n")
    write(tmp_path / "blog" / "b.md", "---\ntitle: B\n---\nbody\n")
    found = {(p.collection, p.slug) for p in iter_pages(tmp_path)}
    assert found == {("docs", "a"), ("blog", "b")}


def test_iter_pages_keeps_the_path_below_the_collection_in_the_slug(tmp_path):
    """`pages/en/about` and `pages/es/about` are translations, not duplicates."""
    write(tmp_path / "pages" / "en" / "about.mdx", "---\ntitle: About\n---\n")
    write(tmp_path / "pages" / "es" / "about.mdx", "---\ntitle: Acerca\n---\n")
    slugs = sorted(p.slug for p in iter_pages(tmp_path))
    assert slugs == ["en/about", "es/about"]


def test_iter_pages_restricts_to_one_collection(tmp_path):
    write(tmp_path / "docs" / "a.mdx", "---\ntitle: A\n---\n")
    write(tmp_path / "blog" / "b.mdx", "---\ntitle: B\n---\n")
    assert [p.slug for p in iter_pages(tmp_path, only="blog")] == ["b"]


def test_iter_pages_survives_unparseable_frontmatter(tmp_path):
    write(tmp_path / "docs" / "bad.mdx", "---\ntitle: [unclosed\n---\nbody\n")
    found = list(iter_pages(tmp_path))
    assert len(found) == 1, "one bad page must not stop the walk"
    assert found[0].parse_findings[0].rule == "frontmatter-parse"


def test_iter_pages_ignores_non_content_files(tmp_path):
    write(tmp_path / "docs" / "a.mdx", "---\ntitle: A\n---\n")
    write(tmp_path / "docs" / "notes.txt", "not content")
    assert len(list(iter_pages(tmp_path))) == 1


# ── find_content_dir ─────────────────────────────────────────────────

def test_find_content_dir_uses_an_explicit_path(tmp_path):
    (tmp_path / "whatever").mkdir()
    assert find_content_dir(tmp_path / "whatever") == tmp_path / "whatever"


def test_find_content_dir_finds_a_project_root(tmp_path):
    content = tmp_path / "src" / "content"
    content.mkdir(parents=True)
    assert find_content_dir(None, tmp_path) == content


def test_find_content_dir_refuses_to_guess_between_sites(tmp_path):
    """Two sites in a workspace is ambiguous, not a default worth picking."""
    for name in ("alpha", "beta"):
        (tmp_path / "apps" / "website" / name / "src" / "content").mkdir(parents=True)
    with pytest.raises(FileNotFoundError) as excinfo:
        find_content_dir(None, tmp_path)
    assert "--content" in str(excinfo.value)


def test_find_content_dir_finds_the_only_site_in_a_workspace(tmp_path):
    content = tmp_path / "apps" / "website" / "solo" / "src" / "content"
    content.mkdir(parents=True)
    assert find_content_dir(None, tmp_path) == content


# ── rules: universal ─────────────────────────────────────────────────

def run(rule, p, ctx=None, profile=None):
    return rule(p, ctx or {"titles": {}, "descs": {}, "files": set()},
                profile or SeoProfile())


def test_missing_title_is_an_error():
    assert run(R.rule_title_length, page())[0].severity == "error"


def test_long_description_says_it_will_be_truncated():
    finding = run(R.rule_desc_length, page(description="x" * 200))[0]
    assert "truncated" in finding.message


def test_heading_order_flags_a_skipped_level():
    finding = run(R.rule_heading_order, page("## Two\n\n#### Four\n"))[0]
    assert "h2 to h4" in finding.message


def test_heading_order_accepts_descending_then_returning():
    assert run(R.rule_heading_order, page("## A\n\n### B\n\n## C\n")) == []


def test_heading_rules_ignore_fenced_code():
    """A markdown example inside a fence is documentation, not structure."""
    body = "## Real\n\n```md\n# Not a heading\n#### Nor this\n```\n"
    assert run(R.rule_heading_order, page(body)) == []
    assert run(R.rule_heading_single_h1, page(body, title="T")) == []


def test_body_h1_competes_with_the_title():
    finding = run(R.rule_heading_single_h1, page("# Another\n", title="T"))[0]
    assert finding.rule == "heading-single-h1"


def test_image_without_alt_is_reported_with_its_source():
    finding = run(R.rule_image_alt, page("![](/img/a.png)\n"))[0]
    assert "/img/a.png" in finding.message


def test_image_with_alt_passes():
    assert run(R.rule_image_alt, page("![a cat](/img/a.png)\n")) == []


def test_canonical_must_be_absolute():
    assert run(R.rule_canonical_absolute, page(canonical="/about/"))[0].severity == "error"
    assert run(R.rule_canonical_absolute, page(canonical="https://x.dev/a")) == []


def test_noindex_and_draft_are_surfaced_not_judged():
    assert run(R.rule_noindex, page(noindex=True))[0].severity == "info"
    assert run(R.rule_draft, page(draft=True))[0].severity == "info"


# ── rules: whole-site ────────────────────────────────────────────────

def test_duplicate_titles_are_an_error():
    ctx = {"titles": {"Same": ["a", "b"]}, "descs": {}, "files": set()}
    finding = run(R.rule_title_duplicate, page(title="Same"), ctx)[0]
    assert "1 other pages" in finding.message


def test_broken_relative_link_is_an_error(tmp_path):
    from kbve.seo.models import Page
    fm, _ = Frontmatter.parse({"title": "T"})
    p = Page(collection="docs", slug="a", path=str(tmp_path / "a.mdx"),
             frontmatter=fm, body="see [there](./gone.mdx)\n")
    ctx = {"titles": {}, "descs": {}, "files": {(tmp_path / "a.mdx").resolve()}}
    assert run(R.rule_internal_links, p, ctx)[0].rule == "internal-link"


def test_relative_link_to_a_real_page_passes(tmp_path):
    from kbve.seo.models import Page
    target = write(tmp_path / "b.mdx", "---\ntitle: B\n---\n")
    fm, _ = Frontmatter.parse({"title": "T"})
    p = Page(collection="docs", slug="a", path=str(tmp_path / "a.mdx"),
             frontmatter=fm, body="see [there](./b.mdx)\n")
    ctx = {"titles": {}, "descs": {}, "files": {target.resolve()}}
    assert run(R.rule_internal_links, p, ctx) == []


def test_site_absolute_links_are_left_alone(tmp_path):
    """Mapping /about/ to a file needs the site's routing; guessing is worse."""
    from kbve.seo.models import Page
    fm, _ = Frontmatter.parse({"title": "T"})
    p = Page(collection="docs", slug="a", path=str(tmp_path / "a.mdx"),
             frontmatter=fm, body="see [there](/about/)\n")
    ctx = {"titles": {}, "descs": {}, "files": set()}
    assert run(R.rule_internal_links, p, ctx) == []


# ── rules: per-site conventions stay off ─────────────────────────────

@pytest.mark.parametrize("rule", [
    R.rule_tags_present,
    R.rule_sem_tracked,
    R.rule_software_jsonld,
    R.rule_social_image,
])
def test_convention_rules_are_silent_by_default(rule):
    """This is the whole point of the port: another site is not a failing site."""
    assert run(rule, page(title="A title that is long enough")) == []


def test_convention_rules_fire_when_a_profile_asks():
    profile = SeoProfile(require_tags=True, require_social_image=True)
    assert run(R.rule_tags_present, page(), profile=profile)[0].rule == "tags-present"
    assert run(R.rule_social_image, page(), profile=profile)[0].rule == "social-image"


def test_social_image_without_alt_is_still_a_finding():
    profile = SeoProfile(require_social_image=True)
    finding = run(R.rule_social_image, page(image="/og.png"), profile=profile)[0]
    assert "alt" in finding.message


# ── audit ────────────────────────────────────────────────────────────

def test_audit_counts_by_severity_and_collection(tmp_path):
    write(tmp_path / "docs" / "good.mdx", """
        ---
        title: A title long enough to pass
        description: %s
        ---
        Body copy.
    """ % ("d" * 80))
    write(tmp_path / "docs" / "bad.mdx", "---\ntitle: x\n---\n")

    result = audit_content(tmp_path)
    assert result.summary.pages == 2
    assert result.summary.error >= 1, "bad.mdx has no description"
    assert result.summary.collections["docs"].pages == 2


def test_audit_applies_the_profile_for_the_collection(tmp_path):
    write(tmp_path / "blog" / "a.mdx", "---\ntitle: A title long enough\n"
          "description: %s\n---\nshort\n" % ("d" * 80))
    profiles = ProfileSet(collections={"blog": SeoProfile(body_min_chars=500)})
    result = audit_content(tmp_path, profiles)
    rules = {f.rule for p in result.pages.values() for f in p.findings}
    assert "body-thin" in rules
    assert "body-thin" not in {
        f.rule for p in audit_content(tmp_path).pages.values() for f in p.findings}


def test_audit_reports_parse_findings_before_rule_findings(tmp_path):
    write(tmp_path / "docs" / "a.mdx", "---\ntitle: 123\n---\n")
    result = audit_content(tmp_path)
    findings = next(iter(result.pages.values())).findings
    assert findings[0].rule == "frontmatter-type"


def test_audit_result_serialises_to_the_page_keyed_contract(tmp_path):
    write(tmp_path / "docs" / "a.mdx", "---\ntitle: x\n---\n")
    payload = json.loads(audit_content(tmp_path).model_dump_json())
    assert list(payload["pages"]) == ["/docs/a/"]
    assert payload["summary"]["pages"] == 1
    assert "findings" in payload["pages"]["/docs/a/"]


def test_audit_of_an_empty_tree_is_clean(tmp_path):
    (tmp_path / "docs").mkdir()
    result = audit_content(tmp_path)
    assert result.summary.pages == 0 and result.summary.error == 0


# ── the real site in this workspace ──────────────────────────────────

def test_audits_rentearth_without_configuration():
    """The agnostic claim, against a site whose schema this was not written for.

    astro-kbve has tags and a `sem` field; rentearth.com has neither, and has
    image/imageAlt/canonical/noindex, which astro-kbve does not. Upstream every
    page here would have been reported for missing tags.
    """
    content = (Path(__file__).resolve().parents[4]
               / "apps" / "website" / "rentearth.com" / "src" / "content")
    if not content.is_dir():
        pytest.skip("rentearth.com is not in this checkout")

    result = audit_content(content, load_profiles(find_config(content)))
    assert result.summary.pages >= 1
    reported = {f.rule for p in result.pages.values() for f in p.findings}
    assert not (reported & {"tags-present", "sem-tracked", "software-jsonld"})


# ── the command line ─────────────────────────────────────────────────
#
# The exit status is the CI contract: 0 clean, 1 findings that block, 2 the
# tool could not run. Conflating the last two would turn a typo in a path into
# a failing SEO gate.

def _cli(monkeypatch, module, argv):
    import sys as _sys
    monkeypatch.setattr(_sys, "argv", [module.__name__, *argv])
    return module.main()


def test_audit_cli_exits_zero_on_a_clean_site(monkeypatch, tmp_path, capsys):
    from kbve.seo import audit as audit_mod
    write(tmp_path / "docs" / "a.mdx", """
        ---
        title: A title that is long enough
        description: %s
        ---
        Body copy.
    """ % ("d" * 80))
    assert _cli(monkeypatch, audit_mod, ["--content", str(tmp_path)]) == 0
    assert "audited 1 pages" in capsys.readouterr().out


def test_audit_cli_exits_one_when_a_page_has_an_error(monkeypatch, tmp_path):
    from kbve.seo import audit as audit_mod
    write(tmp_path / "docs" / "a.mdx", "---\ntitle: A title long enough here\n---\n")
    assert _cli(monkeypatch, audit_mod, ["--content", str(tmp_path)]) == 1


def test_audit_cli_exits_two_when_it_cannot_run(monkeypatch, tmp_path, capsys):
    """A bad path is a broken invocation, not a failing site."""
    from kbve.seo import audit as audit_mod
    code = _cli(monkeypatch, audit_mod, ["--content", str(tmp_path / "nope")])
    assert code == 2
    assert "no content directory" in capsys.readouterr().err


def test_audit_cli_exits_two_on_an_unusable_profile(monkeypatch, tmp_path, capsys):
    from kbve.seo import audit as audit_mod
    write(tmp_path / "docs" / "a.mdx", "---\ntitle: T\n---\n")
    bad = write(tmp_path / "seo.toml", "[default]\ndesc_minimum = 4\n")
    code = _cli(monkeypatch, audit_mod,
                ["--content", str(tmp_path), "--profiles", str(bad)])
    assert code == 2
    assert "desc_minimum" in capsys.readouterr().err


def test_audit_cli_writes_the_json_contract(monkeypatch, tmp_path):
    from kbve.seo import audit as audit_mod
    write(tmp_path / "docs" / "a.mdx", "---\ntitle: T\n---\n")
    out = tmp_path / "findings.json"
    _cli(monkeypatch, audit_mod,
         ["--content", str(tmp_path), "--json", str(out)])
    payload = json.loads(out.read_text())
    assert payload["pages"]["/docs/a/"]["findings"]


def test_audit_cli_finds_the_sites_own_profile(monkeypatch, tmp_path, capsys):
    """seo.toml beside the site is picked up with no --profiles flag."""
    from kbve.seo import audit as audit_mod
    content = tmp_path / "src" / "content"
    write(content / "docs" / "a.mdx",
          "---\ntitle: A title long enough\ndescription: %s\n---\nx\n" % ("d" * 80))
    write(tmp_path / "seo.toml",
          "[collections.docs]\nbody_min_chars = 500\n")
    _cli(monkeypatch, audit_mod, ["--content", str(content)])
    assert _cli(monkeypatch, audit_mod, ["--content", str(content)]) == 0

    result = audit_content(content, load_profiles(find_config(content)))
    rules = {f.rule for p in result.pages.values() for f in p.findings}
    assert "body-thin" in rules, "the site's own profile should have applied"


def test_report_cli_prints_the_breakdown(monkeypatch, tmp_path, capsys):
    from kbve.seo import report as report_mod
    write(tmp_path / "docs" / "a.mdx", "---\ntitle: x\n---\n")
    assert _cli(monkeypatch, report_mod, ["--content", str(tmp_path)]) == 0
    out = capsys.readouterr().out
    assert "== SEO audit ==" in out
    assert "per collection:" in out and "by rule:" in out


def test_report_cli_lists_pages_for_one_rule(monkeypatch, tmp_path, capsys):
    from kbve.seo import report as report_mod
    write(tmp_path / "docs" / "a.mdx", "---\ntitle: x\n---\n")
    _cli(monkeypatch, report_mod,
         ["--content", str(tmp_path), "--rule", "desc-length"])
    out = capsys.readouterr().out
    assert "pages hitting desc-length:" in out
    assert "/docs/a/" in out


def test_report_cli_is_read_only_about_a_bad_path(monkeypatch, tmp_path, capsys):
    from kbve.seo import report as report_mod
    assert _cli(monkeypatch, report_mod,
                ["--content", str(tmp_path / "nope")]) == 2
