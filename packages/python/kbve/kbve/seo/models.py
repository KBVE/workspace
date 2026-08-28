"""Typed models for the SEO auditor.

Pydantic is here for the two places data arrives from outside the package, and
deliberately not for the rest.

The first is page frontmatter, which is YAML written by hand. Upstream every
rule opened with ``isinstance(x, str)`` before it could trust a value, and a
``title: 123`` typo was indistinguishable from a missing title -- both produced
"missing title" and neither said why. :class:`Frontmatter` parses leniently and
hands back the type errors it found, so a mistyped field is reported as a
mistyped field.

The second is the profile file, which a site writes to describe itself.
Validating it means a typo in a threshold name is an error naming the field
rather than a KeyError raised from inside a rule three frames down.

:class:`Finding` and the result models stay plain because nothing outside
constructs them.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

Severity = Literal["error", "warn", "info"]

# Where a page was read from. The same rules run over both, because both
# produce the same shape -- but a handful of checks only mean something on one
# side, and this is what lets a rule say so.
Origin = Literal["source", "build"]

SOURCE: Origin = "source"
BUILD: Origin = "build"

ERROR: Severity = "error"
WARN: Severity = "warn"
INFO: Severity = "info"


class Finding(BaseModel):
    """One rule's verdict on one page."""

    model_config = ConfigDict(frozen=True)

    rule: str
    severity: Severity
    message: str


class SeoProfile(BaseModel):
    """Thresholds and switches for one collection.

    Every field that encodes a convention rather than a fact defaults to off.
    The upstream defaults assumed one site: `expect_tags` was on, and the `sem`
    frontmatter check ran unconditionally, so pointing the auditor at any other
    Astro site reported every page as failing for want of fields that site had
    never heard of.

    What stays on by default is what is true of any indexed page: it needs a
    title and a description, the description has a length search results
    truncate at, headings should descend, and an image needs alt text.
    """

    model_config = ConfigDict(extra="forbid")

    # Length windows. Search results truncate rather than wrap, so these are
    # about what survives to the SERP, not about writing style.
    title_min: int = 15
    title_max: int = 60
    desc_min: int = 70
    desc_max: int = 160
    body_min_chars: int = 0

    # What the layout wraps a frontmatter title in, e.g. "{title} — RentEarth".
    # Source mode measures the bare title otherwise, which under-counts every
    # page on the site by the length of the suffix -- rentearth.com's About
    # page is 5 characters of frontmatter and 17 of rendered <title>.
    #
    # An approximation, and only used in source mode: a layout may vary the
    # template per page (rentearth.com drops the suffix when the title already
    # is the site name), which a single string cannot express. Build mode does
    # not use it, because there the rendered title is the title.
    title_template: str | None = None

    # Universal expectations.
    require_title: bool = True
    require_description: bool = True
    check_headings: bool = True
    check_image_alt: bool = True
    check_internal_links: bool = True
    check_duplicates: bool = True

    # Per-site conventions, off unless a profile asks for them.
    require_tags: bool = False
    require_sem: bool = False
    require_social_image: bool = False
    require_software_jsonld: bool = False

    @field_validator("title_template")
    @classmethod
    def _template_has_a_slot(cls, v: str | None) -> str | None:
        if v is not None and "{title}" not in v:
            raise ValueError('title_template must contain "{title}"')
        return v

    @field_validator("title_max")
    @classmethod
    def _title_window_is_ordered(cls, v: int, info) -> int:
        lo = info.data.get("title_min")
        if lo is not None and v < lo:
            raise ValueError(f"title_max {v} is below title_min {lo}")
        return v

    @field_validator("desc_max")
    @classmethod
    def _desc_window_is_ordered(cls, v: int, info) -> int:
        lo = info.data.get("desc_min")
        if lo is not None and v < lo:
            raise ValueError(f"desc_max {v} is below desc_min {lo}")
        return v


class ProfileSet(BaseModel):
    """A site's profiles: one default, plus overrides per collection."""

    model_config = ConfigDict(extra="forbid")

    default: SeoProfile = Field(default_factory=SeoProfile)
    collections: dict[str, SeoProfile] = Field(default_factory=dict)

    def for_collection(self, collection: str) -> SeoProfile:
        return self.collections.get(collection, self.default)


class Frontmatter(BaseModel):
    """The frontmatter fields the rules read.

    Extra keys are kept rather than rejected: every site invents its own, and
    an auditor that refused to read a page because it carried an unknown key
    would be useless on the site it was pointed at.
    """

    model_config = ConfigDict(extra="allow", populate_by_name=True)

    title: str | None = None
    description: str | None = None
    tags: list[str] | None = None
    draft: bool = False
    noindex: bool = False
    canonical: str | None = None
    # Astro sites spell this imageAlt; the alias means both work.
    image: str | None = None
    image_alt: str | None = Field(default=None, alias="imageAlt")
    sem: Any | None = None
    source_path: str | None = None
    app_name: str | None = None

    @field_validator("title", "description", "canonical", mode="after")
    @classmethod
    def _strip(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        return v or None

    @classmethod
    def parse(cls, raw: object) -> tuple["Frontmatter", list[Finding]]:
        """Build a Frontmatter from raw YAML, reporting what would not fit.

        Returns the model plus one finding per field that was present but the
        wrong shape. Those fields are dropped rather than coerced: a `tags`
        that parsed as a string is not a tag list, and guessing which one the
        author meant would report a page as healthy on the strength of a guess.
        """
        if not isinstance(raw, dict):
            return cls(), [
                Finding(
                    rule="frontmatter-shape",
                    severity=ERROR,
                    message=f"frontmatter is {type(raw).__name__}, expected a mapping",
                )
            ]

        findings: list[Finding] = []
        cleaned = dict(raw)
        while True:
            try:
                return cls.model_validate(cleaned), findings
            except Exception as exc:  # pydantic.ValidationError
                errors = getattr(exc, "errors", None)
                if not callable(errors):
                    raise
                bad = errors()
                if not bad:
                    raise
                for err in bad:
                    field = str(err["loc"][0]) if err.get("loc") else "?"
                    findings.append(
                        Finding(
                            rule="frontmatter-type",
                            severity=ERROR,
                            message=f"{field}: {err.get('msg', 'invalid')}",
                        )
                    )
                    cleaned.pop(field, None)
                    # Aliased fields are reported under the field name, not the
                    # alias, so the alias has to go too or the loop never ends.
                    if field == "image_alt":
                        cleaned.pop("imageAlt", None)


class Page(BaseModel):
    """One page, from either a content file or a rendered HTML file.

    `frontmatter` holds the authored fields in source mode and the equivalent
    rendered metadata in build mode -- the <title>, the description meta, the
    canonical link. Filling the same model from both is what lets one rule set
    cover both: a title too long for the SERP is the same finding whether it
    was measured before or after the layout wrapped it.
    """

    model_config = ConfigDict(frozen=True)

    collection: str
    slug: str
    path: str
    # The URL a reader sees. Each loader knows it; the audit used to rebuild it
    # from collection and slug, which is right for source and wrong for a built
    # tree -- dist/index.html is served at / and was being keyed as /index/.
    url: str
    frontmatter: Frontmatter
    body: str
    origin: Origin = SOURCE
    # Findings raised while parsing, before any rule ran.
    parse_findings: tuple[Finding, ...] = ()


class CollectionSummary(BaseModel):
    pages: int = 0
    error: int = 0
    warn: int = 0
    info: int = 0


class AuditSummary(BaseModel):
    pages: int = 0
    error: int = 0
    warn: int = 0
    info: int = 0
    collections: dict[str, CollectionSummary] = Field(default_factory=dict)


class PageAudit(BaseModel):
    collection: str
    path: str
    findings: list[Finding] = Field(default_factory=list)


class AuditResult(BaseModel):
    """The page-keyed contract the report reads and other tools can enrich."""

    pages: dict[str, PageAudit] = Field(default_factory=dict)
    summary: AuditSummary = Field(default_factory=AuditSummary)
