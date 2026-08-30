//! Showing who holds what.
//!
//! Ownership is a fact about a tile, and a tile is already an entity carrying
//! a material shared with every other tile of its terrain. So held ground is
//! not a new thing drawn over the map -- it is the same tile in a different
//! material, one per terrain per owner. Fifty-odd materials for the whole
//! world, built once, and a tile changing hands is a handle swap.
//!
//! The alternative was a material per tile, which is twenty-four thousand of
//! them and the end of any batching at all.

use bevy::platform::collections::HashMap;
use bevy::prelude::*;

use crate::game::components::tile::Tile;
use crate::game::core::map::{MapSpec, Offset};
use crate::game::core::terrain::Terrain;
use crate::game::systems::territory::{TEAMS, Territory};

/// The four sides, in the order their numbers run.
///
/// The same colours the units are painted in, because a man and the ground he
/// holds belonging to different-looking sides is worse than either being hard
/// to see.
pub const TEAM_COLOURS: [Color; TEAMS as usize] = [
    Color::srgb(0.85, 0.31, 0.29),
    Color::srgb(0.29, 0.47, 0.85),
    Color::srgb(0.36, 0.72, 0.36),
    Color::srgb(0.85, 0.72, 0.28),
];

/// How much of a held tile is the holder's colour.
///
/// Enough to read at a glance and not so much that the map underneath stops
/// being terrain: a border you cannot see is useless, and a board painted in
/// four flat colours is not a world.
const STAIN: f32 = 0.42;

/// Every terrain in every hand, worked out once.
#[derive(Resource)]
pub struct HeldMaterials(HashMap<(Terrain, u32), Handle<StandardMaterial>>);

fn build_materials(mut commands: Commands, mut materials: ResMut<Assets<StandardMaterial>>) {
    let mut held = HashMap::default();

    for terrain in Terrain::ALL.iter().filter(|t| !t.is_water()) {
        for (team, colour) in TEAM_COLOURS.iter().enumerate() {
            let base = terrain.color().to_linear();
            let stain = colour.to_linear();
            let mixed = LinearRgba::rgb(
                base.red + (stain.red - base.red) * STAIN,
                base.green + (stain.green - base.green) * STAIN,
                base.blue + (stain.blue - base.blue) * STAIN,
            );

            let handle = materials.add(StandardMaterial {
                base_color: mixed.into(),
                perceptual_roughness: 0.95,
                ..default()
            });
            held.insert((*terrain, team as u32), handle);
        }
    }

    commands.insert_resource(HeldMaterials(held));
}

/// Repaint held ground when it changes hands, and only then.
///
/// Walking every tile is twenty-four thousand entities, which is nothing once
/// and far too much every frame -- so this runs on the resource changing
/// rather than on the clock. Ground changes hands rarely; that is the whole
/// reason this is affordable.
fn paint_held(
    territory: Option<Res<Territory>>,
    spec: Res<MapSpec>,
    held: Option<Res<HeldMaterials>>,
    mut tiles: Query<(&Offset, &Terrain, &mut MeshMaterial3d<StandardMaterial>), With<Tile>>,
) {
    let (Some(territory), Some(held)) = (territory, held) else {
        return;
    };
    if !territory.is_changed() {
        return;
    }

    for (offset, terrain, mut material) in &mut tiles {
        let Some(team) = territory.owner_of(*spec, *offset) else {
            continue;
        };
        let Some(handle) = held.0.get(&(*terrain, team)) else {
            continue;
        };
        if material.0 != *handle {
            material.0 = handle.clone();
        }
    }
}

pub struct BordersPlugin;

impl Plugin for BordersPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, build_materials)
            .add_systems(Update, paint_held);
    }
}
