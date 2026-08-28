#!/usr/bin/env bash
#
# Installs the nightly toolchain the browser build needs, beside the one
# rust-toolchain.toml pins for everything else.
#
# Two toolchains because the browser build is threaded. `+atomics` makes the
# binary import a shared memory and use `memory.atomic.*`, and the wasm32
# standard library rustup ships is compiled without those features -- so it has
# to be rebuilt from source with `-Z build-std`, which is nightly-only. Nothing
# else in the workspace needs nightly, so nothing else gets it: this stays a
# dependency of one project's build rather than a second entry in .prototools.
#
# Pinned to a date rather than tracking `nightly`, for the same reason the
# stable channel is pinned: a floating channel makes a release depend on when
# it was cut.
set -euo pipefail

tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
toolchain="$(sed -n '1s/[[:space:]]*$//p' "${tools_dir}/wasm-toolchain.txt")"
[ -n "${toolchain}" ] || { echo "error: wasm-toolchain.txt is empty." >&2; exit 1; }

# --profile minimal, plus the two pieces build-std needs: the standard library
# sources to compile, and the target spec to compile them for.
rustup toolchain install "${toolchain}" --profile minimal --component rust-src
rustup target add wasm32-unknown-unknown --toolchain "${toolchain}"

# `rustup toolchain install` is happy with a directory that exists, so check
# for the thing that is actually needed rather than for the install's exit
# code -- the same failure mode that made CI install the stable toolchain with
# --force.
src="$(rustup run "${toolchain}" rustc --print sysroot)/lib/rustlib/src/rust/library/std/Cargo.toml"
[ -f "${src}" ] || { echo "error: ${toolchain} has no std sources at ${src}." >&2; exit 1; }

echo "${toolchain} is ready (rust-src, wasm32-unknown-unknown)."
