#!/usr/bin/env bash
# Removes a worktree created by add.sh, and its branch if nothing is on it.
#
# `git worktree remove` refuses a dirty tree, which is the behaviour worth
# keeping -- a worktree an agent left work in should not vanish silently. Pass
# --force to override, same as git.
#
# The worktree's target/ goes with it. Its blocks were shared with the main
# checkout copy-on-write, so what this actually reclaims is whatever the
# worktree rebuilt for itself, not the whole tree.
#
# Usage: rm.sh <name> [--force]
set -euo pipefail

name="${1:?usage: rm.sh <name> [--force]}"
force="${2:-}"

root=$(git rev-parse --show-toplevel)
dest="${WORKTREE_ROOT:-$(dirname "$root")/.worktrees}/$name"
branch="wt/$name"

if [ ! -e "$dest" ]; then
  echo "rm.sh: no worktree at $dest" >&2
  git worktree prune
  exit 1
fi

git worktree remove ${force:+--force} "$dest"
git worktree prune

# Only if it holds nothing the main branch does not already have.
if git show-ref --verify --quiet "refs/heads/$branch"; then
  if git branch -d "$branch" >/dev/null 2>&1; then
    echo "Removed $dest and branch $branch."
  else
    echo "Removed $dest. Branch $branch kept -- it has unmerged commits."
    echo "Delete it with: git branch -D $branch"
  fi
else
  echo "Removed $dest."
fi
