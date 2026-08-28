# Laser

<a href="https://kbve.com" style="float: right;"><img width="150" height="50" title="KBVE logo" src="https://kbve.com/assets/images/brand/letter_logo.svg" /></a>

Laser is a lightweight integration layer for Phaser and React Three Fiber in React 19 applications.
It provides React hooks and components for embedding Phaser games and R3F scenes with a shared event bus, making it easy to build hybrid 2D/3D game UIs.

## Features

- **Phaser integration** — `<PhaserGame>` component with ref-based access, `usePhaserGame` context hook, and `usePhaserEvent` for subscribing to Phaser events
- **React Three Fiber integration** — `<Stage>` component and `useGameLoop` hook for frame-synced game logic
- **Shared event bus** — `LaserEventBus` for decoupled communication between Phaser and R3F layers
- **TypeScript-first** — Full type definitions with exported types for configs, events, and geometry primitives

## Install

```bash
npm install @kbve/laser
```

### Peer Dependencies

Laser requires the following peer dependencies (install the ones you need):

Only React is required. Every other peer is optional and belongs to one entry
point, so installing `@kbve/laser` for its ECS pulls in neither Phaser nor three.

- `react` >= 18.0.0
- `phaser` >= 4.2.0 _(optional — `@kbve/laser/phaser`)_
- `@phaserjs/rapier-connector` >= 1.0.0 _(optional — `@kbve/laser/rapier`)_
- `three` >= 0.160.0 _(optional — `@kbve/laser/r3f`)_
- `@react-three/fiber` >= 9.0.0 _(optional — `@kbve/laser/r3f`)_
- `@react-three/drei` >= 10.0.0 _(optional — `@kbve/laser/r3f`)_
- `bitecs` >= 0.4.0 _(optional — `@kbve/laser` and `@kbve/laser/ecs`)_
- `fastnoise-lite` >= 1.1.0 _(optional — `@kbve/laser`)_

`react-dom` is not listed: nothing here imports it. Anything that renders React
already has it, and `@react-three/fiber` declares it for the paths that do.

Two floors worth knowing about:

- **Phaser 4.2, not 4.1.** `SpriteGPULayer` reached for the global `Phaser`
  namespace until 4.2.0, which crashes in a module build — and this is only
  ever consumed as a module.
- **`@kbve/laser/r3f` needs React 19**, not 18. `@react-three/fiber` 9 declares
  `react >=19 <19.3` and drei 10 declares `^19`. Every other entry point runs
  on React 18.

The package is ESM only. There is no CommonJS build and no `require` condition
in `exports`.

## Usage

The renderer bindings live behind subpaths, not the root barrel. That split is
what keeps the optional peers optional: importing `PhaserGame` from `@kbve/laser`
would make every consumer install three, and importing `Stage` from it would
make every consumer install Phaser.

```tsx
// Renderer-agnostic: event bus, ECS, determinism, netcode, tile pathing.
import { laserEvents, LaserEventBus } from '@kbve/laser';

// Phaser bindings. Needs phaser installed.
import { PhaserGame, usePhaserEvent } from '@kbve/laser/phaser';

// Physics. Needs @phaserjs/rapier-connector installed. Separate from the
// Phaser entry because the connector is 1.5MB and most games never simulate.
import { createRapierPhysics } from '@kbve/laser/rapier';

// React Three Fiber bindings. Needs three and @react-three/fiber installed.
import { Stage, useGameLoop } from '@kbve/laser/r3f';
```

| Subpath | Contents |
| --- | --- |
| `@kbve/laser` | event bus, ECS helpers, determinism, netcode, spatial and tile utilities |
| `@kbve/laser/ecs` | the bitECS component and store layer on its own |
| `@kbve/laser/mecs` | `SharedArrayBuffer` views, for a worker or WASM boundary |
| `@kbve/laser/phaser` | `PhaserGame`, hooks, player controller, object pooling |
| `@kbve/laser/rapier` | the Rapier physics connector |
| `@kbve/laser/r3f` | `Stage`, `useGameLoop`, the POM material |

### Support

For questions or help, reach out via our [Discord server](https://kbve.com/discord/).

[![Discord](https://img.shields.io/discord/342732838598082562?logo=discord)](https://kbve.com/discord/)

## License

MIT
