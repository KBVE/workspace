#!/usr/bin/env bash
#
# Proves the built wheel installs and loads against the kbve it is meant to
# run with.
#
# The pinning is the point. fudster depends on kbve[server], and `kbve` on PyPI
# is the old published 1.0.13 from the Nx workspace -- which has no `server`
# extra at all. Install this wheel anywhere without saying otherwise and uv
# resolves that one, prints "does not have an extra named `server`" as a
# warning rather than an error, and carries on. So the gate installs the kbve
# wheel built out of this repository and checks against that.
#
# Until kbve 2.0.0 is published, that mismatch is the expected state rather
# than a defect, and this script is what keeps it from being a surprise.
set -euo pipefail

cd "$(dirname "$0")/.."

version="$(uv run --isolated --no-project python -c '
import tomllib, pathlib
print(tomllib.loads(pathlib.Path("pyproject.toml").read_text())["project"]["version"])
')"

wheel="dist/fudster-${version}-py3-none-any.whl"
[[ -f $wheel ]] || { echo "no wheel at $wheel -- run fudster:build first" >&2; exit 1; }

kbve_wheel="$(ls ../kbve/dist/kbve-*-py3-none-any.whl 2>/dev/null | tail -1 || true)"
if [[ -z $kbve_wheel ]]; then
  echo "no kbve wheel in ../kbve/dist -- run kbve-py:build first" >&2
  exit 1
fi

uv run --isolated --no-project \
  --with "${kbve_wheel}[server]" --with "$wheel" python - <<'PY'
import importlib.metadata

import fudster

expected = importlib.metadata.version("fudster")
assert fudster.__version__ == expected, (
    f"__version__ {fudster.__version__} disagrees with the installed {expected}")

# The whole reason for pinning the local wheel: 1.x is the published one.
kbve_version = importlib.metadata.version("kbve")
if kbve_version.startswith("1."):
    raise SystemExit(
        f"resolved kbve {kbve_version} from the registry, not the local wheel; "
        "the [server] extra does not exist there")

# fudster.api imports these at module scope, and they are declared here rather
# than inherited from kbve[server] -- this is what proves that.
import fudster.api  # noqa: F401
import kbve.grpc.client  # noqa: F401
import kbve.health  # noqa: F401

scripts = [ep for ep in importlib.metadata.distribution("fudster").entry_points
           if ep.group == "console_scripts"]
assert scripts, "no console scripts; expected `fudster`"
for ep in scripts:
    ep.load()

print(f"  fudster {expected} against kbve {kbve_version}: "
      f"api ok, {len(scripts)} script(s) resolve")
PY
