"""Loading a site's SEO profiles from a file it owns.

Upstream the profiles were a dict in the library, so describing a second site
meant editing the auditor. That is the same shape the workspace already rejects
elsewhere -- a project declares its own facts in its own directory and a shared
task consumes them -- and it is why the thresholds live in the site now.

The file is TOML, read with the standard library, and validated on the way in
so a misspelled threshold names itself instead of being silently ignored::

    # apps/website/example.com/seo.toml
    [default]
    desc_min = 50

    [collections.blog]
    body_min_chars = 800
    require_tags = true
"""

from __future__ import annotations

import os
import tomllib
from pathlib import Path

from pydantic import ValidationError

from .models import ProfileSet

CONFIG_NAMES = ("seo.toml", ".seo.toml")


class ProfileError(Exception):
    """A profile file exists but does not describe a usable profile set."""


def find_config(content_dir: str | os.PathLike[str]) -> Path | None:
    """Look for a profile file beside the content, then above it.

    Astro puts content at ``<project>/src/content``, so the project root is two
    levels up. The search stops there rather than walking to the filesystem
    root: picking up another project's profiles because this one had none would
    audit a site against thresholds written for a different one.
    """
    here = Path(content_dir).resolve()
    for directory in (here, *list(here.parents)[:2]):
        for name in CONFIG_NAMES:
            candidate = directory / name
            if candidate.is_file():
                return candidate
    return None


def load_profiles(path: str | os.PathLike[str] | None) -> ProfileSet:
    """Read a profile file, or return the built-in defaults when there is none."""
    if path is None:
        return ProfileSet()

    file = Path(path)
    try:
        data = tomllib.loads(file.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as exc:
        raise ProfileError(f"{file}: {exc}") from exc

    try:
        return ProfileSet.model_validate(data)
    except ValidationError as exc:
        detail = "; ".join(
            f"{'.'.join(str(p) for p in err['loc'])}: {err['msg']}"
            for err in exc.errors()
        )
        raise ProfileError(f"{file}: {detail}") from exc
