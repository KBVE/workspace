#!/usr/bin/env bash
# Removes a worktree created by add.sh, and the branch if nothing is on it.
#
# `git worktree remove` refuses a dirty tree, which is the behaviour worth
# keeping -- a worktree an agent left work in should not vanish silently. Pass
# --force to override, same as git.
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

# The symlinked git-crypt key is a link, not a copy, so removing the worktree
# cannot take the key with it. Dropped first anyway: `git worktree remove`
# deletes the administrative directory, and leaving a dangling link into a
# deleted path in the log is noise.
wt_gitdir=$(git -C "$dest" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)
[ -n "$wt_gitdir" ] && [ -L "$wt_gitdir/git-crypt" ] && rm -f "$wt_gitdir/git-crypt"

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
