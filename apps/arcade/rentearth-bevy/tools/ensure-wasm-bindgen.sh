#!/usr/bin/env bash
#
# Puts the wasm-bindgen CLI that Cargo.lock pins on PATH for build-web.sh.
#
# Lives beside the build rather than in the release workflow so that adding a
# game to itch stays a moon.yml edit: the workflow installs the toolchains the
# workspace declares and nothing a single project happens to need. This is one
# of those needs.
#
# The prebuilt archive rather than `cargo install`: the CLI is a from-source
# build of several minutes, and this runs on every release.
set -euo pipefail

crate_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_dir="$(cd "${crate_dir}/../../.." && pwd)"

locked="$(sed -n '/^name = "wasm-bindgen"$/{n;s/^version = "\(.*\)"$/\1/p;q;}' "${workspace_dir}/Cargo.lock")"
[ -n "${locked}" ] || { echo "error: no wasm-bindgen version in Cargo.lock." >&2; exit 1; }

# A CLI older or newer than the crate emits a bundle that fails at import with
# no useful message, so the check is on the exact version, not on presence.
have() {
  local bin="$1"
  command -v "$bin" > /dev/null 2>&1 || return 1
  [ "$("$bin" --version 2>/dev/null | awk '{print $2}')" = "${locked}" ]
}

for candidate in wasm-bindgen "${HOME}/.cargo/bin/wasm-bindgen"; do
  if have "${candidate}"; then
    echo "wasm-bindgen ${locked} is already installed."
    exit 0
  fi
done

# Only the Linux runner is served a binary. A developer on another platform is
# told what to install rather than having a foreign archive unpacked for them.
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *)
    echo "error: wasm-bindgen ${locked} is not installed." >&2
    echo "  cargo install --locked wasm-bindgen-cli --version ${locked}" >&2
    exit 1
    ;;
esac

name="wasm-bindgen-${locked}-x86_64-unknown-linux-musl"
dest="${HOME}/.cargo/bin"
mkdir -p "${dest}"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

echo "Installing wasm-bindgen ${locked}"
curl -fsSL -o "${tmp}/wasm-bindgen.tar.gz" \
  "https://github.com/rustwasm/wasm-bindgen/releases/download/${locked}/${name}.tar.gz"
tar xzf "${tmp}/wasm-bindgen.tar.gz" -C "${tmp}"
install -m 0755 "${tmp}/${name}/wasm-bindgen" "${dest}/wasm-bindgen"

have "${dest}/wasm-bindgen" || { echo "error: installed wasm-bindgen is not ${locked}." >&2; exit 1; }
