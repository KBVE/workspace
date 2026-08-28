# kbve

API layer and complexity handler for async HTTP, WebSocket, gRPC, and broadcasting.

## Installation

```bash
pip install kbve
```

## Development

Part of the [KBVE](https://github.com/kbve/kbve) monorepo. The moon project id
is `kbve-py`, not `kbve` — the `kbve` crate already owns that id in the project
graph. The distribution name is unaffected.

```bash
moon run kbve-py:test
moon run kbve-py:lint
moon run kbve-py:build
```

Python and uv are pinned in the workspace `.prototools`; `moon run kbve-py:install`
(a dependency of every task above) syncs the venv from `uv.lock`.

## What is not here

Ported from the Nx workspace, this package carried modules that read paths in
that repository: `kbve.nx` (workspace graph, security audit, content routing),
`kbve.sprite`, `kbve.blender`, `kbve.unreal`, `kbve.argocd`, `kbve.osrs`,
`kbve.seo`, `kbve.mdx`, `kbve.svg`, and `kbve.ai`. They were left behind along
with the 18 console scripts they provided. What ships is the server stack that
`kbve/__init__.py` exports.
