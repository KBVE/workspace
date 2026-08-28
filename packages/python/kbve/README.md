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

## SEO auditing (`kbve.seo`)

Static frontmatter and MDX analysis of any Astro content collection. No build,
no browser, no network — so it runs in CI on the files a site is authored from.

Two modes over one rule set:

```bash
# source: the .mdx an author edits. No build, no browser, runs on one changed file.
kbve-seo-audit  --content apps/website/rentearth.com/src/content

# build: the HTML that ships. Sees what the layout computed.
kbve-seo-audit  --dist    apps/website/rentearth.com/dist
kbve-seo-report --dist    apps/website/rentearth.com/dist --rule desc-length
```

Neither replaces the other. Source findings name a file you can open, and are
cheap enough to run per pull request — but they cannot see the wrapped title,
the fallback description or the derived canonical, and they only cover pages
that *are* content files (`/` and `/404/` are routes, not collection entries).
Build findings are what search engines get, and cost a build to produce.

The one thing source mode cannot infer, the site states in its `seo.toml`:

```toml
[default]
title_template = "{title} — RentEarth"
```

Without it, a site that suffixes its titles has every page measured short by
the length of the suffix. `--dist` ignores the setting, because there the
rendered `<title>` already is the answer.

Exit status is the contract: `0` clean, `1` error-severity findings, `2` the
tool could not run. A bad path is never a failing site.

Rules that describe an authoring convention (`tags`, `sem`, `draft`, JSON-LD
`source_path`) run only over source; rendered HTML has no counterpart for them.
Rules about the search result skip a `noindex` page entirely — it will never
appear in one.

Thresholds and per-collection switches live in a `seo.toml` the site owns,
found automatically beside the content or at the project root:

```toml
[default]
desc_min = 50

[collections.blog]
body_min_chars = 800
require_tags = true
```

Without one, the defaults apply — and those are limited to what is true of any
indexed page: a title, a description that survives the search result, headings
that descend one level at a time, images with alt text, no duplicate titles,
and no broken relative links. Anything that encodes one site's convention
(`tags`, `sem`, JSON-LD `source_path`, a social card) is off until a profile
asks for it.

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
| `kbve.osrs` | `apps/kbve/astro-kbve` content tree |
| `kbve.argocd` | `apps/kube` |
| `kbve.unreal` | `apps/rentearth/unreal-rentearth` |
| `kbve.sprite.ship_footprint` | `apps/agones/arpg/{web,server}` |

Porting them before their consumers would mean shipping paths already known to
be wrong, so they stay upstream until there is something to point at. The rest
of `kbve.sprite` did come across — its baker and image passes folded into
`kbve.blender`, which is what they always were.
