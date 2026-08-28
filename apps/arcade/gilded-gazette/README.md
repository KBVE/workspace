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
Vite builds around it. `moon run gilded-gazette:build` is that whole order;
`CMakeLists.txt` encodes the same one for a local `cmake --build build --target ci`.

## Building

```
moon run gilded-gazette:build       # the game: codegen, Godot export, Vite
moon run gilded-gazette:e2e         # boots the built game in a browser
moon run gilded-gazette:test-godot  # gdUnit4
moon run gilded-gazette:dev         # Vite against whatever is in public/godot
```

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

#### Parallax Forest

Parallax Forest Background by [DigitalMoonStudio](https://digitalmoons.itch.io/parallax-forest-background)

#### Books

Public Domain [Book Covers](https://publicdomainreview.org/collection/the-art-of-book-covers-1820-1914/)

#### SVGS

Goblin by parkjisun from Noun Project (CC BY 3.0)
magic fire by Cahya Kurniawan from Noun Project (CC BY 3.0)