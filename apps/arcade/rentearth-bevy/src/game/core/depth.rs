//! How far each water tile is from land.
//!
//! The water shader needs real depth to shade coastlines. Its own surface
//! height cannot supply that -- displaced by waves, it says "shallow" in every
//! trough, everywhere, which is why the coastal tint ended up spread across the
//! whole ocean rather than hugging the shore.
//!
//! So depth is measured on the tile grid instead: a breadth-first flood from
//! every land tile outward across water. Distance in tiles, normalised, baked
//! into a texture the shader samples by world position.

use std::collections::VecDeque;

use super::map::{MapSpec, Offset};
use super::terrain::Terrain;

/// Tiles from shore at which water is considered fully deep. Beyond this the
/// gradient is flat, so the shading detail sits where the coast is rather than
/// being spread thin across an ocean.
const DEEP_AT: f32 = 6.0;

/// Distance from land for every tile, normalised to `0.0..1.0`.
///
/// Land is 0. Row-major, matching `Offset::index`.
pub fn distance_from_land(spec: MapSpec, world: &[(Offset, Terrain)]) -> Vec<f32> {
    let count = spec.tile_count() as usize;
    let mut dist = vec![u16::MAX; count];
    let mut queue = VecDeque::new();

    // Multi-source: every land tile starts at zero, so one pass gives the
    // distance to the *nearest* coast rather than to a particular one.
    for (offset, terrain) in world {
        if !terrain.is_water() {
            let i = offset.index(spec);
            dist[i] = 0;
            queue.push_back(*offset);
        }
    }

    while let Some(current) = queue.pop_front() {
        let d = dist[current.index(spec)];
        for neighbour in current.neighbours() {
            // Wrapped, so the flood crosses both seams. Without this the map
            // edges would read as deep ocean regardless of what is beyond them.
            let neighbour = neighbour.wrapped(spec);
            let i = neighbour.index(spec);
            if dist[i] == u16::MAX {
                dist[i] = d + 1;
                queue.push_back(neighbour);
            }
        }
    }

    dist.into_iter()
        .map(|d| {
            // An all-water map leaves nothing unreached, but guard anyway --
            // u16::MAX as a distance would wrap the normalisation.
            let d = if d == u16::MAX { DEEP_AT as u16 } else { d };
            (d as f32 / DEEP_AT).min(1.0)
        })
        .collect()
}
