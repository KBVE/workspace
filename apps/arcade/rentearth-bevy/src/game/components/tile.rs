//! Tile entity data.

use bevy::prelude::*;

/// Marks an entity as a map tile. The `Offset` and `Terrain` components carry
/// the data; this exists so systems can query tiles without naming either.
#[derive(Component, Clone, Copy, Debug)]
pub struct Tile;

/// Where the tile sits in the canonical, unwrapped world.
///
/// The world wraps on both axes, so a tile has infinitely many valid positions
/// -- one per copy of the world. Rather than spawn nine copies of every tile,
/// each tile is spawned once and moved to whichever copy is nearest the camera.
/// This is the position it is measured from; the `Transform` is the position it
/// is currently drawn at.
#[derive(Component, Clone, Copy, Debug)]
pub struct BasePosition(pub Vec3);
