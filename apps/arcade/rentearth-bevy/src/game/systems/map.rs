//! Spawning the world's tiles.

use std::f32::consts::FRAC_PI_2;

use bevy::asset::RenderAssetUsages;
use bevy::image::{ImageAddressMode, ImageSampler, ImageSamplerDescriptor};
use bevy::platform::collections::HashMap;
use bevy::prelude::*;
use bevy::transform::TransformSystems;
use bevy::render::render_resource::{Extent3d, TextureDimension, TextureFormat};

use crate::game::components::tile::{BasePosition, Tile};
use crate::game::core::hex::HEX_SIZE;
use crate::game::components::camera::CameraRig;
use crate::game::core::depth;
use crate::game::core::map::{MapSpec, Offset};
use crate::game::core::terrain::{self, Terrain, SEA_LEVEL};

/// Y that every column is drawn down to. Only the sides between here and a
/// tile's elevation are visible, so this just has to sit below the deepest
/// ocean; the exact value is cosmetic.
const COLUMN_BASE: f32 = -30.0;

/// Scale applied to each column's footprint.
///
/// Exactly 1.0, so columns tessellate. Anything less leaves a gap between
/// neighbours, and while a height difference hides it behind the taller tile's
/// side wall, equal-height neighbours -- a flat shelf, open grassland -- have no
/// wall, so the gap shows as a seam straight through the map. Tile definition
/// comes from the side walls and lighting instead.
const TILE_INSET: f32 = 1.0;

/// The generated world, addressable by tile.
///
/// Kept as a resource so anything that needs "what terrain is at this hex" --
/// picking, and later pathing and yields -- can ask without walking the entity
/// query.
#[derive(Resource)]
pub struct WorldTiles {
    pub terrain: Vec<Terrain>,
}

impl WorldTiles {
    pub fn at(&self, spec: MapSpec, offset: Offset) -> Option<Terrain> {
        self.terrain.get(offset.wrapped(spec).index(spec)).copied()
    }
}

/// Distance from land, as a texture the water shader samples by world
/// position. Built once at startup; the water surface waits on it.
#[derive(Resource, Clone)]
pub struct SeaDepth {
    pub image: Handle<Image>,
}

pub struct MapPlugin;

impl Plugin for MapPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<MapSpec>()
            .add_systems(Startup, spawn_map)
            // After the camera has moved and wrapped, so tiles are placed
            // against the focus the camera will actually render from -- but
            // before transforms propagate, because culling reads the propagated
            // result. Unordered, the frame that crosses a seam culls every tile
            // against last frame's positions and the screen goes black.
            .add_systems(PostUpdate, wrap_tiles.before(TransformSystems::Propagate));
    }
}

pub fn spawn_map(
    mut commands: Commands,
    spec: Res<MapSpec>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut images: ResMut<Assets<Image>>,
) {
    // One mesh and one material per terrain, not per tile. Column depth is
    // baked into the mesh because it differs per terrain, so that is as far as
    // the sharing goes.
    let assets: HashMap<Terrain, (Handle<Mesh>, Handle<StandardMaterial>)> = Terrain::ALL
        .iter()
        .filter(|t| !t.is_water())
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
        // Water is one plane, drawn by the water crate. The tiles still exist
        // -- gameplay has to know a hex is ocean -- they just carry no mesh,
        // because a surface built from separate columns cracks at every seam
        // once the waves displace it. Earth being two thirds water, this is
        // also most of the geometry gone.
        if kind.is_water() {
            commands.spawn((
                Transform::from_translation(offset.to_hex().to_world(SEA_LEVEL)),
                BasePosition(offset.to_hex().to_world(SEA_LEVEL)),
                Tile,
                *offset,
                *kind,
            ));
            continue;
        }

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

    commands.insert_resource(WorldTiles {
        terrain: world.iter().map(|(_, t)| *t).collect(),
    });

    commands.insert_resource(SeaDepth {
        image: images.add(depth_texture(*spec, &world)),
    });

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

/// Bake the distance-from-land field into a single-channel texture.
///
/// One texel per tile. The shader samples it by world position rather than by
/// tile, so it interpolates across tile boundaries and the coastline gradient
/// comes out smooth instead of stepped.
fn depth_texture(spec: MapSpec, world: &[(crate::game::core::map::Offset, Terrain)]) -> Image {
    let field = depth::distance_from_land(spec, world);
    let data: Vec<u8> = field.iter().map(|d| (d * 255.0) as u8).collect();

    let mut image = Image::new(
        Extent3d {
            width: spec.cols as u32,
            height: spec.rows as u32,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        data,
        TextureFormat::R8Unorm,
        // The field is read on the GPU only; nothing needs a CPU copy of it.
        RenderAssetUsages::RENDER_WORLD,
    );

    // Repeat on both axes, because the world wraps and so must its depth: a
    // clamped sampler would smear the edge column across the seam.
    image.sampler = ImageSampler::Descriptor(ImageSamplerDescriptor {
        address_mode_u: ImageAddressMode::Repeat,
        address_mode_v: ImageAddressMode::Repeat,
        ..ImageSamplerDescriptor::linear()
    });

    image
}
