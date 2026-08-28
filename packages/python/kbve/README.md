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

## Content and rendering (`kbve.mdx`, `kbve.svg`, `kbve.ai`)

`kbve.svg` renders donut charts and DAGs to inline SVG at generation time, so a
page ships no diagram JavaScript — a 75-edge Mermaid flowchart costs roughly 4
seconds of blocked main thread. Output is MDX-safe. `kbve.mdx` is the Starlight
writer and escaper those pages are assembled with, and `kbve.ai` wraps
subprocess execution and Claude Code usage reporting.

All three are stdlib-only and hold no repository paths.

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
`kbve.nx` is gone for good: it read the Nx workspace graph, and moon replaced
it.

The rest are waiting on an app tree, not on a decision. Each hardcodes a path
that has no equivalent here yet:

| module | needs |
| --- | --- |
| `kbve.osrs`, `kbve.seo` | `apps/kbve/astro-kbve` content tree |
| `kbve.argocd` | `apps/kube` |
| `kbve.unreal` | `apps/rentearth/unreal-rentearth` |
| `kbve.sprite.ship_footprint` | `apps/agones/arpg/{web,server}` |

Porting them before their consumers would mean shipping paths already known to
be wrong, so they stay upstream until there is something to point at. The rest
of `kbve.sprite` did come across — its baker and image passes folded into
`kbve.blender`, which is what they always were.
