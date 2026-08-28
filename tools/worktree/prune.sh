#!/usr/bin/env bash
# Removes worktrees whose work has landed, and the branches they left behind.
#
# A merge happens on GitHub, so nothing local hears about it. The worktree stays
# on disk holding a target/ whose blocks have diverged from the main checkout by
# however much it rebuilt -- copy-on-write makes a worktree cheap to create, not
# free to keep. The branch outlives the worktree too: `git worktree remove` does
# not delete it, so a repository that has run a few agents accumulates wt/*
# refs pointing at commits that are already in main.
#
# Reports by default and changes nothing. Pass --apply to actually remove.
#
# Usage: prune.sh [--apply] [--no-fetch]
#
# "Landed" means landed on origin/main -- that is where a merge happens, and a
# branch cut from a local main that has not been pushed is genuinely not there
# yet. Override with WORKTREE_BASE if you need to compare against something
# else.
#
# "Landed" is decided in two ways, because the first is not always available:
#
#   1. `gh pr view` says the branch's PR is MERGED. Authoritative, and the only
#      signal that survives a squash merge -- which rewrites the commits, so the
#      branch is no longer an ancestor of main and ancestry checks say "not
#      merged" forever.
#   2. Failing that, the branch has no commits that origin/main lacks.
#
# A worktree with uncommitted changes is never touched, whatever either says.
set -euo pipefail

apply=0
fetch=1
for arg in "$@"; do
  case "$arg" in
    --apply)    apply=1 ;;
    --no-fetch) fetch=0 ;;
    *) echo "usage: prune.sh [--apply] [--no-fetch]" >&2; exit 1 ;;
  esac
done

base="${WORKTREE_BASE:-origin/main}"
root=$(git rev-parse --show-toplevel)
cd "$root"

# Comparing against a stale origin/main reports unmerged work as unmerged,
# which is the safe direction, but it also means the script does nothing useful
# on a repository nobody has fetched today.
if [ "$fetch" = "1" ]; then
  git fetch --quiet --prune origin main 2>/dev/null || \
    echo "note: could not fetch origin; comparing against a possibly stale $base"
fi

# MERGED / OPEN / CLOSED / NONE
pr_state() {
  gh pr view "$1" --json state --jq .state 2>/dev/null || echo NONE
}

landed() {
  local branch="$1"
  [ "$(pr_state "$branch")" = "MERGED" ] && return 0
  # No PR, or gh unavailable: fall back to ancestry.
  git rev-parse --verify --quiet "$base" >/dev/null || return 1
  [ "$(git rev-list --count "$base..$branch" 2>/dev/null || echo 1)" = "0" ]
}

removed=0 kept=0
say() { [ "$apply" = "1" ] && echo "$1" || echo "would $1"; }

# --- worktrees
while IFS= read -r line; do
  case "$line" in worktree\ *) wt_path="${line#worktree }" ;; branch\ *)
    branch="${line#branch refs/heads/}"
    case "$branch" in wt/*) ;; *) continue ;; esac
    [ "$wt_path" = "$root" ] && continue

    if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
      echo "keep   $branch -- uncommitted changes in $wt_path"
      kept=$((kept + 1)); continue
    fi
    if ! landed "$branch"; then
      echo "keep   $branch -- not in $base"
      kept=$((kept + 1)); continue
    fi

    say "remove $wt_path and branch $branch"
    if [ "$apply" = "1" ]; then
      git worktree remove "$wt_path"
      # -D, not -d: a squash merge leaves the branch un-merged by ancestry even
      # though its content is in main, and landed() already established that.
      git branch -D "$branch" >/dev/null
    fi
    removed=$((removed + 1))
  ;; esac
done < <(git worktree list --porcelain)

[ "$apply" = "1" ] && git worktree prune

# --- branches whose worktree is already gone
in_use=$(git worktree list --porcelain | sed -n 's/^branch refs\/heads\///p')
while IFS= read -r branch; do
  [ -n "$branch" ] || continue
  printf '%s\n' "$in_use" | grep -qxF "$branch" && continue
  if ! landed "$branch"; then
    echo "keep   $branch -- no worktree, not in $base"
    kept=$((kept + 1)); continue
  fi
  say "delete stranded branch $branch"
  [ "$apply" = "1" ] && git branch -D "$branch" >/dev/null
  removed=$((removed + 1))
done < <(git for-each-ref --format='%(refname:short)' 'refs/heads/wt/*')

echo
if [ "$apply" = "1" ]; then
  echo "Removed $removed, kept $kept."
else
  echo "$removed to remove, $kept kept. Re-run with --apply to do it."
fi
