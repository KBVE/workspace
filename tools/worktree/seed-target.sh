#!/usr/bin/env bash
# Gives a freshly created worktree a warm Cargo target/, for free.
#
# Runs from the post-checkout hook, so it covers worktrees this repository's
# own tooling did not create -- Claude Code's worktree isolation, an MCP
# server, a bare `git worktree add`. Those all work now that setup.sh has
# taught git-crypt where its key is, but they leave an empty target/, and a
# cold build of this workspace is not cheap.
#
# The seed is an APFS copy-on-write clone of the main checkout's target/.
# Measured on this repository: cloning 25G cost 217M of real disk, and the
# first `cargo build -p jedi` afterwards recompiled that one crate in 8s
# because every dependency was still valid. Blocks un-share only as the
# worktree rebuilds them.
#
# Own target/ rather than a shared one on purpose: cargo holds a lock on the
# build directory for the whole build, so sharing one serialises every agent
# against every other, and against rust-analyzer.
#
# Does nothing unless all of these hold, because post-checkout also fires on
# every ordinary `git checkout`:
#   - this is a linked worktree, not the main checkout
#   - it has no target/ yet
#   - the main checkout has one to clone
set -euo pipefail

[ "${WORKTREE_SEED_TARGET:-1}" = "1" ] || exit 0

git_dir=$(git rev-parse --path-format=absolute --git-dir)
common=$(git rev-parse --path-format=absolute --git-common-dir)

# Equal in the main checkout, different in a linked worktree.
[ "$git_dir" != "$common" ] || exit 0

here=$(git rev-parse --show-toplevel)
main=$(dirname "$common")

[ -d "$here/target" ] && exit 0
[ -d "$main/target" ] || exit 0

# clonefile(2): APFS only, same volume only. Fails rather than falling back to
# a byte copy, which is the behaviour we want -- a silent 25G copy would be far
# worse than a cold build.
if cp -c -R "$main/target" "$here/target" 2>/dev/null; then
  # Incremental state is keyed to absolute paths, so none of it is valid here,
  # and it is the fastest-growing thing in the tree. Removing it is free: the
  # clone shares its blocks.
  rm -rf "$here/target/debug/incremental" "$here/target/release/incremental"
  echo "worktree: seeded target/ from $main (copy-on-write)"
else
  rm -rf "$here/target"
fi
