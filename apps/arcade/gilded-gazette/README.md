# gilded-gazette

A Godot 4 + React/Vite game, originally built for the Brackeys 16 game jam.

```
godot/   Godot 4 project (web export target)
shared/  state.json, events.json, data/*.mdx -- single source of truth
tools/   codegen + asset scripts (shared/ -> godot/ and vite/)
vite/    React front end; hosts the web export from public/godot
```

Three runtimes in one project, in a fixed order: `shared/` compiles into both
`godot/` and `vite/`, the Godot web export lands in `vite/public/godot`, then
Vite builds around it. `moon run gilded-gazette:build` is that whole order.

## Building

```
moon run gilded-gazette:build       # the game: codegen, Godot export, Vite
moon run gilded-gazette:e2e         # boots the built game in a browser
moon run gilded-gazette:test-godot  # gdUnit4
moon run gilded-gazette:dev         # Vite against whatever is in public/godot
```

Two more rewrite files that are committed, so they run when asked and never on
a push: `scene` rebuilds `godot/scenes/train/train.scn`, which is generated
rather than hand-edited, and `godot-import` refreshes the script cache it needs
first. The scene is a binary that does not regenerate byte-identically, so
expect a diff even when nothing changed.

Nothing has to be installed first. The editor is pinned in the workspace
`.prototools` and installed by proto; its web export templates are a task
(`export-templates`, which proto cannot do -- see `.proto/plugins/godot.toml`),
and the character art is another (`assets`, from the repo-root `.lfsconfig`).
Both are dependencies of the build, and the first run is a long one.

`vite/` carries its own `package.json` and `package-lock.json`, outside the
pnpm workspace globs. It is an npm island on purpose for now; adopting the
catalog means moving it onto pnpm, which is a separate change.

## Releasing

Ships to itch.io as `kbve/gilded-gazette`, on a tag:

```
gilded-gazette@<version>
```

Push that tag and `.github/workflows/itch.yml` resolves it against the project
graph, builds, boots the build in a browser, and pushes to itch. **Versioning
is manual**: the tag is checked against `godot/project.godot` `config/version`
and the release fails if they disagree, so bump that first and commit it before
tagging.

The workflow names no game. What makes this one publishable is the `itch` tag
and `ITCH_TARGET` in `moon.yml`.

### Secrets

`BUTLER_API_KEY` for itch, and `FORGEJO_USER` / `FORGEJO_TOKEN` for the
character art, which lives on the self-hosted Forgejo named in the repo-root
`.lfsconfig` rather than on GitHub. All three are repository secrets.

Locally they go in the workspace-root `.env` -- see `.env.example` here for
the names. Vite inlines any `VITE_` prefixed variable into the client bundle,
so treat that file as public output, not as a vault.

By Rhombert, Moshhhhh, h0lybyte

## Credits

### Software

Godot Game Template by [Maaack](https://github.com/Maaack/Godot-Game-Template/).
Testing Library by [GDUnit4](https://github.com/godot-gdunit-labs/gdUnit4)
GodotECS by [baiXfeng](https://github.com/godothub/godot-ecs)

### Assets 

#### Trains

Train Proof of Concept from [JoTrain](https://sketchfab.com/3d-models/queensland-railways-1900s-bl-heritage-carriage-807b44e77da345f2aac51c750d4b673c)

```
Model: queensland-railways-1900s-bl-heritage-carriage-807b44e77da345f2aac51c750d4b673c
Created by Jotrain – www.jotrain.com.au
```

#### Items

Ornate Medieval Dagger from [Poly Haven](https://polyhaven.com/a/ornate_medieval_dagger)
(CC0).

Item models are built from a downloaded asset rather than committed as one. The
downloads are a .blend plus a 1k PBR set, and none of the normal, roughness or
metallic maps survive: `shaders/prop.gdshader` takes one albedo and a baked lamp
tint, so the other three megabytes would be downloaded by every browser and then
ignored. `tools/import-item-model.py` keeps the diffuse, resizes it to 256,
collapses the mesh to a triangle budget, lays the object down, puts its origin on
the ground under it, and writes one self-contained glb:

```
blender -b ~/Downloads/ornate_medieval_dagger_1k/ornate_medieval_dagger_1k.blend \
  -P tools/import-item-model.py -- --out godot/assets/items/ornate_dagger.glb
```

Both budgets are worth understanding before raising either. Vertex data is the
bulk of what a glb weighs, not the image: the dagger arrived at 6,290 triangles
and 192K, of which 162K was positions, normals, UVs and indices. At 800 triangles
and a 256 albedo it is 37K, and it is still the most detailed thing in the train
-- the crates it lies beside are 68 triangles each. A hand-sized object seen from
across a carriage does not repay more than that.

The glb is committed; the download is not.

What the browser downloads is neither. Godot imports a glb at build time into its
own `.scn` and `.ctex`, and `index.pck` carries those; the glb is a source file
the export never ships. So the numbers to watch are in `.godot/imported`, and they
do not follow the source. The dagger's 10.5K jpeg imported to a 78.9K `.ctex`,
because textures default to lossless: `compress/mode=1` in the `.import` puts it
at 9.9K, which is a bigger saving than every other decision here put together.
The mesh lands at 25.6K.

That is also the answer to gltfpack, which is the obvious tool to reach for here.
Its headline win is a smaller glb -- quantized attributes, meshopt compression --
and this game does not download the glb. Measured on the dagger: the default
quantized output does not import at all under Godot 4.7.2, which records
`valid=false` in the `.import` and produces no scene; `gltfpack -noq` imports
cleanly and lands at 25.7K against the 25.6K it already was, because Godot
re-encodes either way. What it would still be good for is its simplifier, which
is better than Blender's collapse -- worth revisiting if an item ever arrives
that decimates badly. What an item then needs is an mdx in
`shared/data/items` naming that model and a `found` spot in the room it lies in --
see `ornate_dagger.mdx`. A model named with no glb behind it fails `npm run gen`
rather than leaving an empty patch of floor in game.

#### Parallax Forest

Parallax Forest Background by [DigitalMoonStudio](https://digitalmoons.itch.io/parallax-forest-background)

#### Books

Public Domain [Book Covers](https://publicdomainreview.org/collection/the-art-of-book-covers-1820-1914/)

#### SVGS

Goblin by parkjisun from Noun Project (CC BY 3.0)
magic fire by Cahya Kurniawan from Noun Project (CC BY 3.0)