//! Spawning the world's tiles.

use bevy::asset::RenderAssetUsages;
use bevy::image::{ImageAddressMode, ImageSampler, ImageSamplerDescriptor};
use bevy::platform::collections::HashMap;
use bevy::prelude::*;
use bevy::render::mesh::{Indices, PrimitiveTopology};
use bevy::render::render_resource::{Extent3d, TextureDimension, TextureFormat};
use bevy::transform::TransformSystems;

use crate::game::components::camera::CameraRig;
use crate::game::components::tile::{BasePosition, Tile};
use crate::game::core::depth;
use crate::game::core::hex::HEX_SIZE;
use crate::game::core::map::{MapSpec, Offset};
use crate::game::core::terrain::{self, SEA_LEVEL, Terrain};

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

/// Width of the darkened rim around each tile's top face, as a fraction of the
/// hex's circumradius.
///
/// The borders a 4X map is read through. Drawn as part of the column rather
/// than as an overlay on top of it: there are 24,000 land tiles, so anything
/// that costs an entity or a draw call each is not a border, it is a budget.
const BORDER_WIDTH: f32 = 0.055;

/// How much darker the rim is than the tile it edges.
///
/// A multiplier rather than a colour, so the border is the terrain's own hue in
/// shadow. A flat grey line over ice and over jungle belongs to neither.
const BORDER_SHADE: f32 = 0.62;

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
    // Read by the private water material. The field stays ungated so the
    // resource has one shape either way; only the reader is conditional.
    #[cfg_attr(not(feature = "water"), allow(dead_code))]
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
            let mesh = meshes.add(column_mesh(
                HEX_SIZE * TILE_INSET,
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

        // The mesh puts its top face at the origin and hangs the column below,
        // so the tile goes straight to its own elevation with no midpoint to
        // work out and nothing to rotate.
        let position = offset.to_hex().to_world(kind.elevation());

        commands.spawn((
            Mesh3d(mesh.clone()),
            MeshMaterial3d(material.clone()),
            Transform::from_translation(position),
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

    info!(
        "spawned {} tiles ({}x{})",
        world.len(),
        spec.cols,
        spec.rows
    );
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
    // Filtered on `BasePosition` alone rather than on `Tile`. Carrying one is
    // what it means to live in a wrapping world, and tiles are no longer the
    // only things that do -- the tree clumps have to cross the seam with the
    // ground they stand on.
    mut wrapped: Query<(&BasePosition, &mut Transform)>,
) {
    // Only when the camera actually moved. A still camera leaves 10k
    // transforms untouched, which also means they stay out of Bevy's change
    // detection and out of the transform propagation pass.
    let Ok(rig) = camera.single() else {
        return;
    };

    let width = spec.world_width();
    let depth = spec.world_depth();

    for (base, mut transform) in &mut wrapped {
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

/// One hex column: a top face with a darkened rim, and the walls below it.
///
/// Built here rather than taken from `Extrusion` because of the rim. Bevy's
/// primitives make a hexagon with nothing to attach a border to, and every
/// other way of drawing one -- an overlay mesh, a child entity, a second pass
/// -- costs something per tile across 24,000 of them. Baked into the mesh the
/// tiles already share, it costs nothing at all: the rim is the same triangles
/// carrying a darker vertex colour.
///
/// The top face sits at y = 0 and the column hangs to `-height`, so a tile is
/// placed at its own elevation. The bottom is left open, being under the map.
fn column_mesh(radius: f32, height: f32) -> Mesh {
    // Pointy-top, matching the axial layout in `hex`: a vertex straight up the
    // z axis, the flats to east and west. Get this wrong by thirty degrees and
    // the tiles stop tessellating.
    let corner = |k: usize, r: f32| {
        let angle = std::f32::consts::FRAC_PI_2 + k as f32 * std::f32::consts::FRAC_PI_3;
        Vec3::new(r * angle.cos(), 0.0, -r * angle.sin())
    };

    let inner_radius = radius * (1.0 - BORDER_WIDTH);

    let mut positions: Vec<[f32; 3]> = Vec::new();
    let mut normals: Vec<[f32; 3]> = Vec::new();
    let mut colors: Vec<[f32; 4]> = Vec::new();
    let mut indices: Vec<u32> = Vec::new();

    let lit = [1.0, 1.0, 1.0, 1.0];
    let rim = [BORDER_SHADE, BORDER_SHADE, BORDER_SHADE, 1.0];
    let up = [0.0, 1.0, 0.0];

    // Centre of the top face.
    positions.push([0.0, 0.0, 0.0]);
    normals.push(up);
    colors.push(lit);

    // Inner ring, then outer ring, both on the top face.
    for k in 0..6 {
        positions.push(corner(k, inner_radius).to_array());
        normals.push(up);
        colors.push(lit);
    }
    for k in 0..6 {
        positions.push(corner(k, radius).to_array());
        normals.push(up);
        colors.push(rim);
    }

    // The face inside the border: a fan from the centre.
    for k in 0..6u32 {
        let next = k % 6 + 1;
        indices.extend_from_slice(&[0, 1 + k, 1 + (next % 6)]);
    }

    // The border itself: a quad per edge, between the two rings.
    for k in 0..6u32 {
        let (a, b) = (1 + k, 1 + (k + 1) % 6);
        let (c, d) = (7 + k, 7 + (k + 1) % 6);
        indices.extend_from_slice(&[a, c, d, a, d, b]);
    }

    // The walls. Their own vertices, because a wall's normal points outward and
    // sharing the top face's would round the edge over.
    for k in 0..6 {
        let a = corner(k, radius);
        let b = corner((k + 1) % 6, radius);

        // Outward and level, so neighbouring columns of different heights read
        // as cliffs rather than as a smooth slope.
        let outward = ((a + b) * 0.5).normalize_or_zero().to_array();

        let base = positions.len() as u32;
        for corner_position in [a, b, b - Vec3::Y * height, a - Vec3::Y * height] {
            positions.push(corner_position.to_array());
            normals.push(outward);
            colors.push(lit);
        }
        indices.extend_from_slice(&[base, base + 2, base + 1, base, base + 3, base + 2]);
    }

    Mesh::new(
        PrimitiveTopology::TriangleList,
        RenderAssetUsages::RENDER_WORLD,
    )
    .with_inserted_attribute(Mesh::ATTRIBUTE_POSITION, positions)
    .with_inserted_attribute(Mesh::ATTRIBUTE_NORMAL, normals)
    .with_inserted_attribute(Mesh::ATTRIBUTE_COLOR, colors)
    .with_inserted_indices(Indices::U32(indices))
}
