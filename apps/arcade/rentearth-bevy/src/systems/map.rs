//! Spawning the world's tiles.

use std::f32::consts::FRAC_PI_2;

use bevy::platform::collections::HashMap;
use bevy::prelude::*;

use crate::components::tile::{BasePosition, Tile};
use crate::core::hex::HEX_SIZE;
use crate::components::camera::CameraRig;
use crate::core::map::MapSpec;
use crate::core::terrain::{self, Terrain};

/// Y that every column is drawn down to. Only the sides between here and a
/// tile's elevation are visible, so this just has to sit below the deepest
/// ocean; the exact value is cosmetic.
const COLUMN_BASE: f32 = -30.0;

/// Gap between neighbouring columns, as a fraction of tile radius. Without it
/// the columns meet exactly and the map reads as one surface, not as tiles.
const TILE_INSET: f32 = 0.97;

pub struct MapPlugin;

impl Plugin for MapPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<MapSpec>()
            .add_systems(Startup, spawn_map)
            // After the camera has moved and wrapped, so tiles are placed
            // against the focus the camera will actually render from.
            .add_systems(PostUpdate, wrap_tiles);
    }
}

fn spawn_map(
    mut commands: Commands,
    spec: Res<MapSpec>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    // One mesh and one material per terrain, not per tile. Column depth is
    // baked into the mesh because it differs per terrain, so that is as far as
    // the sharing goes.
    let assets: HashMap<Terrain, (Handle<Mesh>, Handle<StandardMaterial>)> = Terrain::ALL
        .iter()
        .map(|t| {
            let mesh = meshes.add(Extrusion::new(
                RegularPolygon::new(HEX_SIZE * TILE_INSET, 6),
                t.elevation() - COLUMN_BASE,
            ));
            let material = materials.add(StandardMaterial {
                base_color: t.color(),
                // Flat, chalky tiles. A specular highlight across thousands of
                // columns reads as noise rather than as material.
                perceptual_roughness: 0.95,
                ..default()
            });
            (*t, (mesh, material))
        })
        .collect();

    // Extrusion builds along +Z from a 2D shape in XY; the map needs that axis
    // along +Y, so every tile is laid flat.
    let lay_flat = Quat::from_rotation_x(-FRAC_PI_2);

    let world = terrain::generate(*spec);

    for (offset, kind) in &world {
        let (mesh, material) = &assets[kind];

        // Extrusion is centred on its own origin, so the column's midpoint
        // goes here for the top face to land on the terrain's elevation.
        let mid = (kind.elevation() + COLUMN_BASE) / 2.0;
        let position = offset.to_hex().to_world(mid);

        commands.spawn((
            Mesh3d(mesh.clone()),
            MeshMaterial3d(material.clone()),
            Transform::from_translation(position).with_rotation(lay_flat),
            BasePosition(position),
            Tile,
            *offset,
            *kind,
        ));
    }

    info!("spawned {} tiles ({}x{})", world.len(), spec.cols, spec.rows);
}

/// Move every tile into the copy of the world nearest the camera.
///
/// The world wraps, so a tile at column 0 should appear to the *west* of the
/// camera when the camera is near the eastern edge. Rather than spawning nine
/// copies of the map to cover every crossing, each tile is offset by whole
/// worlds until it is the nearest of its infinitely many valid positions.
///
/// This is the whole reason the ECS layout pays here: the wrap is one system
/// over one component, not nine times the entities.
fn wrap_tiles(
    spec: Res<MapSpec>,
    camera: Query<&CameraRig, Changed<CameraRig>>,
    mut tiles: Query<(&BasePosition, &mut Transform), With<Tile>>,
) {
    // Only when the camera actually moved. A still camera leaves 10k
    // transforms untouched, which also means they stay out of Bevy's change
    // detection and out of the transform propagation pass.
    let Ok(rig) = camera.single() else {
        return;
    };

    let width = spec.world_width();
    let depth = spec.world_depth();

    for (base, mut transform) in &mut tiles {
        // Round rather than floor: round puts the tile in the nearest copy,
        // floor would put it in the one below and leave a world-sized gap on
        // one side of the camera.
        let shift_x = ((rig.focus.x - base.0.x) / width).round() * width;
        let shift_z = ((rig.focus.z - base.0.z) / depth).round() * depth;

        transform.translation.x = base.0.x + shift_x;
        transform.translation.z = base.0.z + shift_z;
    }
}
