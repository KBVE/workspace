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
# Both bundles are threaded. `+atomics` makes the binary import a shared memory
# instead of defining its own, which is what lets a web worker instantiate the
# same module against the same heap and become a thread of this program rather
# than a second copy of it. The standard library rustup ships for wasm32 is
# built without those features, so it is rebuilt from source here -- that is
# the `-Z build-std`, and the reason for the second toolchain.
#
# The page needs cross-origin isolation for any of it to work: no COOP/COEP,
# no SharedArrayBuffer, and `new WebAssembly.Memory({shared: true})` throws
# before the game gets a frame. On itch that is the "SharedArrayBuffer support"
# checkbox in the project's embed options, which is a setting on the page and
# not something an upload can carry. index.html says so rather than failing
# blank.
#
# What threads buy, precisely: bevy_tasks hardcodes a single-threaded pool on
# wasm32 -- `cfg(all(not(target_arch = "wasm32"), feature = "multi_threaded"))`
# -- so Bevy's own schedule, extract and asset work stay on the main thread
# whatever this script does. The workers are for what the game hands to
# bevy_tasker.
set -euo pipefail

crate_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_dir="$(cd "${crate_dir}/../../.." && pwd)"

target="wasm32-unknown-unknown"
dist="${crate_dir}/dist"
wasm="${workspace_dir}/target/${target}/release/rentearth-bevy.wasm"

toolchain="$(sed -n '1s/[[:space:]]*$//p' "${crate_dir}/tools/wasm-toolchain.txt")"
[ -n "${toolchain}" ] || { echo "error: wasm-toolchain.txt is empty." >&2; exit 1; }

# --shared-memory and --import-memory are not implied by +atomics: without them
# lld emits a module that defines its own memory, every worker instantiates a
# private heap, and the pool silently does nothing shared. --max-memory is
# mandatory once memory is shared, because a shared memory cannot be grown
# past a maximum it never declared. 2GiB is address space reserved, not
# committed.
wasm_rustflags="-C target-feature=+atomics,+bulk-memory,+mutable-globals"
wasm_rustflags="${wasm_rustflags} -C link-arg=--shared-memory"
wasm_rustflags="${wasm_rustflags} -C link-arg=--import-memory"
wasm_rustflags="${wasm_rustflags} -C link-arg=--max-memory=2147483648"

# wasm-bindgen rewrites the module to give each thread its own thread-locals,
# and it needs these four to do it -- without them it stops at "failed to find
# `__wasm_init_tls`". lld emits the symbols but does not export them, because
# nothing inside the module references them: the caller is the generated glue,
# which does not exist yet at link time.
for symbol in __wasm_init_tls __tls_size __tls_align __tls_base; do
  wasm_rustflags="${wasm_rustflags} -C link-arg=--export=${symbol}"
done

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
  # `rustup run`, not `cargo +toolchain`: the `+` directive is understood by
  # rustup's cargo proxy, and under moon `cargo` is the real binary proto
  # installed, which rejects it with "no such command: `+nightly-...`".
  RUSTFLAGS="${wasm_rustflags}" rustup run "${toolchain}" cargo build --release --target "${target}" \
    -Z build-std=std,panic_abort \
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
cp "${crate_dir}/web/worker.js" "${dist}/worker.js"
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
