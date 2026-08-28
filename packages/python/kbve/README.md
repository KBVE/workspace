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

## Blender toolchain (`kbve.blender`, `--extra blender`)

Headless asset tools launched into Blender's own Python:

```bash
kbve-blender-retarget --char <rig.glb> --anims <src.glb> --out <o.glb> --clips idle,run
kbve-blender-vat --src <anim.fbx> --out <dir> --tris 1200 --frames 32
kbve-blender-turf --out <dir> --res 2048
```

Each locates Blender via `--blender`, `$BLENDER`, `PATH`, then the macOS app
bundle. `kbve.blender.pack_orm` is the exception -- it never enters Blender and
needs only Pillow, which is what the `blender` extra installs.

## What is not here

Ported from the Nx workspace, this package carried modules that read paths in
that repository: `kbve.nx` (workspace graph, security audit, content routing),
`kbve.sprite`, `kbve.unreal`, `kbve.argocd`, `kbve.osrs`, `kbve.seo`,
`kbve.mdx`, `kbve.svg`, and `kbve.ai`. They were left behind along with 15 of
the 18 console scripts they provided.
