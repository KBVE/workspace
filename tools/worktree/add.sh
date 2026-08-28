#!/usr/bin/env bash
# Creates a git worktree that this repository can actually build in.
#
# `git worktree add` on its own does not work here, and the failure is not
# obvious:
#
#   error: external filter '"git-crypt" smudge' failed
#   fatal: apps/arcade/rentearth-bevy/src/private/mod.rs: smudge filter git-crypt failed
#
# git-crypt keeps its key in the *common* git directory, at .git/git-crypt. A
# linked worktree's git dir is .git/worktrees/<name>, and git-crypt looks there,
# finds no key, and fails every encrypted path on checkout. The fix is to check
# out in two steps -- create the worktree empty, link the key into its git dir,
# then populate it.
#
# Everything else here is about disk. A second full checkout of this repository
# is cheap; a second copy of what a build leaves behind is not. Measured on the
# main tree: source 38M, target/ 25G.
#
# The worktree gets its own target/, seeded as an APFS copy-on-write clone of
# the main one. Measured: cloning the 25G target cost 217M of disk, and the
# first `cargo build -p jedi` in the new worktree recompiled that one crate in
# 8s -- every dependency was reused. Blocks un-share only as the worktree
# rebuilds them, so the cost tracks what an agent actually touches.
#
# Own target rather than a shared one because the shared one has a shared lock:
# cargo takes a file lock on the build directory for the whole build, so two
# agents compiling at once serialise, and so does rust-analyzer in the editor.
# The clone gives parallelism at roughly the disk cost of sharing.
#
# LFS needs no help. .lfsconfig sets fetchexclude=*, so a checkout materialises
# pointers rather than blobs, and the LFS object cache lives in the common git
# dir -- worktrees share it. A blob fetched by tools/lfs/ensure.sh in one
# worktree is a cache hit in the next.
#
# Usage: add.sh <name> [start-point]
#
#   add.sh fix-auth              # new branch wt/fix-auth from HEAD
#   add.sh fix-auth origin/main  # new branch wt/fix-auth from origin/main
#
# Location defaults to a sibling of the repository, .worktrees/<name>, so the
# project graph and the hasher never walk it. Override with WORKTREE_ROOT.
set -euo pipefail

name="${1:?usage: add.sh <name> [start-point]}"
start="${2:-HEAD}"

case "$name" in
  */*|.*) echo "add.sh: name must be a single path segment: $name" >&2; exit 1 ;;
esac

common=$(git rev-parse --path-format=absolute --git-common-dir)
root=$(git rev-parse --show-toplevel)
dest="${WORKTREE_ROOT:-$(dirname "$root")/.worktrees}/$name"

if [ -e "$dest" ]; then
  echo "add.sh: $dest already exists" >&2
  exit 1
fi

branch="wt/$name"
if git show-ref --verify --quiet "refs/heads/$branch"; then
  echo "add.sh: branch $branch already exists; check it out or pick another name" >&2
  exit 1
fi

# --no-checkout, because the key is not in place yet.
git worktree add --no-checkout -b "$branch" "$dest" "$start"

wt_gitdir=$(git -C "$dest" rev-parse --path-format=absolute --git-dir)

# git-crypt is optional: a clone that has never been unlocked has no key, and
# a worktree of it is still useful for everything outside the encrypted paths.
# Checkout below will fail loudly in that case, which is the correct outcome --
# it is the same failure the main checkout would give.
if [ -d "$common/git-crypt" ]; then
  ln -sfn "$common/git-crypt" "$wt_gitdir/git-crypt"
fi

git -C "$dest" checkout HEAD -- .

# Seed target/ from the main checkout's, copy-on-write.
#
# WORKTREE_TARGET picks the strategy:
#   clone   (default) own target/, CoW-seeded from the main checkout
#   own     own target/, empty -- first build is cold
#   shared  point cargo at the main checkout's target/ -- lowest disk, but
#           builds serialise against every other user of that directory
#
# `cp -c` is clonefile(2), which is APFS-only and same-volume-only. It fails
# rather than silently falling back to a byte copy, and a byte copy of 25G is
# not something to do by accident, so a failure downgrades to `own`.
target_mode="${WORKTREE_TARGET:-clone}"
case "$target_mode" in
  clone)
    if [ ! -d "$root/target" ]; then
      echo "note: $root/target does not exist yet; starting with an empty one"
      target_mode="own"
    elif cp -c -R "$root/target" "$dest/target" 2>/dev/null; then
      # Incremental state is keyed to absolute paths, so none of it is valid at
      # this new path. It is also the fastest-growing thing in the tree (5G of
      # the 27G measured after one build). Dropping it costs nothing -- the
      # clone shares its blocks -- and stops it being copied again on the next
      # worktree seeded from a tree that inherited it.
      rm -rf "$dest/target/debug/incremental" "$dest/target/release/incremental"
    else
      rm -rf "$dest/target"
      echo "note: copy-on-write clone unavailable (not APFS, or a different volume)"
      echo "      falling back to an empty target/ -- the first build will be cold"
      target_mode="own"
    fi
    ;;
  own) ;;
  shared)
    # Cargo discovers .cargo/config.toml by walking up from the working
    # directory, and that walk stays inside the worktree -- the main checkout's
    # config is never in scope, which is why this has to be a per-worktree file.
    # Written as a file rather than exported so an agent that runs a bare
    # `cargo build` still gets it.
    mkdir -p "$dest/.cargo"
    cat > "$dest/.cargo/config.toml" <<EOF
# Written by tools/worktree/add.sh. Not committed -- .gitignore covers it.
[build]
target-dir = "$root/target"
EOF
    ;;
  *)
    echo "add.sh: WORKTREE_TARGET must be clone, own, or shared (got: $target_mode)" >&2
    exit 1
    ;;
esac

case "$target_mode" in
  clone)  target_desc="own, cloned from $root/target ($(du -sh "$dest/target" | cut -f1) logical, near-zero on disk)" ;;
  own)    target_desc="own, empty" ;;
  shared) target_desc="shared with $root/target -- builds serialise" ;;
esac

cat <<EOF

Worktree ready.

  path    $dest
  branch  $branch
  target  $target_desc

LFS assets are pointers. A build that needs them fetches its own tree via
tools/lfs/ensure.sh; the objects are shared with the main checkout.

Node dependencies are not installed. Run \`pnpm install\` in the worktree if the
task needs them -- the pnpm store is global, so it costs little disk.

Remove it with:

  tools/worktree/rm.sh $name
EOF
