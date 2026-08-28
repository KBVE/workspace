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
# Local config, so it is per-clone and has to be re-run after `git-crypt
# unlock` (which rewrites these three keys back to their relative form).
# Idempotent: run it whenever.
set -euo pipefail

common=$(git rev-parse --path-format=absolute --git-common-dir)
key="$common/git-crypt/keys/default"

if [ ! -f "$key" ]; then
  echo "setup.sh: no git-crypt key at $key" >&2
  echo "  This clone has never been unlocked. Run 'git-crypt unlock <keyfile>' first." >&2
  exit 1
fi

git config filter.git-crypt.smudge "git-crypt smudge --key-file=$key"
git config filter.git-crypt.clean  "git-crypt clean --key-file=$key"
git config diff.git-crypt.textconv "git-crypt diff --key-file=$key"

echo "git-crypt filters now name the key by absolute path; worktrees will check out."
