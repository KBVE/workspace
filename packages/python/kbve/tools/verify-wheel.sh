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
# Two installs are checked, because the package has two audiences. The bare
# one is the server stack, and must not need an extra to import. The second
# adds [blender], which is where the image passes get Pillow and numpy.
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

# --- bare install: the public API owes nothing to an extra ------------------
uv run --isolated --no-project --with "$wheel" python - <<'PY'
import importlib.metadata
import kbve

# The lazy __getattr__ means a broken submodule stays invisible until touched,
# so every exported name is resolved rather than just imported.
missing = [name for name in kbve.__all__ if getattr(kbve, name, None) is None]
if missing:
    raise SystemExit(f"exported but unresolvable: {missing}")

import kbve.proto.kbve_pb2 as pb
import kbve.proto.kbve_pb2_grpc as pb_grpc

assert pb.EchoRequest(message="ping").message == "ping"
assert pb_grpc.EchoStub is not None and pb_grpc.HealthStub is not None

dist = importlib.metadata.distribution("kbve")
files = {f.name for f in dist.files or []}
if "py.typed" not in files:
    raise SystemExit("py.typed is not packaged; the .pyi stubs are inert (PEP 561)")

scripts = [ep for ep in dist.entry_points if ep.group == "console_scripts"]
if not scripts:
    raise SystemExit("no console scripts in the wheel; expected the kbve-blender-* launchers")

print(f"  bare:      {len(kbve.__all__)} exports, proto ok, py.typed ok, {len(scripts)} scripts declared")
PY

# --- with [blender]: every console script has to resolve --------------------
#
# A console script naming a function that does not exist installs cleanly and
# fails the first time a user runs the command. Loading each one turns that
# into a build failure. .load() imports the module and resolves the attribute
# without calling it, so no launcher goes looking for Blender here.
#
# The extra is installed for this pass because that is the documented way to
# get these commands: three of them import Pillow or numpy at module scope.
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
