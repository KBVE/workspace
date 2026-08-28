//! Trees on forest tiles.
//!
//! Billboards, in the 2.5D sense: flat quads standing upright in the world.
//! What makes them cheap here is that the camera never yaws -- `apply_rig`
//! builds its transform from a constant offset and a fixed pitch, so a quad
//! lying in the XY plane already faces it, from every tile, forever. There is
//! no per-frame system pointing anything at anything.

use bevy::asset::RenderAssetUsages;
use bevy::image::{ImageFilterMode, ImageLoaderSettings, ImageSampler, ImageSamplerDescriptor};
use bevy::light::NotShadowCaster;
use bevy::prelude::*;
use bevy::render::mesh::{Indices, PrimitiveTopology};

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

/// World height of a full atlas cell.
///
/// Not of a tree: sprites are bottom-aligned inside a cell they do not all
/// fill, so a spruce occupying half its cell draws half as tall as a pine
/// filling one. That is the point -- the pack's own proportions decide how the
/// biomes compare, rather than a number per biome here.
const TREE_HEIGHT: f32 = 30.0;

/// Canopy width as a fraction of height. The atlas cell's own proportions --
/// the quad has to match the sprite or the trees come out stretched.
const TREE_ASPECT: f32 = ATLAS_CELL_W / ATLAS_CELL_H;

/// One cell of the tree atlas, in pixels.
const ATLAS_CELL_W: f32 = 64.0;
const ATLAS_CELL_H: f32 = 144.0;

/// Which run of atlas cells each wooded biome draws from.
///
/// Half-open, in cells. The atlas is ordered by biome so a range is a pair
/// rather than a list: spruce, then broadleaf, then pine.
const TAIGA_CELLS: std::ops::Range<usize> = 0..4;
const FOREST_CELLS: std::ops::Range<usize> = 4..6;
const JUNGLE_CELLS: std::ops::Range<usize> = 6..8;

/// Total cells across the atlas, which is what a UV is measured against.
const ATLAS_CELLS: usize = 8;

/// The biomes that carry trees, and where their trees come from.
fn tree_cells(terrain: Terrain) -> Option<std::ops::Range<usize>> {
    match terrain {
        Terrain::Forest => Some(FOREST_CELLS),
        Terrain::Jungle => Some(JUNGLE_CELLS),
        Terrain::Taiga => Some(TAIGA_CELLS),
        _ => None,
    }
}

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
    assets: Res<AssetServer>,
    spec: Res<MapSpec>,
    world: Res<WorldTiles>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    // Nearest, not linear. These are pixel art: filtering them averages
    // neighbouring pixels into the mush that the art is drawn to avoid, and
    // the hard edge is the whole point of the style.
    let atlas = assets
        .load_builder()
        .with_settings(|settings: &mut ImageLoaderSettings| {
            settings.sampler = ImageSampler::Descriptor(ImageSamplerDescriptor {
                mag_filter: ImageFilterMode::Nearest,
                min_filter: ImageFilterMode::Nearest,
                ..ImageSamplerDescriptor::default()
            });
        })
        .load("trees/trees.png");

    let material = materials.add(StandardMaterial {
        base_color_texture: Some(atlas),
        // Mask, not Blend. A masked quad writes depth, so trees occlude each
        // other and the terrain correctly with no sorting; blended ones would
        // need to be drawn back to front, which is a per-frame sort over every
        // tree on screen for an effect nothing here needs.
        alpha_mode: AlphaMode::Mask(0.5),
        perceptual_roughness: 0.95,
        ..default()
    });

    // A clump per (biome, variant). Every clump is still one mesh and they all
    // share the one material, so the whole forest draws in as many calls as
    // there are combinations here -- and only for the ones on screen.
    let biomes = [Terrain::Forest, Terrain::Jungle, Terrain::Taiga];
    let clumps: Vec<Vec<Handle<Mesh>>> = biomes
        .iter()
        .map(|t| {
            let cells = tree_cells(*t).expect("listed biome has no trees");
            (0..CLUMP_VARIANTS)
                .map(|v| meshes.add(clump_mesh(v as u32, cells.clone())))
                .collect()
        })
        .collect();

    let mut planted = 0usize;
    let mut first: Option<Vec3> = None;

    for offset in spec.tiles() {
        let Some(kind) = world.at(*spec, offset) else {
            continue;
        };
        let Some(biome) = biomes.iter().position(|t| *t == kind) else {
            continue;
        };

        // Which clump this tile draws. Hashed from the tile's own coordinates
        // rather than counted, so it does not change when the neighbouring
        // terrain does.
        let variant = (hash(offset.col as u32, offset.row as u32, 0xC1u32) * CLUMP_VARIANTS as f32)
            as usize % CLUMP_VARIANTS;

        // On the tile's top face, not its centre: `elevation` is where the
        // column's surface is, which is what the trees stand on.
        let position = offset.to_hex().to_world(kind.elevation());

        commands.spawn((
            Mesh3d(clumps[biome][variant].clone()),
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
        first.get_or_insert(position);
    }

    // The position as well as the count. Forests are a small fraction of the
    // map, so "planted 122" on its own leaves no way to go and look at one.
    match first {
        Some(p) => info!("planted {planted} wooded tiles; first at x {:.0} z {:.0}", p.x, p.z),
        None => info!("planted no wooded tiles"),
    }
}

/// Build one clump: `TREES_PER_TILE` quads in the tile's local space.
///
/// Baked into a single mesh rather than spawned as an entity each. At this
/// scale the cost of a tree is not its two triangles, it is being an entity --
/// a visibility computation every frame and a transform propagated on every
/// camera move. One mesh per tile keeps the entity count in the same order as
/// the tiles themselves.
fn clump_mesh(variant: u32, cells: std::ops::Range<usize>) -> Mesh {
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

        // Which tree in the atlas. Picked per tree rather than per clump, so a
        // single tile carries more than one shade of green -- a stand of one
        // colour reads as a solid block from any distance.
        let span = cells.len();
        let cell = cells.start + (hash(variant, i as u32, 0x7Bu32) * span as f32) as usize % span;
        let u0 = cell as f32 / ATLAS_CELLS as f32;
        let u1 = (cell + 1) as f32 / ATLAS_CELLS as f32;

        // Standing on the tile's surface, so the bottom edge is at y = 0.
        for (dx, dy, u, v) in [
            (-half_width, 0.0, u0, 1.0),
            (half_width, 0.0, u1, 1.0),
            (half_width, height, u1, 0.0),
            (-half_width, height, u0, 0.0),
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
