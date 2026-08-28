// Rapier subpath: the physics connector, on its own.
//
// This used to hang off `@kbve/laser/phaser`, which meant that importing
// PhaserGame -- a React wrapper around a canvas -- pulled 1.5MB of physics
// engine into the bundle. A barrel re-export is not tree-shakeable here, so
// every Phaser consumer paid for physics whether or not it simulated
// anything. Splitting it keeps the rule the other entry points already
// follow: one optional peer, one entry.
export { RAPIER, createRapierPhysics } from './lib/physics/rapier';
