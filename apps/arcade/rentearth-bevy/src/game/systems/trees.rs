//! Trees on forest tiles.
//!
//! Billboards, in the 2.5D sense: flat quads standing upright in the world.
//! What makes them cheap here is that the camera never yaws -- `apply_rig`
//! builds its transform from a constant offset and a fixed pitch, so a quad
//! lying in the XY plane already faces it, from every tile, forever. There is
//! no per-frame system pointing anything at anything.

use bevy::asset::RenderAssetUsages;
use bevy::light::NotShadowCaster;
use bevy::prelude::*;
use bevy::render::mesh::{Indices, PrimitiveTopology};
use bevy::render::render_resource::{Extent3d, TextureDimension, TextureFormat};

use crate::game::components::tile::BasePosition;
use crate::game::core::hex::HEX_SIZE;
use crate::game::core::map::MapSpec;
use crate::game::core::terrain::Terrain;
use crate::game::systems::camera::CAMERA_PITCH;
use crate::game::systems::map::{WorldTiles, spawn_map};

/// Trees in one clump, which is to say one forest tile.
const TREES_PER_TILE: usize = 7;

/// How many distinct clumps are built.
///
/// Every forest tile draws one of these, picked by its own coordinates. One
/// clump would stamp the same arrangement across the whole map and the forests
/// would read as wallpaper; a clump per tile would be several thousand meshes
/// and nothing would batch. A handful is enough to break the pattern at this
/// size on screen, and still draws in as many batches as there are variants.
const CLUMP_VARIANTS: usize = 6;

/// Trunk-to-tip height of one tree, before the correction below.
const TREE_HEIGHT: f32 = 21.0;

/// Canopy width as a fraction of height.
const TREE_ASPECT: f32 = 0.62;

/// How far from the tile centre trees are scattered, against a hex whose
/// circumradius is `HEX_SIZE`. Slightly inside it: a little overhang looks like
/// a wood rather than a hedge, but a tree centred on the rim hangs half its
/// canopy over the neighbour, and over open water it is obvious.
const SCATTER_RADIUS: f32 = HEX_SIZE * 0.66;

pub struct TreePlugin;

impl Plugin for TreePlugin {
    fn build(&self, app: &mut App) {
        // After the map, which is what says where the forests are.
        app.add_systems(Startup, spawn_trees.after(spawn_map));
    }
}

fn spawn_trees(
    mut commands: Commands,
    spec: Res<MapSpec>,
    world: Res<WorldTiles>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut images: ResMut<Assets<Image>>,
) {
    let material = materials.add(StandardMaterial {
        base_color_texture: Some(images.add(conifer_texture())),
        // Mask, not Blend. A masked quad writes depth, so trees occlude each
        // other and the terrain correctly with no sorting; blended ones would
        // need to be drawn back to front, which is a per-frame sort over every
        // tree on screen for an effect nothing here needs.
        alpha_mode: AlphaMode::Mask(0.5),
        perceptual_roughness: 0.95,
        ..default()
    });

    let clumps: Vec<Handle<Mesh>> = (0..CLUMP_VARIANTS)
        .map(|v| meshes.add(clump_mesh(v as u32)))
        .collect();

    let mut planted = 0usize;

    for offset in spec.tiles() {
        if world.at(*spec, offset) != Some(Terrain::Forest) {
            continue;
        }

        // Which clump this tile draws. Hashed from the tile's own coordinates
        // rather than counted, so it does not change when the neighbouring
        // terrain does.
        let variant = (hash(offset.col as u32, offset.row as u32, 0xC1u32) * CLUMP_VARIANTS as f32)
            as usize % CLUMP_VARIANTS;

        // On the tile's top face, not its centre: `elevation` is where the
        // column's surface is, which is what the trees stand on.
        let position = offset.to_hex().to_world(Terrain::Forest.elevation());

        commands.spawn((
            Mesh3d(clumps[variant].clone()),
            MeshMaterial3d(material.clone()),
            Transform::from_translation(position),
            // Wraps with the map. `wrap_tiles` moves everything carrying this,
            // so trees cross the seam with the ground they stand on.
            BasePosition(position),
            // A quad turned edge-on to the sun casts a shadow that is a line,
            // and one turned toward it casts a rectangle. Neither is a tree,
            // and several thousand of them is not free either.
            NotShadowCaster,
        ));
        planted += 1;
    }

    info!("planted {planted} forest tiles");
}

/// Build one clump: `TREES_PER_TILE` quads in the tile's local space.
///
/// Baked into a single mesh rather than spawned as an entity each. At this
/// scale the cost of a tree is not its two triangles, it is being an entity --
/// a visibility computation every frame and a transform propagated on every
/// camera move. One mesh per tile keeps the entity count in the same order as
/// the tiles themselves.
fn clump_mesh(variant: u32) -> Mesh {
    // Vertical distances are foreshortened by the camera's pitch and horizontal
    // ones are not, so a quad built to the height it should look would come out
    // squat. This is the exact factor, which is why the trees are modelled at
    // their apparent size and corrected here rather than eyeballed taller.
    let stretch = 1.0 / CAMERA_PITCH.cos();

    // The camera direction, which is constant. Used as the quad normal: it is
    // where the scene sun is as well, so trees come out lit. A quad's own +Z
    // normal faces away from that sun and every tree would render in shadow.
    let normal = Vec3::new(0.0, CAMERA_PITCH.sin(), CAMERA_PITCH.cos());

    let mut positions: Vec<[f32; 3]> = Vec::with_capacity(TREES_PER_TILE * 4);
    let mut normals: Vec<[f32; 3]> = Vec::with_capacity(TREES_PER_TILE * 4);
    let mut uvs: Vec<[f32; 2]> = Vec::with_capacity(TREES_PER_TILE * 4);
    let mut indices: Vec<u32> = Vec::with_capacity(TREES_PER_TILE * 6);

    for i in 0..TREES_PER_TILE {
        // A golden-angle spiral, jittered. Placing by rejection sampling would
        // clump some tiles and leave others bare, which at seven trees is very
        // visible; the spiral spreads them evenly and the jitter stops the
        // spiral itself from being legible.
        let t = (i as f32 + 0.5) / TREES_PER_TILE as f32;
        let angle = i as f32 * 2.399_963_2
            + hash(variant, i as u32, 0x5Eu32) * std::f32::consts::TAU;
        let radius = t.sqrt() * SCATTER_RADIUS;

        let centre = Vec2::new(angle.cos(), angle.sin()) * radius;

        // Size varies per tree. A stand of identical trees reads as a texture;
        // this is most of what makes it read as trees.
        let scale = 0.78 + hash(variant, i as u32, 0xA3u32) * 0.44;
        let height = TREE_HEIGHT * scale * stretch;
        let half_width = TREE_HEIGHT * scale * TREE_ASPECT * 0.5;

        let base = positions.len() as u32;

        // Standing on the tile's surface, so the bottom edge is at y = 0.
        for (dx, dy, u, v) in [
            (-half_width, 0.0, 0.0, 1.0),
            (half_width, 0.0, 1.0, 1.0),
            (half_width, height, 1.0, 0.0),
            (-half_width, height, 0.0, 0.0),
        ] {
            // Z carries the scatter's second axis: the quad stands in XY, so
            // the tile's depth is the world Z the tree is placed at.
            positions.push([centre.x + dx, dy, centre.y]);
            normals.push(normal.to_array());
            uvs.push([u, v]);
        }

        indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
    }

    Mesh::new(
        PrimitiveTopology::TriangleList,
        RenderAssetUsages::RENDER_WORLD,
    )
    .with_inserted_attribute(Mesh::ATTRIBUTE_POSITION, positions)
    .with_inserted_attribute(Mesh::ATTRIBUTE_NORMAL, normals)
    .with_inserted_attribute(Mesh::ATTRIBUTE_UV_0, uvs)
    .with_inserted_indices(Indices::U32(indices))
}

/// Width and height of the tree sprite.
const SPRITE_W: usize = 64;
const SPRITE_H: usize = 96;

/// Draw a conifer.
///
/// Generated rather than loaded. A tree is about thirty pixels tall on screen
/// at the default zoom, so what carries it is the silhouette and a light side,
/// and both of those are a few lines of arithmetic -- against a PNG, which is
/// another LFS object, another licence to record, and another thing to keep in
/// step with the hex size. Swapping in real art later is a change to this
/// function and nothing else.
fn conifer_texture() -> Image {
    let mut data = vec![0u8; SPRITE_W * SPRITE_H * 4];

    // Three overlapping tiers, each a triangle widening toward its base. The
    // overlap is what gives a conifer its stepped outline; a single triangle
    // reads as a cone.
    const TIERS: usize = 3;
    let trunk_top = (SPRITE_H as f32 * 0.80) as usize;

    for y in 0..SPRITE_H {
        for x in 0..SPRITE_W {
            let fx = x as f32 / SPRITE_W as f32;
            let fy = y as f32 / SPRITE_H as f32;

            let mut inside = false;

            // Trunk: a narrow column under the canopy.
            if y >= trunk_top && (fx - 0.5).abs() < 0.045 {
                let idx = (y * SPRITE_W + x) * 4;
                data[idx..idx + 4].copy_from_slice(&[74, 52, 34, 255]);
                continue;
            }

            for tier in 0..TIERS {
                // Each tier starts higher up and reaches lower down than the
                // one above, so they overlap rather than stack.
                let top = 0.05 + tier as f32 * 0.24;
                let bottom = top + 0.42;
                if fy < top || fy > bottom {
                    continue;
                }
                // Widening from the tier's own apex, and wider for lower tiers.
                let along = (fy - top) / (bottom - top);
                let half = along * (0.16 + tier as f32 * 0.10);
                if (fx - 0.5).abs() <= half {
                    inside = true;
                    break;
                }
            }

            if !inside {
                continue;
            }

            // Lit from the left, matching the scene sun, whose direction has a
            // negative x. Flat-shaded terrain next to a smoothly shaded tree
            // would look out of place, so this is two tones and no gradient.
            let lit = fx < 0.46;
            let shade = if lit { 1.0 } else { 0.72 };
            // Darker toward the base, where a real canopy is in its own shadow.
            let depth = 1.0 - fy * 0.28;

            let rgb = [
                (0.20 * 255.0 * shade * depth) as u8,
                (0.44 * 255.0 * shade * depth) as u8,
                (0.22 * 255.0 * shade * depth) as u8,
            ];

            let idx = (y * SPRITE_W + x) * 4;
            data[idx..idx + 3].copy_from_slice(&rgb);
            data[idx + 3] = 255;
        }
    }

    Image::new(
        Extent3d {
            width: SPRITE_W as u32,
            height: SPRITE_H as u32,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        data,
        // Srgb: these are colours picked by eye, so they are in the space the
        // eye picked them in.
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::RENDER_WORLD,
    )
}

/// Deterministic value in `0.0..1.0` from two coordinates and a salt.
///
/// The same splitmix-style mixing the terrain generator uses, and for the same
/// reason: placement has to survive a reload, so it cannot come from an RNG
/// whose state depends on the order tiles happen to be visited in.
fn hash(a: u32, b: u32, salt: u32) -> f32 {
    let mut z = (a as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    z ^= (b as u64).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z ^= (salt as u64).wrapping_mul(0x94D0_49BB_1331_11EB);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;
    ((z >> 40) as f32) / ((1u32 << 24) as f32)
}
