# Fish and Chip Adventures

A Phaser game mounted inside a React root and built by Vite into a static
bundle. It ships to [kbve.itch.io/fishchip](https://kbve.itch.io/fishchip) as an
HTML build.

```
moon run fish-and-chip:dev        # vite dev server on :4200
moon run fish-and-chip:build      # dist/
moon run fish-and-chip:typecheck
moon run fish-and-chip:test
```

## Layout

- `src/main.tsx` mounts `#fishchip` from `index.html`.
- `src/app/phaser/game.tsx` owns the Phaser `Game` lifecycle -- construct on
  mount, `destroy(true)` on unmount, which is what keeps StrictMode's double
  mount from leaving an orphaned canvas and game loop behind.
- `src/app/phaser/scenes/` is the game itself. `Preloader` runs first and every
  other scene is registered after it.
- `src/app/phaser/world/` generates the town. `generateTown` is a pure function
  of a seed, so it is unit tested without a canvas; `palette.ts` holds the tile
  ids, every one of them read out of the authored map or measured off the
  tileset rather than guessed.
- `src/app/phaser/scenes/data/score.ts` is the only writer of persisted score
  state: `totalFish` (what the town NPC reports) and `highScores` (the top five
  runs), both nanostores persistent atoms. GameOver banks a run through
  `recordRun`.
- `src/app/phaser/scenes/data/town-characters.ts` holds the grid-engine
  character list without its sprites, so a test can drive it through a real
  `GridEngineHeadless` -- the scene itself needs a canvas and is out of reach.

## Assets

`public/game/` holds every image, tilemap, and audio file the game loads, and
`Preloader` reads them by relative path. That is a change from the jam build,
which fetched them from `kbve.com` and a Discord attachment: both are 404 today,
so the game as shipped no longer boots. The files were recovered out of the old
KBVE/kbve history (`apps/kbve.com/public/assets/img/fishchip`, last present at
`24483dc`) and the credits background from the itch page's own cover art.

They are plain git objects, not LFS. The LFS rules in `.gitattributes` cover
gilded-gazette's character art, which is large, binary, and hosted on a private
remote; two megabytes of web-sized sprites and one ogg are not worth that.

Art credits, as listed in `CreditsScene`: ArchanDroid (sprites), Nezt50 (tiles),
Retornodomal (menus), BChip (music and animations).

## The town

The map is generated per run, not loaded. `?seed=<number>` pins it -- worth
knowing before reporting a bad town, because otherwise nobody else can reach
the map you saw.

Four landmarks, all captioned in-world and all triggered with `F` when you are
standing on or beside them: the sand pit starts the fishing minigame, the sign
shows credits, the market shows your all-time catch and high scores, and the
grave has something to read.

## Publishing

Tag and push:

```
git tag fish-and-chip@0.1.0
git push origin fish-and-chip@0.1.0
```

`.github/workflows/itch.yml` verifies the tag against `package.json`, builds,
and pushes `dist/` to the `kbve/fishchip:html` channel with the tag's version
as the itch user version. It needs a `BUTLER_API_KEY` repository secret, taken
from <https://itch.io/user/settings/api-keys>.

`vite.config.ts` sets `base: './'` because itch serves an upload from a hashed
subdirectory -- absolute asset paths 404 there and the page comes up blank.

## Origin

Ported from the legacy Nx workspace (`apps/gamejam/react-phaser-fish-chip`).
The build wrote straight into a sibling site's `public/embed` directory there;
it writes to its own `dist/` here, and the itch upload and any embed take the
same artifact. Phaser 3, React 18, styled-components, and react-helmet-async
were dropped for Phaser 4, React 19, and plain CSS on the way over, and the
grid-engine handle is typed rather than `any`, so the 2.x API is actually
checked.
