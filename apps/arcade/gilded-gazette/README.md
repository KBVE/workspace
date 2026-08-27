# gilded-gazette

A Godot 4 + React/Vite game, originally built for the Brackeys 16 game jam.

```
game/
  godot/   Godot 4 project (web export target)
  shared/  state.json, events.json, data/*.mdx -- single source of truth
  tools/   codegen + asset scripts (shared/ -> godot/ and vite/)
  vite/    React front end; hosts the web export from public/godot
```

Build orchestration lives in `game/CMakeLists.txt`; `cmake --build build --target ci`
runs what `.github/workflows/release-itch.yml` runs.

Ships to itch.io as `kbve/gilded-gazette`.

## Branch flow

`dev` is where work lands; `main` is the release branch. Nothing publishes
except a merge into `main`.

| Event | What runs |
|---|---|
| push to `dev` | `tests.yml` (gdUnit4, web build, Playwright) and `shell.yml` (rebuilds `game/godot/web/shell.html` when the vite shell changes) |
| push to `dev` | `dev-pr.yml` opens or refreshes the `dev` to `main` PR, titled with the version it would ship |
| merge to `main` | `release-itch.yml`: publish if `config/version` is not yet tagged, then fast-forward `dev` back onto `main` |

**Versioning is manual.** `game/godot/project.godot` `config/version` is the
release gate: the workflow publishes only when no `v<version>` tag exists, so a
main push that repeats an already-shipped version is a no-op rather than a
duplicate upload. Bump `config/version` on `dev` when you want the next merge to
ship; the `dev` to `main` PR body says which of the two will happen.

### CI secrets

This repo is private and KBVE is on GitHub Free, where organization secrets do
not reach private repositories. So `BUTLER_API_KEY`, `FORGEJO_USER` and `FORGEJO_TOKEN`
have to exist as **repository** secrets here, not as the org secrets of the same
name. `UNITY_PAT` is optional: every use is `secrets.UNITY_PAT ||
secrets.GITHUB_TOKEN` and the fallback has the permissions the jobs need.

Local secrets go in `.env`, which is gitignored. Vite inlines any `VITE_`
prefixed variable into the client bundle, so treat that file as public output,
not as a vault.

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