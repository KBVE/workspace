# Rehearsing the generated release notes

`release.yml` now drafts a GitHub release from `tools/release/notes.mjs`. Every
part of that has run except the `gh release` call itself, which only happens on
a pushed tag. This is the sequence for exercising it on a project where a wrong
answer costs nothing.

## Where it already stands

The workflow changes are **already on `origin/main`** — a parallel session
pushed them:

| Commit | |
|---|---|
| `995f529` | `notes.mjs` and its tests |
| `c7945da` | `release.yml` drafts the release |
| `1b8d1b9` | `ci.yml` checks commit messages on push |
| `e61479e`, `7958e2d` | `AGENTS.md` |

The `commits` job **ran and passed** on run `33242522525`, so that half is
proven rather than assumed. What has never run is `gh release create`.

Still local, not pushed:

- `aa55996 fix(release): preview the notes for a tag that does not exist yet`
- `817a0d0 chore(moon): bound the CAS, and stop tools/ inventing projects` (not
  from this work)

## Two things to know before starting

**`main` is red.** Run `33242522525` failed on `jedi:lint`, from
`e67eba0 perf(kbve-proto): stop charging every consumer for a gRPC stack`.
Unrelated to the release tooling, but tagging a red commit ships a version whose
lint does not pass. Decide whether that matters before tagging, or fix it first.

**The working tree has changes from another session.** `.moon/workspace.yml`,
`apps/arcade/rentearth-bevy/src/private/units/*`, and an untracked
`packages/python/fudster/`. None belong to this work. Commit with an explicit
pathspec — `git commit -- <paths>` — so none of it is swept in.

## Why rentearth-api is the rehearsal

It carries no graph tags (`moon query projects --id rentearth-api` → `tags: []`),
so neither `itch.yml` nor `protobuf-publish.yml` claims it and `release.yml`
takes the "Nothing to publish yet" branch. Nothing is uploaded anywhere. Its
manifest already says `0.1.0`, so no version bump is needed — the rehearsal is
the release.

Checked and passing already:

```
gh auth status                                     # h0lybyte, scopes incl. repo + workflow
node --test tools/release/ tools/commit/           # green
node tools/release/verify-tag.mjs rentearth-api@0.1.0
node tools/release/notes.mjs rentearth-api@0.1.0   # previews from HEAD
```

## The window

**1. Push what is left.**

```bash
git log --oneline origin/main..main    # expect aa55996 and 817a0d0, nothing else
git push
```

**2. Preview the notes.** Same code the workflow runs. Reads from HEAD and says
so, because the tag does not exist yet.

```bash
node tools/release/notes.mjs rentearth-api@0.1.0
```

**3. Tag and push it.** The tag has to sit on a commit that already contains
`c7945da`, or the old `release.yml` runs and nothing is created.

```bash
git tag rentearth-api@0.1.0
git push origin rentearth-api@0.1.0
```

**4. Check the run.**

```bash
gh run list --workflow release.yml --limit 3
gh release view rentearth-api@0.1.0
```

Expected: a **draft**, titled `rentearth-api@0.1.0`, listing only commits that
touched `services/api/rentearth-api`, with no "Full changelog" line because it
is a first release.

## Failure modes worth recognising

- **Empty notes, job green.** The `fetch-depth: 0` failure mode — the checkout
  did not have the history. It cannot error, only come back empty.
- **No release at all, job green.** The tag predates `c7945da`, so the old
  workflow ran. Delete the tag and re-tag on a newer commit.
- **Permission error on `gh release create`.** The job-level `permissions:
  contents: write` did not apply; the workflow default is `read`.

## After

Only then tag a game. `rentearth-bevy` goes through `itch.yml` as well, so a
mistake there is a bad build on a public itch page rather than an empty draft.

## Known gap

A commit in a dependency (`bevy_tasker` for `rentearth-bevy`) ships inside the
artifact but touches no path under the project's own source, so it will not
appear in the notes. `moon query projects` does not return `dependsOn`; picking
those up needs `moon project-graph --json` and a transitive walk.
