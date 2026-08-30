//! The seat of a side, drawn on the ground it grew from.
//!
//! A home was a tile in an array and a component on an entity, and neither of
//! those is visible: a player looking for his capital had nothing to look at
//! but a stain on the ground the same colour as the six tiles beside it. This
//! gives it a building.
//!
//! Four of them, so the cheap thing is also the right thing -- a keep and a
//! tower each, meshed once and shared, standing on the tile's own elevation.
//! It grows as men are taken into it, which is the only feedback the player
//! gets that absorbing a company did anything.

use bevy::prelude::*;

use crate::game::components::command::{Home, Populace, Team};
use crate::game::components::tile::BasePosition;
use crate::game::core::hex::HEX_SIZE;
use crate::game::core::map::MapSpec;
use crate::game::systems::borders::TEAM_COLOURS;
use crate::game::systems::map::WorldTiles;

/// How wide the keep sits on its hex.
///
/// A third of the hex, which leaves room for men to stand around it. Wider
/// looked like the tile had been paved over.
const KEEP: f32 = HEX_SIZE * 0.30;

/// How tall it stands with nobody living in it.
///
/// About twice a man, which is what makes it read as a building rather than
/// as a marker: at the same height as its garrison it was a coloured box.
const HEIGHT: f32 = HEX_SIZE * 0.26;

/// How much taller a hundred citizens make it.
///
/// Small on purpose: a capital that doubles in height every few minutes stops
/// reading as a building and starts reading as a bar chart.
const PER_HUNDRED: f32 = 0.5;

/// Marks the thing that grows, as opposed to the entity that owns it.
#[derive(Component)]
struct Keep;

/// Put a keep on every home tile.
///
/// Runs once things exist rather than at startup, because the homes are chosen
/// from the generated map and so are not there when startup begins. `Added`
/// keeps it to the frame they appear in.
fn raise_keeps(
    spec: Res<MapSpec>,
    world: Option<Res<WorldTiles>>,
    homes: Query<(&Home, &Team), Added<Home>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut commands: Commands,
) {
    let Some(world) = world else {
        return;
    };

    for (home, team) in &homes {
        let Some(terrain) = world.at(*spec, home.tile) else {
            continue;
        };
        let ground = home.tile.to_hex().to_world(terrain.elevation());

        let colour = TEAM_COLOURS[team.0 as usize % TEAM_COLOURS.len()];
        let stone = materials.add(StandardMaterial {
            // A shade off the border colour rather than the colour itself: a
            // wall the same value as the ground it stands on has no edges.
            base_color: colour.darker(0.10),
            perceptual_roughness: 0.9,
            ..default()
        });
        // The tower is the same colour lightened rather than a second one, so
        // a capital reads as one building at a distance and as two shapes up
        // close.
        let pale = materials.add(StandardMaterial {
            base_color: colour.lighter(0.25),
            perceptual_roughness: 0.9,
            ..default()
        });

        let keep = meshes.add(Cuboid::new(KEEP, HEIGHT, KEEP));
        let roof = meshes.add(Cone::new(KEEP * 0.62, HEIGHT * 0.85));
        let tower = meshes.add(Cylinder::new(KEEP * 0.24, HEIGHT * 1.45));
        let spire = meshes.add(Cone::new(KEEP * 0.30, HEIGHT * 0.50));

        // A corner rather than the middle, so the two shapes read as one
        // building seen from an angle instead of as a cylinder balanced on a
        // box.
        let corner = KEEP * 0.46;

        commands.spawn((
            Transform::from_translation(ground),
            BasePosition(ground),
            Visibility::default(),
            Keep,
            *team,
            Name::new(format!("capital {}", team.0)),
            children![
                (
                    Mesh3d(keep),
                    MeshMaterial3d(stone.clone()),
                    // The mesh is centred on its own middle and the ground is
                    // at the parent, so it is lifted by half its height to
                    // stand on the tile rather than sink into it.
                    Transform::from_xyz(0.0, HEIGHT * 0.5, 0.0),
                ),
                (
                    Mesh3d(roof),
                    MeshMaterial3d(pale.clone()),
                    Transform::from_xyz(0.0, HEIGHT * 1.425, 0.0),
                ),
                (
                    Mesh3d(tower),
                    MeshMaterial3d(stone),
                    Transform::from_xyz(corner, HEIGHT * 0.72, -corner),
                ),
                (
                    Mesh3d(spire),
                    MeshMaterial3d(pale),
                    Transform::from_xyz(corner, HEIGHT * 1.695, -corner),
                ),
            ],
        ));
    }
}

/// Grow a capital as people move into it.
///
/// On the count changing rather than on the clock: citizens arrive when a
/// player sends them, which is rarely, and walking four entities every frame
/// to find out that nothing happened is four entities too many.
fn grow_keeps(
    people: Query<(&Team, &Populace), Changed<Populace>>,
    mut keeps: Query<(&Team, &mut Transform), With<Keep>>,
) {
    for (side, populace) in &people {
        let grown = 1.0 + PER_HUNDRED * populace.citizens as f32 / 100.0;
        for (team, mut transform) in &mut keeps {
            if team == side {
                transform.scale = Vec3::new(grown, grown, grown);
            }
        }
    }
}

pub struct CityPlugin;

impl Plugin for CityPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Update, (raise_keeps, grow_keeps));
    }
}
