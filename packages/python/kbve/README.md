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

Headless bakers, launched into Blender's own Python:

```bash
kbve-blender-retarget --char <rig.glb> --anims <src.glb> --out <o.glb> --clips idle,run
kbve-blender-vat --src <anim.fbx> --out <dir> --tris 1200 --frames 32
kbve-blender-turf --out <dir> --res 2048
kbve-model-sprites --model <x.obj> --skin <s.jpg> --out <dir> --frames 16 --res 256
```

Each locates Blender via `--blender`, `$BLENDER`, `PATH`, then the macOS app
bundle.

Image passes either side of a bake, which never enter Blender:

```bash
kbve-sprite-postprocess --dir render_flat --res 512
kbve-skin-variant --in skin.jpg --out skin_off.jpg
```

These are what the `blender` extra is for — the bakers need no install, since
Blender brings its own interpreter, while these need Pillow and numpy.

## What is not here

Ported from the Nx workspace, this package carried modules that read paths in
that repository: `kbve.nx` (workspace graph, security audit, content routing),
`kbve.unreal`, `kbve.argocd`, `kbve.osrs`, `kbve.seo`, `kbve.mdx`, `kbve.svg`,
and `kbve.ai`. They were left behind along with 12 of the 18 console scripts
they provided.

`kbve.sprite` is gone as a package but not as code: its baker and image passes
folded into `kbve.blender`, which is what they were. What stayed behind is
`ship_footprint`, which regenerates collision data into
`apps/agones/arpg/{web,server}` — an app tree that did not migrate.
