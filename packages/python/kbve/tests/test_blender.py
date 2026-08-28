"""Tests for kbve.blender.

The three bpy modules are not tested here and cannot be: they import bpy at
module scope, which only exists inside Blender. What is testable is everything
that decides *how* Blender gets invoked -- binary resolution, argument
forwarding -- plus pack_orm, which deliberately stays outside Blender.

This module had no tests upstream.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from kbve.blender import cli, pack_orm


# ── find_blender ─────────────────────────────────────────────────────

def test_find_blender_prefers_explicit(monkeypatch):
    monkeypatch.setenv("BLENDER", "/from/env")
    assert cli.find_blender("/explicit") == "/explicit"


def test_find_blender_falls_back_to_env(monkeypatch):
    monkeypatch.setenv("BLENDER", "/from/env")
    monkeypatch.setattr(cli.shutil, "which", lambda _: "/on/path")
    assert cli.find_blender(None) == "/from/env"


def test_find_blender_falls_back_to_path(monkeypatch):
    monkeypatch.delenv("BLENDER", raising=False)
    monkeypatch.setattr(cli.shutil, "which", lambda _: "/on/path")
    assert cli.find_blender(None) == "/on/path"


def test_find_blender_falls_back_to_macos_app(monkeypatch):
    monkeypatch.delenv("BLENDER", raising=False)
    monkeypatch.setattr(cli.shutil, "which", lambda _: None)
    monkeypatch.setattr(Path, "exists", lambda _: True)
    assert cli.find_blender(None).endswith("MacOS/Blender")


def test_find_blender_exits_when_absent(monkeypatch):
    """The message has to name all three ways out, or the failure is a dead end."""
    monkeypatch.delenv("BLENDER", raising=False)
    monkeypatch.setattr(cli.shutil, "which", lambda _: None)
    monkeypatch.setattr(Path, "exists", lambda _: False)
    with pytest.raises(SystemExit) as excinfo:
        cli.find_blender(None)
    message = str(excinfo.value)
    assert "$BLENDER" in message and "--blender" in message


def test_find_blender_ignores_empty_env(monkeypatch):
    """An exported-but-empty BLENDER should not win over a binary on PATH."""
    monkeypatch.setenv("BLENDER", "")
    monkeypatch.setattr(cli.shutil, "which", lambda _: "/on/path")
    assert cli.find_blender(None) == "/on/path"


# ── run_in_blender ───────────────────────────────────────────────────

def test_run_in_blender_builds_headless_command(monkeypatch):
    seen = {}

    def fake_run(cmd):
        seen["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(cli.subprocess, "run", fake_run)
    code = cli.run_in_blender(Path("/mod/vat_bake.py"), ["a", "b"], "/bin/blender")

    assert code == 0
    # The '--' is what separates Blender's own flags from the script's.
    assert seen["cmd"] == [
        "/bin/blender", "-b", "-P", "/mod/vat_bake.py", "--", "a", "b",
    ]


def test_run_in_blender_propagates_exit_code(monkeypatch):
    monkeypatch.setattr(
        cli.subprocess, "run",
        lambda cmd: subprocess.CompletedProcess(cmd, 3))
    assert cli.run_in_blender(Path("/mod/x.py"), [], "/bin/blender") == 3


# ── turf_main ────────────────────────────────────────────────────────

def _capture_turf(monkeypatch, argv):
    seen = {}
    monkeypatch.setattr(sys, "argv", ["kbve-blender-turf", *argv])
    monkeypatch.setattr(cli, "find_blender", lambda _: "/bin/blender")
    monkeypatch.setattr(
        cli, "run_in_blender",
        lambda module, passthrough, blender: seen.update(
            module=module, passthrough=passthrough) or 0)
    with pytest.raises(SystemExit) as excinfo:
        cli.turf_main()
    assert excinfo.value.code == 0
    return seen


def test_turf_main_forwards_nothing_by_default(monkeypatch):
    """Every flag has a default inside turf_bake; forwarding None would win over it."""
    seen = _capture_turf(monkeypatch, [])
    assert seen["passthrough"] == []
    assert seen["module"].name == "turf_bake.py"


def test_turf_main_forwards_by_name(monkeypatch):
    seen = _capture_turf(monkeypatch, ["--res", "512", "--seed", "3"])
    assert seen["passthrough"] == ["--res", "512", "--seed", "3"]


def test_turf_main_forwards_only_what_was_passed(monkeypatch):
    seen = _capture_turf(monkeypatch, ["--prefix", "grass"])
    assert seen["passthrough"] == ["--prefix", "grass"]


def test_turf_main_keeps_the_flag_spelling_turf_bake_reads(monkeypatch):
    """turf_bake looks for '--ao-samples'; argparse stores it as ao_samples."""
    seen = _capture_turf(monkeypatch, ["--ao-samples", "8"])
    assert seen["passthrough"] == ["--ao-samples", "8"]


# ── retarget_main / vat_main ─────────────────────────────────────────

def _capture(monkeypatch, prog, entry, argv):
    seen = {}
    monkeypatch.setattr(sys, "argv", [prog, *argv])
    monkeypatch.setattr(cli, "find_blender", lambda _: "/bin/blender")
    monkeypatch.setattr(
        cli, "run_in_blender",
        lambda module, passthrough, blender: seen.update(
            module=module, passthrough=passthrough) or 0)
    with pytest.raises(SystemExit):
        entry()
    return seen


def test_retarget_main_passes_positionally(monkeypatch):
    seen = _capture(
        monkeypatch, "kbve-blender-retarget", cli.retarget_main,
        ["--char", "c.glb", "--anims", "a.glb", "--out", "o.glb",
         "--clips", "idle,run"])
    assert seen["module"].name == "retarget.py"
    # retarget.py reads these by position, so order is the contract.
    assert seen["passthrough"][:4] == ["c.glb", "a.glb", "o.glb", "idle,run"]


def test_retarget_main_inverts_the_skip_flags(monkeypatch):
    """--no-plume/--no-reweight are opt-outs; the script receives do-it flags.

    The wrapper sends "1" for "do this" and "0" for "skip it", so passing
    --no-plume has to arrive as "0". Getting the polarity backwards here would
    silently produce the opposite rig with no error anywhere.
    """
    base = ["--char", "c.glb", "--anims", "a.glb", "--out", "o.glb",
            "--clips", "idle"]

    default = _capture(
        monkeypatch, "kbve-blender-retarget", cli.retarget_main, base)
    assert default["passthrough"][4:] == ["1", "1"]

    skipped = _capture(
        monkeypatch, "kbve-blender-retarget", cli.retarget_main,
        [*base, "--no-plume", "--no-reweight"])
    assert skipped["passthrough"][4:] == ["0", "0"]


def test_vat_main_stringifies_its_numbers(monkeypatch):
    seen = _capture(
        monkeypatch, "kbve-blender-vat", cli.vat_main,
        ["--src", "s.fbx", "--out", "d", "--tris", "800", "--frames", "16"])
    assert seen["module"].name == "vat_bake.py"
    assert seen["passthrough"] == ["s.fbx", "d", "800", "16"]


def test_vat_main_appends_name_only_when_given(monkeypatch):
    """vat_bake reads by position, so an absent name must not leave a hole."""
    base = ["--src", "s.fbx", "--out", "d"]

    without = _capture(monkeypatch, "kbve-blender-vat", cli.vat_main, base)
    assert len(without["passthrough"]) == 4

    with_name = _capture(
        monkeypatch, "kbve-blender-vat", cli.vat_main, [*base, "--name", "hero"])
    assert with_name["passthrough"][4] == "hero"


def test_vat_main_defaults_match_the_documented_ones(monkeypatch):
    seen = _capture(monkeypatch, "kbve-blender-vat", cli.vat_main,
                    ["--src", "s.fbx", "--out", "d"])
    assert seen["passthrough"][2:4] == ["1200", "32"]


# ── pack_orm ─────────────────────────────────────────────────────────

def _write_greyscale(path: Path, value: int, size=(4, 4)) -> None:
    from PIL import Image
    Image.new("L", size, value).save(path)


def test_pack_writes_ao_to_red_and_roughness_to_green(tmp_path):
    from PIL import Image

    _write_greyscale(tmp_path / "turf_baked_ao.png", 200)
    _write_greyscale(tmp_path / "turf_baked_roughness.png", 100)

    out = pack_orm.pack(tmp_path, "turf_baked")

    with Image.open(out) as im:
        assert im.mode == "RGB"
        # Red is ambient occlusion, green is roughness, blue is unused.
        assert im.getpixel((0, 0)) == (200, 100, 0)


def test_pack_names_the_output_after_the_prefix(tmp_path):
    _write_greyscale(tmp_path / "grass_ao.png", 1)
    _write_greyscale(tmp_path / "grass_roughness.png", 2)
    assert pack_orm.pack(tmp_path, "grass").name == "grass_orm.png"


def test_pack_rejects_mismatched_sizes(tmp_path):
    """Merging different sizes raises deep inside PIL; this fails with the sizes."""
    _write_greyscale(tmp_path / "turf_baked_ao.png", 1, size=(4, 4))
    _write_greyscale(tmp_path / "turf_baked_roughness.png", 2, size=(8, 8))
    with pytest.raises(SystemExit) as excinfo:
        pack_orm.pack(tmp_path, "turf_baked")
    assert "size mismatch" in str(excinfo.value)


def test_pack_requires_both_inputs(tmp_path):
    _write_greyscale(tmp_path / "turf_baked_ao.png", 1)
    with pytest.raises(FileNotFoundError):
        pack_orm.pack(tmp_path, "turf_baked")
