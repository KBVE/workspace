#!/usr/bin/env bash
# Commit-time guards: encrypted paths, and repository hygiene.
#
# --- 1. Refuse to commit plaintext into a git-crypt path.
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

# `git commit -- <paths>` builds a temporary index and leaves the real one
# alone, so there is nothing here to look at and every check below is skipped.
# That is a hole rather than a quiet pass: it is the form a coding agent
# reaches for, and it is exactly the form that most needs the guard. Say so.
if [ -z "$staged" ]; then
  if ! git diff --quiet HEAD -- 2>/dev/null; then
    echo "pre-commit: nothing staged, so the encrypted-path guard did not run" >&2
    echo "  (a pathspec commit bypasses it; stage with 'git add' to be checked)" >&2
  fi
  exit 0
fi

while IFS= read -r file; do
  [ -z "$file" ] && continue

  # Only paths git itself says are git-crypt filtered.
  filter=$(git check-attr filter -- "$file" | sed 's/.*: //')
  [ "$filter" != "git-crypt" ] && continue

  # A git-crypt blob starts with NUL followed by "GITCRYPT".
  #
  # Read into a variable rather than piped into a matcher, because the obvious
  # way to write this is wrong twice over on a mac.
  #
  # `grep -q 'GITCRYPT'` exits 1 on a correctly encrypted blob: the leading NUL
  # makes BSD grep call the input binary, and a binary match without -a is
  # reported the same as no match. And once that is fixed with -a, grep exits
  # the moment it matches, which closes the pipe under git and returns 141
  # through `pipefail` -- so the check that now finds the magic still fails.
  # Both faults point the same way, at "this file is plaintext", which is the
  # one answer that stops a commit.
  #
  # Command substitution drops the NUL, which is why the pattern is matched
  # loosely rather than anchored at byte one.
  magic=$(git cat-file -p ":$file" 2>/dev/null | head -c 9 || true)
  case "$magic" in
    *GITCRYPT*) continue ;;
  esac

  if [ "$fail" -eq 0 ]; then
    echo "pre-commit: plaintext staged in an encrypted path" >&2
    echo >&2
  fi
  echo "  $file" >&2
  fail=1
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

# --- 2. Refuse a new top-level dot-directory that is not allowlisted.
#
# Editors and coding agents write per-machine state into a dot-directory at the
# repository root. .hallmark/log.json reached main this way, in the same
# `git add -A` that swept in the game tree. A .gitignore entry only stops the
# tools that already exist; the next one invents a directory nobody has listed.
#
# Allowlisted below is everything the repository genuinely keeps at the root.
# Adding to it should be a deliberate line in a diff.
allowed='^\.(github|moon|vscode|proto|cargo|husky)$'

new_dotdirs=$(git diff --cached --name-only --diff-filter=A \
  | grep -E '^\.[^/]+/' \
  | cut -d/ -f1 \
  | sort -u \
  | grep -Ev "$allowed" || true)

if [ -n "$new_dotdirs" ]; then
  cat >&2 <<MSG
pre-commit: new top-level dot-directory staged

$(printf '%s\n' "$new_dotdirs" | sed 's/^/  /')

This is usually per-machine state written by an editor or a coding agent, and
it does not belong in a public repository. Add it to .gitignore.

If it is genuinely repository configuration that every clone needs, add it to
the allowlist in tools/hooks/pre-commit.sh so the decision is visible in a
diff.
MSG
  exit 1
fi

# --- 3. Advisory: game source outside an encrypted path. Not a failure — plenty of it
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
