"""Venv launchers for the Blender-python tools.

The tools need ``bpy`` (Blender's bundled Python), so each launcher locates a
Blender binary and re-runs the target module inside it via
``blender -b -P <module> -- <args>``.
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def find_blender(explicit: str | None) -> str:
    if explicit:
        return explicit
    env = os.environ.get("BLENDER")
    if env:
        return env
    found = shutil.which("blender")
    if found:
        return found
    mac = "/Applications/Blender.app/Contents/MacOS/Blender"
    if Path(mac).exists():
        return mac
    raise SystemExit(
        "blender not found: install it, set $BLENDER, or pass --blender")


def run_in_blender(module: Path, passthrough: list[str], blender: str) -> int:
    cmd = [blender, "-b", "-P", str(module), "--", *passthrough]
    return subprocess.run(cmd).returncode


def retarget_main() -> None:
    p = argparse.ArgumentParser(
        prog="kbve-blender-retarget",
        description="Headless Rokoko retarget (Mesh2Motion -> Synty SIDEKICK).")
    p.add_argument("--char", required=True, help="target rig glb (skinned)")
    p.add_argument("--anims", required=True, help="source rig glb (actions)")
    p.add_argument("--out", required=True, help="output glb")
    p.add_argument("--clips", required=True, help="comma-separated action names")
    p.add_argument("--no-plume", action="store_true",
                   help="skip the helmet-crest plume bone (herbmail-specific)")
    p.add_argument("--no-reweight", action="store_true",
                   help="skip neutral_bone weight routing")
    p.add_argument("--blender", default=None, help="path to blender binary")
    a = p.parse_args()
    blender = find_blender(a.blender)
    passthrough = [
        a.char, a.anims, a.out, a.clips,
        "0" if a.no_plume else "1",
        "0" if a.no_reweight else "1",
    ]
    code = run_in_blender(HERE / "retarget.py", passthrough, blender)
    sys.exit(code)


def vat_main() -> None:
    p = argparse.ArgumentParser(
        prog="kbve-blender-vat",
        description="Bake a looping skinned animation to a vertex animation texture.")
    p.add_argument("--src", required=True, help="source fbx/glb with one skinned mesh")
    p.add_argument("--out", required=True, help="output directory")
    p.add_argument("--tris", type=int, default=1200,
                   help="decimate target; texture size is verts x frames")
    p.add_argument("--frames", type=int, default=32, help="resampled cycle length")
    p.add_argument("--name", default=None, help="output basename (default: source stem)")
    p.add_argument("--blender", default=None, help="path to blender binary")
    a = p.parse_args()
    blender = find_blender(a.blender)
    passthrough = [a.src, a.out, str(a.tris), str(a.frames)]
    if a.name:
        passthrough.append(a.name)
    code = run_in_blender(HERE / "vat_bake.py", passthrough, blender)
    sys.exit(code)


def turf_main() -> None:
    p = argparse.ArgumentParser(
        prog="kbve-blender-turf",
        description="Bake a tiling turf surface -- grass tufts and rocks -- to flat maps.")
    p.add_argument("--out", default=None, help="output directory (default: cwd)")
    p.add_argument("--res", type=int, default=None, help="bake resolution (default: 2048)")
    p.add_argument("--seed", type=int, default=None, help="scatter seed (default: 7)")
    p.add_argument("--prefix", default=None, help="output basename (default: turf_baked)")
    p.add_argument("--ao-samples", type=int, default=None,
                   help="ambient occlusion samples (default: 96)")
    p.add_argument("--rocks", type=int, default=None, help="rock count")
    p.add_argument("--blender", default=None, help="path to blender binary")
    a = p.parse_args()

    # turf_bake reads flags rather than positionals, so they are forwarded by
    # name. Only what was passed is forwarded: every one of these has a default
    # on the far side, and sending a None through would override it.
    passthrough: list[str] = []
    for flag, value in (
        ("--out", a.out),
        ("--res", a.res),
        ("--seed", a.seed),
        ("--prefix", a.prefix),
        ("--ao-samples", a.ao_samples),
        ("--rocks", a.rocks),
    ):
        if value is not None:
            passthrough += [flag, str(value)]

    blender = find_blender(a.blender)
    code = run_in_blender(HERE / "turf_bake.py", passthrough, blender)
    sys.exit(code)


def model_sprites_main() -> None:
    """Launcher for the ARPG sprite baker.

    Unlike the others this forwards its arguments verbatim rather than naming
    them: model_sprites.py parses eight of its own with argparse, and
    restating them here would be a second list to keep in step. Only --blender
    is consumed, so parse_known_args is what keeps --model and friends intact.
    """
    p = argparse.ArgumentParser(
        prog="kbve-model-sprites",
        description="Bake a model to a sheet of facing sprites (args are passed to the baker).",
        add_help=False)
    p.add_argument("--blender", default=None, help="path to blender binary")
    a, rest = p.parse_known_args()

    # `kbve-model-sprites -- --model x.obj` was the documented spelling when
    # this was its own entry point, because it used to be run through uv. The
    # separator means nothing to a console script, so it is tolerated and
    # dropped rather than forwarded as an argument the baker would reject.
    if rest and rest[0] == "--":
        rest = rest[1:]

    blender = find_blender(a.blender)
    code = run_in_blender(HERE / "model_sprites.py", rest, blender)
    sys.exit(code)


# Default entry when invoked bare; kept generic in case more tools are added.
def main() -> None:
    retarget_main()


if __name__ == "__main__":
    main()
