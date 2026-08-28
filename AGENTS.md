# Agent notes

Conventions an agent cannot infer from the tree. Everything else — project
layout, task names, ownership — is in `.moon/workspace.yml` and each project's
`moon.yml`, and `moon query projects` will tell you the rest.

## Worktrees

Working in a worktree is the normal way to run in parallel here. A bare
`git worktree add` is fine: git-crypt and the Cargo target directory are both
handled at the git level, so tooling that creates its own worktrees — an
agent's isolation mode, an MCP server — gets the same treatment.

`tools/worktree/add.sh <name>` adds naming, placement, and a summary on top:

```bash
tools/worktree/add.sh fix-auth        # .worktrees/fix-auth, branch wt/fix-auth
tools/worktree/rm.sh  fix-auth        # refuses a dirty tree without --force
```

What is already taken care of:

- **git-crypt.** `tools/worktree/setup.sh` points the filters at the key by
  absolute path. Without it a worktree checkout dies on every encrypted path,
  because git-crypt looks for its key in `.git/worktrees/<name>`.
  `git-crypt unlock` rewrites those filters back, so the post-checkout hook
  re-applies them — unlock does a checkout, which is what fires the hook. It is
  silent unless it actually changes something, and it stays out of the way of
  `git-crypt lock`, which removes the key and the filters together.
- **Cargo.** The post-checkout hook copy-on-write clones the main checkout's
  `target/`. A new worktree costs ~200M of real disk instead of 25G, and builds
  reuse every dependency. Each worktree owns its `target/` on purpose: cargo
  locks the build directory for a whole build, so a shared one would serialise
  agents against each other and against rust-analyzer.
- **Git LFS.** `.lfsconfig` sets `fetchexclude=*`, so assets check out as
  pointers. The object cache is in the common git dir and shared. A build that
  needs real bytes fetches its own subtree via `tools/lfs/ensure.sh` — do not
  run a bare `git lfs pull`, which drags in hundreds of megabytes of another
  game's models.
- **moon.** `cache.unstable_sharedWorktreeCache` shares task output blobs from
  the base checkout, so a fresh worktree does not re-run builds whose outputs
  already exist on this machine.

Not done for you: `pnpm install`, if the task needs node modules.

## Committing

This repository often has more than one agent or session working in it at once.
**Commit with a pathspec** — `git commit -- <paths>` — rather than `git add`
followed by a bare `git commit`. The pathspec form commits only those paths and
ignores whatever else is sitting in the index. A bare commit picks up another
session's staged files, and the fix for that is a history rewrite racing
against the session that caused it.

For the same reason, never `git add -A`.

## Commits

Conventional commits, and they are enforced rather than encouraged. The
`commit-msg` hook runs `tools/commit/validate.mjs`, and CI checks pull request
titles the same way — the labeller reads the type out of the title, so an
unconventional one silently gets no `kind/*` label.

```
type(scope): subject          fix(laser): stop the resource pools going negative
```

**Types** are the `commit` fields on the kind labels in
`tools/labels/labels.yml`, so `feat` meaning `kind/feature` is stated once:
`feat`, `content`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `build`,
`perf`, `release`. `content` counts as a feature — game text and data are what
ships, not prose about the software.

**Scopes** are moon project ids, the five `area/*` group names, or one of the
repository-wide scopes in `tools/commit/scopes.yml` (`ci`, `moon`, `agents`,
`repo`, `deps`). That is what keeps a commit attributable to a project. A scope
that could mean several projects is rejected: write `rentearth-bevy` or
`rentearth.com`, not `rentearth`.

Subjects are lower case, no full stop. The hook reads
`tools/labels/labels.lock.json` rather than starting moon, so it costs about
40ms per commit.

## Getting work back to main

Push the branch and open a pull request. Do not merge it, and never push to
`main` directly.

```bash
git push -u origin wt/<name>
gh pr create --draft --base main --title "<conventional commit subject>"
```

Open it as a draft and say so when you report back, with the URL. Marking it
ready, merging, and closing are the user's calls.

Once something merges, nothing local hears about it: the worktree stays on disk
and `git worktree remove` would not have deleted the branch anyway. Clean up
with

```bash
tools/worktree/prune.sh            # report only
tools/worktree/prune.sh --apply    # actually remove
```

It removes worktrees whose branch has landed on `origin/main`, deletes their
branches, and picks up `wt/*` branches whose worktree is already gone. A
worktree with uncommitted changes is never touched. It asks `gh` whether the
PR is MERGED before falling back to ancestry, because a squash merge rewrites
the commits and ancestry alone would call the branch unmerged forever.

`ci.yml` and `protobuf-ci.yml` both trigger on `pull_request`, so pushing the
branch is what gets the work checked. `moon ci` decides what to run by
comparing against the base branch, which is why the workflow checks out with
`fetch-depth: 0` -- nothing for you to do, but it is the reason a PR is more
useful here than a local commit.

Review assignment is automatic: `.github/CODEOWNERS` is generated by moon from
each project's `moon.yml`, so whoever owns the touched projects is requested.

**Never push a tag.** Tags matching `*@*` are the release trigger --
`release.yml` verifies and publishes, and `itch.yml` ships game builds to itch.
Releasing is not something to do on the way to merging a branch.

## Labels

`tools/labels/labels.yml` is the source of truth for every label this
repository uses. Four families, prefixed so GitHub's substring picker can
narrow to one:

- `kind/*` — what the work is (`bug`, `feature`, `security`, `refactor`,
  `docs`, `test`, `chore`, `plan`, `question`)
- `status/*` — why it is not moving (`needs-triage`, `blocked`, `in-progress`,
  and the terminal `duplicate`, `invalid`, `wontfix`)
- `area/*` — which top-level group it touches
- `tag/*` — the moon tag vocabulary
- `0`–`6` — severity, kept under its original bare names. The one family
  without a prefix

`area/*` and `tag/*` are not applied by hand-maintained lists of projects:
`tools/labels/sync.mjs` reads the moon project graph, so adding `tags: ['npm']`
to a `moon.yml` is what makes `tag/npm` meaningful.

That runs both directions. **`labels.yml` also defines which tags a `moon.yml`
is allowed to declare.** moon cannot enforce this itself — `constraints` only
offers `enforceLayerRelationships` and `tagRelationships` — so `moon run
labels:check` does, and it fails on a tag the vocabulary does not contain.
Without it a typo would quietly mint a label and `tag/bevy` and `tag/bevvy`
would both look official.

```bash
moon run labels:check                        # offline. No API calls at all
node tools/labels/sync.mjs --write-lock      # after editing labels.yml or tags
node tools/labels/sync.mjs --remote          # compare with GitHub, report only
node tools/labels/sync.mjs --apply           # write to GitHub
```

Pull requests are labelled automatically. `.github/workflows/label-pr.yml`
runs `tools/labels/label-pr.mjs`, which reads the lock and nothing else: the
title's conventional-commit type gives `kind/*`, and the changed paths give
`area/*` and `tag/*` through the route map. The kind is reconciled, so
retitling a pull request from `feat()` to `fix()` moves the label rather than
leaving both; scope labels are only added, and anything outside those three
families is never touched. `--explain` shows what it would do without calling
GitHub:

```bash
node tools/labels/label-pr.mjs --explain "fix(fish-and-chip): x" apps/arcade/fish-and-chip/src/game.ts
```

`labels.lock.json` is generated and committed. It holds the resolved label set
and a `routes` map from every project source to the `area/*` and `tag/*` labels
it implies, so tooling can turn changed paths into labels without running moon
or calling the API. Regenerate it with `--write-lock`; the check fails if it is
stale, which is why the default run touches no network.

What it deliberately does **not** cache is GitHub's own label state. A snapshot
of that goes stale the moment someone edits a label in the web UI, and a cache
that can be quietly wrong is worse than none in a system built to catch drift.
Everything in the lock is derived from files in this repository, so it is
reproducible rather than remembered.

Adding a tag is two deliberate lines: the entry in `labels.yml` and the
`moon.yml` that uses it. Either alone fails the check or is reported as dead.

The sync deletes only what `labels.yml` lists under `retire`, which is two
contribution signals this repository has no audience for. Where a declared label has an older synonym already on
GitHub, `supersedes` in `labels.yml` makes the sync **rename** it — `bug`
becomes `kind/bug` — so the label and anything filed under it survive and the
duplicate spelling stops existing. Everything else it does not describe is
reported as unmanaged and left alone.

Labels are per-repository. The sync targets whichever repository the working
directory belongs to, and prints it before doing anything; the other KBVE
repositories are untouched and share no label set with this one.

## Toolchains

Versions are pinned in `.prototools` and `.moon/toolchains.yml`; `rust-toolchain.toml`
is kept in sync by hand. Prefer `moon run <project>:<task>` over calling cargo,
pnpm, or buf directly — the task declares the inputs and outputs that make the
cache work, and a direct invocation silently skips it.
