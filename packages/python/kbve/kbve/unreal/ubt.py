"""Locating Unreal Build Tool and composing the command that drives it.

Nothing here runs UBT; it works out what to run. That split is what lets
kbve-unreal-clangd --dry-run print the exact command on a machine with no
engine installed, and what makes any of this testable.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# Where the Epic launcher installs engines on macOS. There is no equivalent
# convention on Linux -- source builds land wherever they were cloned -- so
# there is no default to offer there, and resolve_engine_root says so instead
# of guessing a path that will not exist.
MACOS_ENGINE_BASE = Path("/Users/Shared/Epic Games")

# UBT's own name for the host, which is also the default target platform.
HOST_PLATFORMS = {"darwin": "Mac", "linux": "Linux", "win32": "Win64"}


def host_platform() -> str:
    """The UBT platform name for the machine this is running on."""
    return HOST_PLATFORMS.get(sys.platform, "Linux")


def parse_engine_association(uproject: Path) -> str:
    data = json.loads(Path(uproject).read_text())
    return data["EngineAssociation"]


def resolve_engine_root(uproject: Path, override: Path | None = None) -> Path:
    if override is not None:
        return Path(override)
    env = os.environ.get("KBVE_UE_ROOT")
    if env:
        return Path(env)
    version = parse_engine_association(uproject)
    if sys.platform != "darwin":
        raise EngineNotFound(
            f"no default engine location on {sys.platform}; set KBVE_UE_ROOT "
            f"or pass --engine-root (the project wants UE_{version})")
    return MACOS_ENGINE_BASE / f"UE_{version}"


class EngineNotFound(Exception):
    """The engine could not be located and the caller has to say where it is."""


def build_script(engine_root: Path) -> Path:
    """The UBT entry point for the host.

    Chosen by the host, not by the target platform. This used to be fixed at
    BatchFiles/Mac/Build.sh while --platform was a separate argument, so asking
    for a Linux target on a Linux machine ran the macOS script -- which is not
    there, and fails with a path error rather than anything about platforms.
    """
    batchfiles = Path(engine_root) / "Engine" / "Build" / "BatchFiles"
    if sys.platform == "darwin":
        return batchfiles / "Mac" / "Build.sh"
    if sys.platform == "win32":
        return batchfiles / "Build.bat"
    return batchfiles / "Linux" / "Build.sh"


def generate_clang_db_command(
    engine_root: Path,
    uproject: Path,
    target: str,
    config: str,
    platform: str,
) -> list[str]:
    return [
        str(build_script(engine_root)),
        target,
        platform,
        config,
        f"-project={uproject}",
        "-mode=GenerateClangDatabase",
    ]
