import json

import pytest

from kbve.unreal import ubt
from kbve.unreal.ubt import (
    parse_engine_association,
    resolve_engine_root,
    generate_clang_db_command,
)


@pytest.fixture
def uproject(tmp_path):
    path = tmp_path / "rentearth.uproject"
    path.write_text(json.dumps({"FileVersion": 3, "EngineAssociation": "5.8"}))
    return path


def test_parse_engine_association_reads_version(uproject):
    assert parse_engine_association(uproject) == "5.8"


def test_resolve_engine_root_defaults_to_shared_epic(uproject, monkeypatch):
    """The Epic launcher's macOS location, asserted as macOS rather than as here.

    This read sys.platform implicitly and passed on a developer's Mac while
    failing on the Linux runner, where /Users/Shared is not a thing.
    """
    monkeypatch.setattr(ubt.sys, "platform", "darwin")
    monkeypatch.delenv("KBVE_UE_ROOT", raising=False)
    assert str(resolve_engine_root(uproject)) == "/Users/Shared/Epic Games/UE_5.8"


@pytest.mark.parametrize("platform", ["linux", "win32"])
def test_resolve_engine_root_refuses_to_guess_off_macos(uproject, monkeypatch,
                                                        platform):
    """A source build lands wherever it was cloned; there is nothing to default to."""
    monkeypatch.setattr(ubt.sys, "platform", platform)
    monkeypatch.delenv("KBVE_UE_ROOT", raising=False)
    with pytest.raises(ubt.EngineNotFound) as excinfo:
        resolve_engine_root(uproject)
    assert "KBVE_UE_ROOT" in str(excinfo.value)
    assert "UE_5.8" in str(excinfo.value), "say which engine the project wants"


@pytest.mark.parametrize("platform,expected", [
    ("darwin", "Engine/Build/BatchFiles/Mac/Build.sh"),
    ("linux", "Engine/Build/BatchFiles/Linux/Build.sh"),
    ("win32", "Engine/Build/BatchFiles/Build.bat"),
])
def test_build_script_follows_the_host(monkeypatch, tmp_path, platform, expected):
    """The script is picked by the host, not by the target platform.

    It was fixed at the macOS path while --platform was a separate argument, so
    a Linux target on a Linux machine invoked a script that is not installed
    there and failed with a missing-path error saying nothing about platforms.
    """
    monkeypatch.setattr(ubt.sys, "platform", platform)
    assert ubt.build_script(tmp_path) == tmp_path / expected


@pytest.mark.parametrize("platform,expected", [
    ("darwin", "Mac"), ("linux", "Linux"), ("win32", "Win64"),
])
def test_host_platform_uses_ubt_names(monkeypatch, platform, expected):
    monkeypatch.setattr(ubt.sys, "platform", platform)
    assert ubt.host_platform() == expected


def test_resolve_engine_root_env_override(uproject, monkeypatch, tmp_path):
    monkeypatch.setenv("KBVE_UE_ROOT", str(tmp_path / "UE"))
    assert resolve_engine_root(uproject) == tmp_path / "UE"


def test_resolve_engine_root_arg_beats_env(uproject, monkeypatch, tmp_path):
    monkeypatch.setenv("KBVE_UE_ROOT", str(tmp_path / "env"))
    assert resolve_engine_root(uproject, override=tmp_path / "arg") == tmp_path / "arg"


def test_generate_clang_db_command_shape(uproject, tmp_path):
    engine = tmp_path / "UE_5.8"
    cmd = generate_clang_db_command(
        engine_root=engine,
        uproject=uproject,
        target="chuckEditor",
        config="Development",
        platform="Mac",
    )
    assert cmd[0] == str(engine / ubt.build_script(engine).relative_to(engine))
    assert "-mode=GenerateClangDatabase" in cmd
    assert f"-project={uproject}" in cmd
    assert "chuckEditor" in cmd
    assert "Development" in cmd
    assert "Mac" in cmd
