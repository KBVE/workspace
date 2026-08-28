import json

import pytest

from kbve.unreal.check import build_check_invocation, main as check_main
from kbve.unreal.clangd import write_clangd_pointer, locate_generated_db


@pytest.fixture
def db_env(tmp_path):
    src = tmp_path / "proj/Source/mod"
    src.mkdir(parents=True)
    cpp = src / "A.cpp"
    cpp.write_text("")
    header = src / "A.h"
    header.write_text("")
    entries = [
        {
            "file": str(cpp),
            "directory": str(tmp_path),
            "command": f"clang++ -DX=1 -c {cpp} -o /out/A.o",
        }
    ]
    db = tmp_path / "proj/compile_commands.json"
    db.write_text(json.dumps(entries))
    return tmp_path, db, cpp, header


def test_build_check_invocation_header_injects_include(db_env):
    _, db, cpp, header = db_env
    entries = json.loads(db.read_text())
    cmd = build_check_invocation(entries, str(header))
    assert "-fsyntax-only" in cmd
    assert "-include" in cmd
    assert cmd[cmd.index("-include") + 1] == str(header.resolve())
    assert cmd.index("-include") > cmd.index("-DX=1")


def test_check_main_missing_entry_exit_code_2(db_env, capsys):
    tmp_path, db, _, _ = db_env
    missing = tmp_path / "proj/Source/mod/Nope.cpp"
    missing.write_text("")
    rc = check_main(["--db", str(db), str(missing)])
    assert rc == 2
    err = capsys.readouterr().err
    assert "kbve-unreal-clangd" in err


def test_write_clangd_pointer_creates_committed_config(tmp_path):
    db_dir = tmp_path / "apps/rentearth/unreal-rentearth"
    db_dir.mkdir(parents=True)
    out = write_clangd_pointer(tmp_path, db_dir)
    assert out == tmp_path / ".clangd"
    text = out.read_text()
    assert "CompilationDatabase: apps/rentearth/unreal-rentearth" in text


def test_locate_generated_db_prefers_project_dir(tmp_path):
    project_dir = tmp_path / "proj"
    project_dir.mkdir()
    (project_dir / "compile_commands.json").write_text("[]")
    engine = tmp_path / "UE_5.8"
    engine.mkdir()
    found = locate_generated_db(engine, project_dir)
    assert found == project_dir / "compile_commands.json"


def test_locate_generated_db_finds_engine_output(tmp_path):
    project_dir = tmp_path / "proj"
    project_dir.mkdir()
    engine = tmp_path / "UE_5.8"
    engine.mkdir()
    (engine / "compile_commands.json").write_text("[]")
    found = locate_generated_db(engine, project_dir)
    assert found == engine / "compile_commands.json"


def test_locate_generated_db_none_when_absent(tmp_path):
    project_dir = tmp_path / "proj"
    project_dir.mkdir()
    engine = tmp_path / "UE_5.8"
    engine.mkdir()
    assert locate_generated_db(engine, project_dir) is None


# ── the defaults that named one checkout ─────────────────────────────

import pytest  # noqa: E402

from kbve.unreal import clangd as clangd_mod  # noqa: E402


@pytest.mark.parametrize("argv", [
    [],
    ["--target", "GameEditor"],
    ["--project", "game.uproject"],
])
def test_project_and_target_are_both_required(argv):
    """They defaulted to a .uproject path and a UBT target from one repository.

    `chuckEditor` was not even the target of the game the default path pointed
    at, so the old defaults turned "you did not say which project" into "that
    file does not exist".
    """
    with pytest.raises(SystemExit) as excinfo:
        clangd_mod.main(argv)
    assert excinfo.value.code == 2


def test_missing_uproject_exits_two(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    code = clangd_mod.main(
        ["--project", "nope.uproject", "--target", "GameEditor"])
    assert code == 2
    assert "uproject not found" in capsys.readouterr().err


def test_dry_run_prints_the_command_without_an_engine(tmp_path, monkeypatch,
                                                      capsys):
    """--dry-run is the whole reason ubt.py composes rather than executes."""
    import json
    (tmp_path / ".git").mkdir()
    uproject = tmp_path / "game.uproject"
    uproject.write_text(json.dumps({"EngineAssociation": "5.8"}))
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("KBVE_UE_ROOT", str(tmp_path / "engine"))

    code = clangd_mod.main(
        ["--project", "game.uproject", "--target", "GameEditor", "--dry-run"])
    assert code == 0
    out = capsys.readouterr().out
    assert "-mode=GenerateClangDatabase" in out
    assert "GameEditor" in out


def test_engine_not_found_is_reported_not_raised(tmp_path, monkeypatch, capsys):
    import json
    from kbve.unreal import ubt
    (tmp_path / ".git").mkdir()
    uproject = tmp_path / "game.uproject"
    uproject.write_text(json.dumps({"EngineAssociation": "5.8"}))
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("KBVE_UE_ROOT", raising=False)
    monkeypatch.setattr(ubt.sys, "platform", "linux")

    code = clangd_mod.main(
        ["--project", "game.uproject", "--target", "GameEditor"])
    assert code == 2
    assert "KBVE_UE_ROOT" in capsys.readouterr().err
