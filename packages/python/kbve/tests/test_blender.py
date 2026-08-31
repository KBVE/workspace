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

from kbve.blender import cli, pack_orm, skin_variant, sprite_postprocess


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


# ── model_sprites_main ───────────────────────────────────────────────

def test_model_sprites_main_forwards_verbatim(monkeypatch):
    """The baker parses its own eight flags; the wrapper must not restate them."""
    seen = _capture(
        monkeypatch, "kbve-model-sprites", cli.model_sprites_main,
        ["--model", "x.obj", "--skin", "s.jpg", "--out", "d",
         "--frames", "16", "--res", "256"])
    assert seen["module"].name == "model_sprites.py"
    assert seen["passthrough"] == [
        "--model", "x.obj", "--skin", "s.jpg", "--out", "d",
        "--frames", "16", "--res", "256",
    ]


def test_model_sprites_main_drops_a_leading_separator(monkeypatch):
    """`kbve-model-sprites -- --model x` was the documented spelling under uv.

    A console script has no separator to strip, so a forwarded '--' would reach
    the baker's argparse as an argument and be rejected.
    """
    seen = _capture(
        monkeypatch, "kbve-model-sprites", cli.model_sprites_main,
        ["--", "--model", "x.obj"])
    assert seen["passthrough"] == ["--model", "x.obj"]


def test_model_sprites_main_consumes_only_blender(monkeypatch):
    seen = {}
    monkeypatch.setattr(
        sys, "argv",
        ["kbve-model-sprites", "--blender", "/opt/b", "--model", "x.obj"])
    monkeypatch.setattr(
        cli, "run_in_blender",
        lambda module, passthrough, blender: seen.update(
            passthrough=passthrough, blender=blender) or 0)
    with pytest.raises(SystemExit):
        cli.model_sprites_main()
    assert seen["blender"] == "/opt/b"
    assert seen["passthrough"] == ["--model", "x.obj"]


# ── skin_variant ─────────────────────────────────────────────────────

def _run_skin_variant(monkeypatch, argv):
    monkeypatch.setattr(sys, "argv", ["kbve-skin-variant", *argv])
    skin_variant.main()


def test_skin_variant_kills_the_glow_channel(monkeypatch, tmp_path):
    """A dominant green pixel is masked; a neutral one is left alone."""
    from PIL import Image

    src = tmp_path / "skin.png"
    # Left pixel glows green, right pixel is mid grey.
    Image.frombytes("RGB", (2, 1), bytes([10, 200, 10, 120, 120, 120])).save(src)
    out = tmp_path / "off.png"

    # No feather, so the mask edge cannot bleed one pixel into the other.
    _run_skin_variant(monkeypatch,
                      ["--in", str(src), "--out", str(out), "--feather", "0"])

    with Image.open(out) as im:
        glow, neutral = im.getpixel((0, 0)), im.getpixel((1, 0))
    assert glow[1] < 200, "the green channel should have been knocked down"
    assert neutral == (120, 120, 120), "a non-glowing pixel must be untouched"


def test_skin_variant_targets_the_named_channel(monkeypatch, tmp_path):
    """--hue red on a green-glowing image should change nothing."""
    from PIL import Image

    src = tmp_path / "skin.png"
    Image.frombytes("RGB", (1, 1), bytes([10, 200, 10])).save(src)
    out = tmp_path / "off.png"

    _run_skin_variant(monkeypatch,
                      ["--in", str(src), "--out", str(out),
                       "--hue", "red", "--feather", "0"])

    with Image.open(out) as im:
        assert im.getpixel((0, 0)) == (10, 200, 10)


# ── sprite_postprocess ───────────────────────────────────────────────

def test_bake_shadow_returns_a_frame_sized_image():
    from PIL import Image

    frame = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    frame.paste((255, 0, 0, 255), (12, 12, 20, 20))

    shadow = sprite_postprocess.bake_shadow(
        frame, 32, 0.4, 0.05, 0.55, 0.0, 0.0, 0.04, 0.06)

    assert shadow.size == frame.size
    assert shadow.mode == "RGBA"


def test_bake_shadow_is_derived_from_the_silhouette():
    """An empty frame has no silhouette, so there is nothing to cast."""
    from PIL import Image

    empty = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    shadow = sprite_postprocess.bake_shadow(
        empty, 32, 0.4, 0.05, 0.55, 0.0, 0.0, 0.04, 0.06)
    assert shadow.getbbox() is None


def test_bake_foam_needs_a_silhouette():
    """Nothing in the frame means nothing meets the water."""
    from PIL import Image

    empty = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    foam = sprite_postprocess.bake_foam(
        empty, 32, 0.4, 0.05, 0.02, 0.0, (255, 255, 255))
    assert foam.getbbox() is None


def test_bake_foam_gathers_at_the_bottom_not_the_top():
    """The reason the band is weighted by depth.

    Foam belongs where a hull meets the water. An even rim would put just as
    much of it around the mastheads, which is the tell that it is an outline
    effect rather than a waterline one.
    """
    import numpy as np
    from PIL import Image

    frame = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    frame.paste((40, 40, 40, 255), (24, 8, 40, 56))   # a tall block

    foam = sprite_postprocess.bake_foam(
        frame, 64, 1.0, 0.05, 0.01, 0.0, (255, 255, 255))

    alpha = np.asarray(foam.getchannel("A")).astype(int)
    solid = np.asarray(frame.getchannel("A")).astype(int) > 40
    added = np.where(solid, 0, alpha)          # only what the foam contributed

    top_half = added[:32].sum()
    bottom_half = added[32:].sum()
    assert bottom_half > top_half * 4, (top_half, bottom_half)


def test_bake_foam_does_not_climb_the_hull():
    """Foam marks where the water is, so almost none of it belongs above.

    An ungated rim traces the whole outline and lights the gunwale, which reads
    as a glow around the ship rather than a ship sitting in water.
    """
    import numpy as np
    from PIL import Image

    frame = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    frame.paste((40, 40, 40, 255), (16, 12, 48, 44))   # a block "hull"

    foam = sprite_postprocess.bake_foam(
        frame, 64, 1.0, 0.03, 0.0, 0.0, (255, 255, 255))

    solid = np.asarray(frame.getchannel("A")).astype(int) > 40
    added = np.where(solid, 0, np.asarray(foam.getchannel("A")).astype(int))

    waterline = 43                      # the block's lowest opaque row
    above = added[: waterline - 3].sum()
    below = added[waterline - 3 :].sum()
    assert above < below * 0.05, (above, below)


def test_bake_foam_ignores_thin_spars():
    """A bowsprit is not a waterline, and should trail no foam in mid air."""
    import numpy as np
    from PIL import Image

    frame = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    frame.paste((40, 40, 40, 255), (16, 30, 48, 44))   # hull
    frame.paste((40, 40, 40, 255), (50, 14, 62, 16))   # a thin spar, high up

    foam = sprite_postprocess.bake_foam(
        frame, 64, 1.0, 0.03, 0.0, 0.0, (255, 255, 255))
    # Only what the foam added: compositing returns the subject's own alpha
    # too, and the spar is opaque.
    solid = np.asarray(frame.getchannel("A")).astype(int) > 40
    added = np.where(solid, 0, np.asarray(foam.getchannel("A")).astype(int))

    assert added[10:22, 48:64].sum() == 0, "spar picked up foam"
    assert added[44:52, 20:44].sum() > 0, "hull did not"


def test_bake_foam_traces_outside_the_hull():
    """A rim, not a fill: the foam lands on water, not on the subject."""
    import numpy as np
    from PIL import Image

    frame = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    frame.paste((40, 40, 40, 255), (24, 24, 40, 48))

    foam = sprite_postprocess.bake_foam(
        frame, 64, 1.0, 0.05, 0.0, 0.0, (255, 255, 255))
    added = np.asarray(foam)[:, :, :3]

    # Directly under the block's bottom edge is foam; the block's own middle
    # is untouched by it.
    assert added[52, 32][0] > 120, "foam below the hull"
    assert added[36, 32][0] < 60, "hull interior left alone"


def test_bake_foam_uses_the_cut_mask_over_the_silhouette():
    """What the water actually removed beats what the silhouette suggests.

    A figurehead overhangs open water: its lowest pixel looks exactly like a
    hull's lowest pixel, and only the bake knows nothing was cut beneath it.
    Given that mask, the overhang gets no foam while the hull still does.
    """
    import numpy as np
    from PIL import Image

    frame = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    frame.paste((40, 40, 40, 255), (10, 30, 40, 44))   # hull, meets water at 43
    frame.paste((40, 40, 40, 255), (44, 20, 58, 30))   # overhang, clear of it

    # Only the hull was cut by the waterline plane.
    cut = np.zeros((64, 64), dtype=bool)
    cut[44:52, 10:40] = True

    foam = sprite_postprocess.bake_foam(
        frame, 64, 1.0, 0.03, 0.0, 0.0, (255, 255, 255), 0.006, cut)

    solid = np.asarray(frame.getchannel("A")).astype(int) > 40
    added = np.where(solid, 0, np.asarray(foam.getchannel("A")).astype(int))

    assert added[28:40, 42:60].sum() == 0, "overhang picked up foam"
    assert added[42:50, 12:38].sum() > 0, "hull did not"


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
