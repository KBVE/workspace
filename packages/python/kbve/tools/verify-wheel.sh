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

print(f"kbve {kbve.__version__}: {len(kbve.__all__)} exports, proto ok, py.typed ok")
PY
