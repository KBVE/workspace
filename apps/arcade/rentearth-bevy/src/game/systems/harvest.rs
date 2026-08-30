//! What the land has in it.
//!
//! Wood is held per tile in one flat array rather than as trees that exist:
//! the trees are drawn from terrain, in their thousands, by a shader that
//! never knew they were individually anything. Making each one a thing that
//! can be cut down would be the same mistake as making each soldier an
//! entity, and for the same reason -- so a grove is a number that goes down.
//!
//! Stone will be a second array beside this one when it arrives. It is
//! deliberately not written yet: one resource that works is worth more than
//! two that are half-plumbed.

use bevy::prelude::*;

use crate::game::core::map::{MapSpec, Offset};
use crate::game::core::terrain::Terrain;
use crate::game::systems::map::{WorldTiles, spawn_map};

/// How much wood stands on a wooded tile.
///
/// Enough that a company works a grove for a while rather than stripping it
/// in one trip -- a resource that vanishes the moment it is touched is a
/// button, not a place.
const GROVE: u32 = 240;

/// Whether trees grow here.
///
/// The same three biomes the tree shader plants in. It is a function rather
/// than a list in two places, because a wood you can cut that has no trees in
/// it -- or trees you cannot cut -- is the kind of disagreement nobody finds
/// until they are standing in it.
pub fn wooded(terrain: Terrain) -> bool {
    matches!(terrain, Terrain::Taiga | Terrain::Forest | Terrain::Jungle)
}

/// Standing timber, by tile.
#[derive(Resource)]
pub struct Woodland(Vec<u32>);

impl Woodland {
    /// How much is left here.
    pub fn at(&self, spec: MapSpec, tile: Offset) -> u32 {
        self.0
            .get(tile.wrapped(spec).index(spec))
            .copied()
            .unwrap_or(0)
    }

    /// Cut up to `want`, and say how much was actually got.
    ///
    /// Returning the amount rather than taking it on trust is what stops a
    /// grove going negative when two companies work it in the same frame.
    pub fn cut(&mut self, spec: MapSpec, tile: Offset, want: u32) -> u32 {
        let Some(standing) = self.0.get_mut(tile.wrapped(spec).index(spec)) else {
            return 0;
        };
        let taken = want.min(*standing);
        *standing -= taken;
        taken
    }
}

fn seed_woodland(spec: Res<MapSpec>, world: Res<WorldTiles>, mut commands: Commands) {
    let wood = spec
        .tiles()
        .map(|tile| match world.at(*spec, tile) {
            Some(terrain) if wooded(terrain) => GROVE,
            _ => 0,
        })
        .collect();

    commands.insert_resource(Woodland(wood));
}

pub struct HarvestPlugin;

impl Plugin for HarvestPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, seed_woodland.after(spawn_map));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec() -> MapSpec {
        MapSpec {
            cols: 8,
            rows: 4,
            ..MapSpec::default()
        }
    }

    /// A grove cannot be cut past empty, however much is asked of it. Two
    /// companies working the same trees in one tick is the ordinary case, not
    /// the odd one, and an unclamped take would hand out wood that was never
    /// standing there.
    #[test]
    fn a_grove_runs_out_rather_than_going_negative() {
        let spec = spec();
        let tile = Offset { col: 2, row: 1 };
        let mut wood = Woodland(vec![0; spec.tile_count() as usize]);
        wood.0[tile.index(spec)] = 10;

        assert_eq!(wood.cut(spec, tile, 4), 4);
        assert_eq!(wood.at(spec, tile), 6);
        assert_eq!(wood.cut(spec, tile, 100), 6);
        assert_eq!(wood.at(spec, tile), 0);
        assert_eq!(wood.cut(spec, tile, 1), 0);
    }

    /// Cutting off the edge of the map is cutting the tile it wraps to, not a
    /// panic and not silently nothing: the world is a torus and a company can
    /// stand across the seam.
    #[test]
    fn cutting_wraps_with_the_world() {
        let spec = spec();
        let mut wood = Woodland(vec![5; spec.tile_count() as usize]);
        let over_the_edge = Offset { col: 8, row: 1 };

        assert_eq!(wood.cut(spec, over_the_edge, 5), 5);
        assert_eq!(wood.at(spec, Offset { col: 0, row: 1 }), 0);
    }
}
