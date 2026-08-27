#!/usr/bin/env bash
# Refuse to commit plaintext into a git-crypt path.
#
# The case this exists for: a clone that has never run `git-crypt unlock` has no
# filter installed, so a file added under private/ is committed in the clear.
# `git-crypt status` reports such a file as "encrypted" — it describes the
# working tree, not the blob — so the tool that should catch this says nothing.
#
# Checked against the staged blob, which is what actually lands in history.
set -euo pipefail

fail=0
staged=$(git diff --cached --name-only --diff-filter=ACMR)
[ -z "$staged" ] && exit 0

while IFS= read -r file; do
  [ -z "$file" ] && continue

  # Only paths git itself says are git-crypt filtered.
  filter=$(git check-attr filter -- "$file" | sed 's/.*: //')
  [ "$filter" != "git-crypt" ] && continue

  # A git-crypt blob starts with NUL followed by "GITCRYPT".
  if ! git cat-file -p ":$file" 2>/dev/null | head -c 9 | grep -q 'GITCRYPT'; then
    if [ "$fail" -eq 0 ]; then
      echo "pre-commit: plaintext staged in an encrypted path" >&2
      echo >&2
    fi
    echo "  $file" >&2
    fail=1
  fi
done <<< "$staged"

if [ "$fail" -eq 1 ]; then
  cat >&2 <<'MSG'

These files match a git-crypt rule but are staged unencrypted. Committing them
would put their contents in history permanently, where encrypting them later
cannot reach.

Usually this means the clone is locked. Run:

  git-crypt unlock <key>
  git add <paths>

Then commit again.
MSG
  exit 1
fi

# Advisory: game source outside an encrypted path. Not a failure — plenty of it
# is meant to be public — but worth seeing before it is pushed.
loose=$(printf '%s\n' "$staged" \
  | grep -E '^apps/.*\.(gd|gdshader|cs)$' \
  | grep -v '/private/' \
  | grep -v '/addons/' || true)

if [ -n "$loose" ]; then
  echo "pre-commit: game source staged outside private/ (public once pushed):" >&2
  printf '%s\n' "$loose" | sed 's/^/  /' >&2
  echo >&2
fi

exit 0
