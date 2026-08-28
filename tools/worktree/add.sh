#!/usr/bin/env bash
# Creates a worktree for an agent or a parallel branch.
#
# Most of what this used to do now happens at the git level, so a bare
# `git worktree add` works too -- which matters, because agents and MCP tooling
# create worktrees themselves and will never call this script:
#
#   tools/worktree/setup.sh        teaches git-crypt where its key is, so the
#                                  checkout does not die on encrypted paths
#   tools/worktree/seed-target.sh  runs from post-checkout and clones the main
#                                  checkout's target/ copy-on-write
#
# What is left here is the convenience layer: naming, placement, branch
# creation, target strategy, and telling you what you got.
#
# Usage: add.sh <name> [start-point]
#
#   add.sh fix-auth              # new branch wt/fix-auth from HEAD
#   add.sh fix-auth origin/main  # new branch wt/fix-auth from origin/main
#
# Lands in .worktrees/<name> beside the repository, so moon's project globs and
# the hasher never walk it. Override with WORKTREE_ROOT.
#
# WORKTREE_TARGET picks how Cargo's target/ is handled:
#   clone   (default) own target/, copy-on-write seeded from the main checkout
#   own     own target/, empty -- first build is cold
#   shared  point cargo at the main checkout's target/. Lowest disk, but cargo
#           locks the build directory for the whole build, so this serialises
#           against every other worktree and against rust-analyzer.
set -euo pipefail

name="${1:?usage: add.sh <name> [start-point]}"
start="${2:-HEAD}"

case "$name" in
  */*|.*) echo "add.sh: name must be a single path segment: $name" >&2; exit 1 ;;
esac

root=$(git rev-parse --show-toplevel)
dest="${WORKTREE_ROOT:-$(dirname "$root")/.worktrees}/$name"
branch="wt/$name"
target_mode="${WORKTREE_TARGET:-clone}"

case "$target_mode" in clone|own|shared) ;; *)
  echo "add.sh: WORKTREE_TARGET must be clone, own, or shared (got: $target_mode)" >&2
  exit 1 ;;
esac

[ -e "$dest" ] && { echo "add.sh: $dest already exists" >&2; exit 1; }
git show-ref --verify --quiet "refs/heads/$branch" && {
  echo "add.sh: branch $branch already exists; check it out or pick another name" >&2
  exit 1; }

# Idempotent, and cheap enough to just do. Without it the checkout below fails
# on every git-crypt path. Not fatal if the clone was never unlocked -- the
# checkout will say so itself, exactly as it would in the main checkout.
bash "$root/tools/worktree/setup.sh" >/dev/null 2>&1 || true

# The post-checkout hook does the seeding; this only decides whether to let it.
if [ "$target_mode" = "clone" ]; then
  git worktree add -b "$branch" "$dest" "$start"
else
  WORKTREE_SEED_TARGET=0 git worktree add -b "$branch" "$dest" "$start"
fi

if [ "$target_mode" = "shared" ]; then
  # Cargo finds .cargo/config.toml by walking up from the working directory,
  # and that walk stays inside the worktree -- the main checkout's config is
  # never in scope, so this has to be a per-worktree file. A file rather than
  # an exported variable, so a bare `cargo build` still picks it up.
  mkdir -p "$dest/.cargo"
  cat > "$dest/.cargo/config.toml" <<EOF
# Written by tools/worktree/add.sh. Not committed -- .gitignore covers it.
[build]
target-dir = "$root/target"
EOF
fi

case "$target_mode" in
  clone)  desc=$([ -d "$dest/target" ] \
            && echo "own, cloned from $root/target ($(du -sh "$dest/target" | cut -f1) logical, near-zero on disk)" \
            || echo "own, empty -- copy-on-write unavailable, first build will be cold") ;;
  own)    desc="own, empty" ;;
  shared) desc="shared with $root/target -- builds serialise" ;;
esac

cat <<EOF

Worktree ready.

  path    $dest
  branch  $branch
  target  $desc

LFS assets are pointers; a build that needs them fetches its own tree via
tools/lfs/ensure.sh, and the objects are shared with the main checkout.

Node dependencies are not installed. Run \`pnpm install\` if the task needs
them -- the pnpm store is global, so it costs little disk.

Remove with: tools/worktree/rm.sh $name
EOF
