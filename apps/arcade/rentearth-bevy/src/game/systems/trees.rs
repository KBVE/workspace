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

use crate::game::components::camera::CameraRig;
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
/// Not a free choice: it sets how many atlas texels land on a screen pixel, and
/// so whether the mip chain is sampled at a level or between two. See
/// `CameraRig::ZOOM_LEVELS`, which is picked against this number.
///
/// Not of a tree: sprites are bottom-aligned inside a cell they do not all
/// fill, so a spruce occupying half its cell draws half as tall as a pine
/// filling one. That is the point -- the pack's own proportions decide how the
/// biomes compare, rather than a number per biome here.
const TREE_HEIGHT: f32 = 36.0;

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
        app.add_systems(Startup, spawn_trees.after(spawn_map))
            .add_systems(Update, add_mipmaps);
    }
}

/// Levels in the tree atlas's mip chain, the full-size image included.
///
/// Not the whole chain down to a pixel. The atlas packs its trees side by side
/// with only a few pixels of gutter -- the jungle pines are 63 texels into a
/// 64-texel cell -- and every halving spends some of it, so a fifth level would
/// start averaging neighbouring trees together. Four covers minification to an
/// eighth of full size, which is the furthest the camera goes. Reaching further
/// out means halving each cell on its own rather than the atlas as a whole.
const MIP_LEVELS: u32 = 4;

/// The atlas, and whether its mip chain has been built yet.
#[derive(Resource)]
struct TreeAtlas {
    handle: Handle<Image>,
    done: bool,
}

fn spawn_trees(
    mut commands: Commands,
    assets: Res<AssetServer>,
    spec: Res<MapSpec>,
    world: Res<WorldTiles>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    // Nearest when magnified, filtered when minified -- which is not a
    // compromise between two tastes but a response to two different situations.
    // Magnified, nearest is the whole point of pixel art. Minified, it is a
    // bug: a tree is 144 pixels of atlas drawn into some 40 pixels of screen,
    // so nearest keeps one texel in four and throws the rest away, and which
    // one it keeps changes as the camera slides by a fraction of a pixel. That
    // is the swimming. Filtering plus the mip chain below averages what nearest
    // was picking between, and the pixels sit still.
    let atlas = assets
        .load_builder()
        .with_settings(|settings: &mut ImageLoaderSettings| {
            // The mip chain is built on the CPU from this data, so it has to
            // survive being uploaded rather than being dropped at once.
            settings.asset_usage = RenderAssetUsages::MAIN_WORLD | RenderAssetUsages::RENDER_WORLD;
            settings.sampler = ImageSampler::Descriptor(ImageSamplerDescriptor {
                mag_filter: ImageFilterMode::Nearest,
                min_filter: ImageFilterMode::Linear,
                mipmap_filter: ImageFilterMode::Linear,
                ..ImageSamplerDescriptor::default()
            });
        })
        .load("trees/trees.png");

    commands.insert_resource(TreeAtlas {
        handle: atlas.clone(),
        done: false,
    });

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

/// Build the atlas's mip chain, once, as soon as it has loaded.
///
/// Bevy does not generate mipmaps for a PNG, and without them a minified
/// texture aliases however it is sampled -- the filter chooses between four
/// texels when sixteen are covered. This does the averaging properly, ahead of
/// time.
fn add_mipmaps(atlas: Option<ResMut<TreeAtlas>>, mut images: ResMut<Assets<Image>>) {
    let Some(mut atlas) = atlas else {
        return;
    };
    if atlas.done {
        return;
    }
    let Some(mut image) = images.get_mut(&atlas.handle) else {
        return;
    };
    let Some(data) = image.data.as_ref() else {
        return;
    };

    // The chain has to reach the furthest zoom, or the coarsest level aliases.
    // Each zoom level doubles the texels per pixel and each mip halves them, so
    // the last level needs `log2` of its ratio. Levels closer than one texel per
    // pixel magnify and need no mip at all, which is why there are fewer of
    // these than there are zoom levels. See `CameraRig::ZOOM_LEVELS`.
    debug_assert!(
        CameraRig::ZOOM_LEVELS
            .last()
            .is_some_and(|z| 2.0 * z <= (1u32 << (MIP_LEVELS - 1)) as f32),
        "the mip chain does not reach the furthest zoom level",
    );

    let width = image.texture_descriptor.size.width;
    let height = image.texture_descriptor.size.height;

    let mut chain = data.clone();
    let mut level = data.clone();
    let (mut w, mut h) = (width, height);

    // Coverage under the alpha mask at full size. Every smaller level is scaled
    // to match it: averaging alpha shrinks it toward the middle, so a tree that
    // covered a little over half a texel drops under the cutoff and disappears.
    // Left alone, forests thin out as the camera pulls back -- which reads as a
    // level-of-detail system rather than as the bug it is.
    let target = coverage(&level);

    for _ in 1..MIP_LEVELS {
        let (nw, nh) = ((w / 2).max(1), (h / 2).max(1));
        let mut next = halve(&level, w, h);
        rescale_alpha(&mut next, target);
        chain.extend_from_slice(&next);
        level = next;
        w = nw;
        h = nh;
    }

    image.texture_descriptor.mip_level_count = MIP_LEVELS;
    image.data = Some(chain);
    atlas.done = true;
}

/// Fraction of texels that pass the alpha cutoff.
fn coverage(rgba: &[u8]) -> f32 {
    let passing = rgba.chunks_exact(4).filter(|p| p[3] >= 128).count();
    passing as f32 / (rgba.len() / 4).max(1) as f32
}

/// Halve an RGBA image, averaging colour weighted by alpha.
///
/// Weighted, because a transparent texel's colour is arbitrary -- here it is
/// black -- and averaging it in unweighted draws a dark rim around everything
/// as the tree shrinks.
fn halve(rgba: &[u8], w: u32, h: u32) -> Vec<u8> {
    let (nw, nh) = ((w / 2).max(1), (h / 2).max(1));
    let mut out = vec![0u8; (nw * nh * 4) as usize];

    for y in 0..nh {
        for x in 0..nw {
            let mut rgb = [0.0f32; 3];
            let mut alpha = 0.0f32;
            let mut weight = 0.0f32;

            for dy in 0..2 {
                for dx in 0..2 {
                    let sx = (x * 2 + dx).min(w - 1);
                    let sy = (y * 2 + dy).min(h - 1);
                    let i = ((sy * w + sx) * 4) as usize;
                    let a = rgba[i + 3] as f32 / 255.0;
                    for c in 0..3 {
                        rgb[c] += rgba[i + c] as f32 * a;
                    }
                    alpha += a;
                    weight += a;
                }
            }

            let o = ((y * nw + x) * 4) as usize;
            if weight > 0.0 {
                for c in 0..3 {
                    out[o + c] = (rgb[c] / weight).round().clamp(0.0, 255.0) as u8;
                }
            }
            out[o + 3] = (alpha / 4.0 * 255.0).round().clamp(0.0, 255.0) as u8;
        }
    }

    out
}

/// Scale a level's alpha until it covers the same fraction as the original.
///
/// Found by bisection rather than solved: coverage is a step function of the
/// scale, so there is nothing to invert.
fn rescale_alpha(rgba: &mut [u8], target: f32) {
    let (mut low, mut high) = (0.0f32, 4.0f32);
    let mut best = 1.0f32;

    for _ in 0..12 {
        let mid = (low + high) / 2.0;
        let covered = rgba
            .chunks_exact(4)
            .filter(|p| (p[3] as f32 * mid) >= 128.0)
            .count() as f32
            / (rgba.len() / 4).max(1) as f32;

        best = mid;
        if covered < target {
            low = mid;
        } else {
            high = mid;
        }
    }

    for p in rgba.chunks_exact_mut(4) {
        p[3] = (p[3] as f32 * best).round().clamp(0.0, 255.0) as u8;
    }
}
