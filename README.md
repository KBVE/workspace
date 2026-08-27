# KBVE Workspace

A [moon](https://moonrepo.dev) monorepo.

Secrets never enter this repository. `.env` and `env.sh` are ignored; values
come from the secret manager and CI reads them from GitHub Actions secrets.

## Layout

| Path        | Holds                                              |
| ----------- | -------------------------------------------------- |
| `apps/`     | Deployable frontends (Astro, game clients)          |
| `services/` | Deployable backends (Rust crates, workers)          |
| `packages/` | Shared TypeScript libraries                         |
| `crates/`   | Shared Rust libraries                               |
| `tools/`    | Internal CLIs and scripts                           |
| `infra/`    | Deploy manifests, Docker, CI helpers                |
| `docs/`     | Documentation                                       |
| `packages/proto/` | Protobuf schemas — source of truth for every wire type |

## Setup

    proto use                 # installs node, pnpm, rust, moon from .prototools
    pnpm install
    moon run proto:generate   # generates ts/rust/csharp/python from the schemas

## Common commands

    moon check --all          # build + test + lint every affected project
    moon run :build           # run the `build` task in every project
    moon run <project>:<task> # run one task
    moon query projects       # list the project graph

## Adding a project

Create the directory under the right root, add a `moon.yml` declaring its
`type`/`language`, and it is picked up by the globs in `.moon/workspace.yml`.
Node projects inherit tasks from `.moon/tasks/node.yml`, Rust from
`.moon/tasks/rust.yml`.
