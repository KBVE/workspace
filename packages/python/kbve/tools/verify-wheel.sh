#!/usr/bin/env bash
#
# Proves the built wheel installs and loads on its own.
#
# `uv build` succeeding says nothing about whether the result is usable: a
# missing package directory, a py.typed that was never packaged, or a module
# that only imports because the source tree happened to be on sys.path all
# produce a wheel and fail at the consumer. The test suite cannot catch any of
# them -- it runs against an editable install of the source tree, which is the
# one arrangement where every path resolves.
#
# --isolated --no-project builds a throwaway environment with nothing but the
# wheel and its declared dependencies, so an import that works here works for
# someone who ran `pip install kbve` and nothing else.
#
# Three installs, because the distribution has three shapes and each one is a
# promise to somebody:
#
#   bare        pydantic + PyYAML. kbve.seo and the stdlib-only modules, and
#               nothing heavier. This pass is what stops the server stack
#               drifting back into the base dependencies -- it asserts that
#               importing kbve.seo does NOT pull grpc or fastapi in.
#   [server]    the names exported from kbve/__init__.py, and the proto modules.
#   [blender]   the console scripts whose modules import Pillow or numpy.
set -euo pipefail

cd "$(dirname "$0")/.."

version="$(uv run --isolated --no-project python -c '
import tomllib, pathlib
print(tomllib.loads(pathlib.Path("pyproject.toml").read_text())["project"]["version"])
')"

wheel="dist/kbve-${version}-py3-none-any.whl"
if [[ ! -f $wheel ]]; then
  echo "no wheel at $wheel -- run kbve-py:build first" >&2
  echo "dist/ holds: $(ls dist 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
fi

# --- bare: the light install has to stay light -----------------------------
uv run --isolated --no-project --with "$wheel" python - <<'PY'
import importlib.metadata
import re
import sys

import kbve
import kbve.argocd
import kbve.seo
import kbve.mdx
import kbve.svg
import kbve.ai
import kbve.utils
import kbve.config
import kbve.tasks

assert kbve.seo.RULES, "the rule registry is empty"

# The whole point of the split. If one of these turns up here, something in the
# base install imported it and the light install stopped being light.
heavy = sorted({"grpc", "fastapi", "uvicorn", "aiohttp",
                "google.protobuf"} & set(sys.modules))
if heavy:
    raise SystemExit(
        f"the base install pulled in the server stack: {heavy}. "
        "Something outside the [server] extra imports it.")

# Asking for a server name without the extra must say which extra, not raise a
# bare ModuleNotFoundError from three frames down.
try:
    kbve.AppServer
except ImportError as exc:
    assert "kbve[server]" in str(exc), f"unhelpful error: {exc}"
else:
    raise SystemExit("AppServer resolved without the [server] extra installed")

# The import check above catches base code that reaches into the stack. This
# catches the other direction: a heavy requirement declared unconditionally,
# which costs every consumer the download whether they import it or not.
# Requirements arrive as 'grpcio<2.0,>=1.62; extra == "server"', so the name
# has to be taken off the front rather than split off a guessed separator.
unconditional = {
    re.match(r"[A-Za-z0-9._-]+", req).group(0).lower()
    for req in (importlib.metadata.requires("kbve") or [])
    if "extra ==" not in req
}
heavy_reqs = unconditional & {
    "grpcio", "protobuf", "fastapi", "uvicorn", "aiohttp", "pillow", "numpy"}
if heavy_reqs:
    raise SystemExit(
        f"base dependencies grew a heavy requirement: {sorted(heavy_reqs)}. "
        "Every consumer pays for that download; it belongs in an extra.")

dist = importlib.metadata.distribution("kbve")
files = {f.name for f in dist.files or []}
if "py.typed" not in files:
    raise SystemExit("py.typed is not packaged; the .pyi stubs are inert (PEP 561)")

scripts = [ep for ep in dist.entry_points if ep.group == "console_scripts"]
if not scripts:
    raise SystemExit("no console scripts in the wheel")

# kbve.seo and kbve.argocd need neither extra -- pydantic and PyYAML are in the
# base install -- so their commands have to work without one.
light = [ep for ep in scripts
         if ep.name.startswith(("kbve-seo-", "kbve-argocd-"))]
for ep in light:
    ep.load()

print(f"  bare:      seo + argocd + stdlib modules, py.typed ok, "
      f"{len(light)}/{len(scripts)} scripts run unextra'd")
PY

# --- [server]: the exported API -------------------------------------------
uv run --isolated --no-project --with "${wheel}[server]" python - <<'PY'
import kbve

missing = [name for name in kbve.__all__ if getattr(kbve, name, None) is None]
if missing:
    raise SystemExit(f"exported but unresolvable: {missing}")

import kbve.proto.kbve_pb2 as pb
import kbve.proto.kbve_pb2_grpc as pb_grpc

assert pb.EchoRequest(message="ping").message == "ping"
assert pb_grpc.EchoStub is not None and pb_grpc.HealthStub is not None

print(f"  [server]:  {len(kbve.__all__)} exports resolve, proto ok")
PY

# --- [blender]: every console script ---------------------------------------
#
# A console script naming a function that does not exist installs cleanly and
# fails the first time a user runs the command. Loading each one turns that
# into a build failure. .load() imports the module and resolves the attribute
# without calling it, so no launcher goes looking for Blender here.
uv run --isolated --no-project --with "${wheel}[blender]" python - <<'PY'
import importlib.metadata

dist = importlib.metadata.distribution("kbve")
scripts = [ep for ep in dist.entry_points if ep.group == "console_scripts"]
for ep in scripts:
    try:
        ep.load()
    except Exception as exc:  # noqa: BLE001 - the name of the broken script matters
        raise SystemExit(f"console script {ep.name} does not resolve: {exc}") from exc

print(f"  [blender]: {len(scripts)} scripts resolve")
PY
