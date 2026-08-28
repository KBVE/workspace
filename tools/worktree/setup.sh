#!/usr/bin/env bash
# Makes plain `git worktree add` work in this repository.
#
# git-crypt keeps its key in the common git directory and finds it through
# `git rev-parse --git-dir`. In a linked worktree that resolves to
# .git/worktrees/<name>, where there is no key, so every encrypted path fails
# its smudge filter and the checkout dies:
#
#   error: external filter '"git-crypt" smudge' failed
#
# git-crypt 0.8 takes --key-file on smudge, clean, and diff, so naming the key
# by absolute path removes the lookup entirely. Worth doing at the git level
# rather than in a wrapper: it fixes `git worktree add` itself, and so fixes
# every tool that shells out to it -- Claude Code's worktree isolation, an MCP
# server, a script nobody has written yet.
#
# This has to be re-applied, not just done once. `git-crypt unlock` rewrites
# all three keys back to their relative form -- verified, not assumed -- which
# silently re-breaks worktree creation until something puts them back. The
# post-checkout hook runs `--if-needed` for exactly that reason: unlock does a
# checkout, so the hook fires on the way out and repairs the config it just
# undid.
#
# Local config, so it is per-clone. Idempotent: run it whenever.
#
# Usage: setup.sh [--if-needed]
#
#   --if-needed  say nothing and change nothing unless the config has drifted;
#                exit 0 on a locked repository rather than complaining. For
#                hooks, where noise on every checkout is worse than useless.
set -euo pipefail

quiet=0
[ "${1:-}" = "--if-needed" ] && quiet=1

common=$(git rev-parse --path-format=absolute --git-common-dir)
key="$common/git-crypt/keys/default"

# `git-crypt lock` removes the key and deconfigures the filters together. A
# locked repository is a legitimate state, so repairing the filters behind
# lock's back would be wrong -- it would leave filters pointing at a key that
# is not there.
if [ ! -f "$key" ]; then
  [ "$quiet" = "1" ] && exit 0
  echo "setup.sh: no git-crypt key at $key" >&2
  echo "  This clone is locked or has never been unlocked." >&2
  echo "  Run 'git-crypt unlock <keyfile>' first." >&2
  exit 1
fi

want="git-crypt smudge --key-file=$key"
if [ "$quiet" = "1" ] && [ "$(git config --get filter.git-crypt.smudge || true)" = "$want" ]; then
  exit 0
fi

git config filter.git-crypt.smudge "$want"
git config filter.git-crypt.clean  "git-crypt clean --key-file=$key"
git config diff.git-crypt.textconv "git-crypt diff --key-file=$key"

if [ "$quiet" = "1" ]; then
  echo "git-crypt: repaired the filter config so worktrees can check out"
else
  echo "git-crypt filters now name the key by absolute path; worktrees will check out."
fi
