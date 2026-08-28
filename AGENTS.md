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
  because git-crypt looks for its key in `.git/worktrees/<name>`. Re-run it
  after `git-crypt unlock`, which rewrites those filters back.
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

## Toolchains

Versions are pinned in `.prototools` and `.moon/toolchains.yml`; `rust-toolchain.toml`
is kept in sync by hand. Prefer `moon run <project>:<task>` over calling cargo,
pnpm, or buf directly — the task declares the inputs and outputs that make the
cache work, and a direct invocation silently skips it.
