#!/usr/bin/env bash
# Materialises the LFS blobs a project needs, and nothing else.
#
# Run as a dependency of the build, so `moon run <project>:build` produces a
# working artifact on a fresh clone without anyone knowing this repository uses
# LFS. The blob store is shared across games and already holds hundreds of
# objects, so the scope is one project's tree rather than the whole store.
#
# Checks before it fetches. `git lfs pull` on an already-complete tree still
# makes a batch request, and the build depends on this task, so an unconditional
# pull would put a network round trip in front of every local build. Deciding
# from the working tree costs nothing and is correct: a pointer is 130-odd bytes
# beginning with a known line.
#
# Usage: ensure.sh <include pattern>     e.g. apps/arcade/rentearth-bevy/**
set -euo pipefail

include="${1:?usage: ensure.sh <include pattern>}"

command -v git-lfs >/dev/null 2>&1 || {
  echo "::error::git-lfs is not installed. See https://git-lfs.com."
  exit 1
}

# -I takes the pattern; a trailing pathspec would be read as a ref instead and
# fail with "not a valid object name".
pointers=$(git lfs ls-files -n -I "$include" | while read -r f; do
  [ -f "$f" ] || { echo "$f"; continue; }
  head -c 42 "$f" 2>/dev/null | grep -q 'git-lfs.github.com/spec' && echo "$f" || true
done)

if [ -z "$pointers" ]; then
  exit 0
fi

count=$(printf '%s\n' "$pointers" | wc -l | tr -d ' ')
echo "Fetching $count LFS object(s) for $include"

if ! git lfs pull --include="$include"; then
  cat >&2 <<'MSG'
::error::Could not fetch LFS objects.

The blobs live on the Forgejo instance named in .lfsconfig, which needs an
account. Authenticate once and the system credential helper remembers it:

  git lfs pull --include="<pattern>"      # prompts for username and token

Create a token at https://git.kbve.com/user/settings/applications.
MSG
  exit 1
fi
