#!/usr/bin/env bash
#
# Builds the browser bundles into dist/, laid out the way itch.io serves an
# HTML game: index.html at the root, everything it fetches beside it.
#
# Two bundles, not one. Bevy picks its wgpu backend at compile time -- the
# `webgpu` feature overrides the default `webgl2` in a cfg, and the resulting
# binary requests Backends::BROWSER_WEBGPU and nothing else. There is no
# runtime fallback inside a single wasm, so reaching a browser without WebGPU
# means a second binary built without that feature. index.html reads
# navigator.gpu and imports one or the other.
#
# Single threaded on purpose: Bevy's multithreaded wasm build needs
# SharedArrayBuffer, which needs cross-origin isolation headers that itch does
# not send on its default hosting.
set -euo pipefail

crate_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_dir="$(cd "${crate_dir}/../../.." && pwd)"

target="wasm32-unknown-unknown"
dist="${crate_dir}/dist"
wasm="${workspace_dir}/target/${target}/release/rentearth-bevy.wasm"

# Not on PATH when rustup comes from Homebrew, which is how this machine is set
# up, so look where cargo install puts things before giving up.
if command -v wasm-bindgen > /dev/null; then
  bindgen="wasm-bindgen"
elif [ -x "${HOME}/.cargo/bin/wasm-bindgen" ]; then
  bindgen="${HOME}/.cargo/bin/wasm-bindgen"
else
  echo "error: wasm-bindgen is not installed." >&2
  echo "  cargo install --locked wasm-bindgen-cli --version 0.2.127" >&2
  echo "  (the version has to match the wasm-bindgen crate in Cargo.lock)" >&2
  exit 1
fi

# A mismatch between the CLI and the crate produces a bundle that fails at
# import time with an unhelpful message, so it is worth catching here.
locked="$(sed -n '/^name = "wasm-bindgen"$/{n;s/^version = "\(.*\)"$/\1/p;q;}' "${workspace_dir}/Cargo.lock")"
installed="$("${bindgen}" --version | awk '{print $2}')"
if [ "${locked}" != "${installed}" ]; then
  echo "error: wasm-bindgen ${installed} does not match Cargo.lock's ${locked}." >&2
  exit 1
fi

# The private water shader is a cargo feature so a clone without the git-crypt
# key still builds. A release should ship the real thing, but failing outright
# would also fail every fork, so this reports and continues.
water=()
if [ -f "${crate_dir}/src/private/water/mod.rs" ]; then
  if grep -qI . "${crate_dir}/src/private/water/mod.rs" 2> /dev/null; then
    water=(--features water)
  else
    echo "warning: src/private is still encrypted; building the flat water fallback." >&2
  fi
fi

rm -rf "${dist}"
mkdir -p "${dist}"

build() {
  local name="$1"
  shift

  echo "==> ${name}"
  # Cargo keys its target directory on the feature set, so these two do not
  # share artifacts and the second build is not incremental over the first.
  cargo build --release --target "${target}" \
    "${water[@]}" "$@" \
    --manifest-path "${crate_dir}/Cargo.toml"

  "${bindgen}" \
    --no-typescript \
    --target web \
    --out-dir "${dist}" \
    --out-name "${name}" \
    "${wasm}"
}

build rentearth-webgpu --features webgpu
build rentearth-webgl2

cp "${crate_dir}/web/index.html" "${dist}/index.html"
cp -R "${crate_dir}/assets" "${dist}/assets"

# LFS pointers are ~130 bytes of text where a PNG should be. Loading one fails
# softly at runtime to Bevy's placeholder texture, which ships a game with
# visibly wrong water rather than an error, so catch it at build time.
for png in "${dist}"/assets/water/*.png; do
  [ -e "${png}" ] || continue
  if head -c 40 "${png}" | grep -q "git-lfs.github.com"; then
    echo "error: ${png##*/} is an LFS pointer, not an image." >&2
    echo "  git lfs pull" >&2
    exit 1
  fi
done

echo "dist: $(du -sh "${dist}" | cut -f1)"
for bundle in webgpu webgl2; do
  echo "  ${bundle}: $(du -h "${dist}/rentearth-${bundle}_bg.wasm" | cut -f1)"
done
