//! Terrain kinds and world generation.
//!
//! The generator is value noise plus a latitude band -- no external noise crate
//! and no RNG state, so a given `MapSpec` always produces the same world. Real
//! generation (plates, rainfall, rivers, resources) replaces `generate` and
//! should not need to touch anything else.

use bevy::prelude::*;

use super::earth;
use super::map::{MapSpec, Offset, WorldSource};

/// Height of the water surface. Land elevations are measured against it: at or
/// below this and a tile would be underwater.
pub const SEA_LEVEL: f32 = -3.0;

#[derive(Component, Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Terrain {
    Ocean,
    Coast,
    Desert,
    Plains,
    Grassland,
    Forest,
    Jungle,
    Taiga,
    Hills,
    Mountain,
    Tundra,
    Ice,
}

impl Terrain {
    pub const ALL: [Terrain; 12] = [
        Terrain::Ocean,
        Terrain::Coast,
        Terrain::Desert,
        Terrain::Plains,
        Terrain::Grassland,
        Terrain::Forest,
        Terrain::Jungle,
        Terrain::Taiga,
        Terrain::Hills,
        Terrain::Mountain,
        Terrain::Tundra,
        Terrain::Ice,
    ];

    pub fn is_water(self) -> bool {
        matches!(self, Terrain::Ocean | Terrain::Coast)
    }

    pub fn color(self) -> Color {
        match self {
            Terrain::Ocean => Color::srgb(0.09, 0.20, 0.38),
            Terrain::Coast => Color::srgb(0.17, 0.40, 0.58),
            Terrain::Desert => Color::srgb(0.84, 0.76, 0.52),
            Terrain::Plains => Color::srgb(0.72, 0.69, 0.37),
            Terrain::Grassland => Color::srgb(0.40, 0.59, 0.27),
            Terrain::Forest => Color::srgb(0.20, 0.40, 0.23),
            // Darker and less yellow than forest, so the tropics read as their
            // own band rather than as more of the same green.
            Terrain::Jungle => Color::srgb(0.12, 0.32, 0.16),
            // Toward grey: boreal ground is moss and rock, not pasture.
            Terrain::Taiga => Color::srgb(0.24, 0.37, 0.29),
            Terrain::Hills => Color::srgb(0.49, 0.46, 0.33),
            Terrain::Mountain => Color::srgb(0.54, 0.52, 0.53),
            Terrain::Tundra => Color::srgb(0.63, 0.65, 0.59),
            Terrain::Ice => Color::srgb(0.90, 0.93, 0.96),
        }
    }

    /// Height of the tile's top face, in world units.
    ///
    /// Every column is drawn down to a shared base, so this is what gives the
    /// map its relief: mountains stand well above plains, water sits below the
    /// land it meets, and the exposed column sides read as cliffs.
    ///
    /// Every water tile returns exactly `SEA_LEVEL`. A tile's top face is the
    /// water's surface, and water is level -- giving ocean and coast different
    /// heights would put a step in the middle of the sea. Depth is carried by
    /// colour instead, which is the only place it can go.
    pub fn elevation(self) -> f32 {
        match self {
            Terrain::Ocean | Terrain::Coast => SEA_LEVEL,
            Terrain::Desert => 2.0,
            Terrain::Plains => 3.0,
            Terrain::Grassland => 3.0,
            Terrain::Tundra => 3.0,
            Terrain::Ice => 4.0,
            Terrain::Forest => 5.0,
            Terrain::Jungle => 5.0,
            Terrain::Taiga => 4.0,
            Terrain::Hills => 11.0,
            Terrain::Mountain => 24.0,
        }
    }
}

/// Build the whole world.
///
/// Two passes, because coast cannot be decided per tile in isolation: it is
/// ocean that touches land, so the land has to exist first.
pub fn generate(spec: MapSpec) -> Vec<(Offset, Terrain)> {
    let land: Vec<(Offset, Terrain)> = spec.tiles().map(|o| (o, classify(spec, o))).collect();

    let is_land = |col: i32, row: i32| -> bool {
        // Both axes wrap, so neither seam becomes a permanent coastline.
        let row = row.rem_euclid(spec.rows);
        let col = col.rem_euclid(spec.cols);
        let idx = (row * spec.cols + col) as usize;
        !land[idx].1.is_water()
    };

    // Coast is decided while `is_land` still borrows `land`. Collecting into
    // its own vector ends that borrow, so `land` can be consumed below.
    let coastal: Vec<bool> = land
        .iter()
        .map(|(o, t)| *t == Terrain::Ocean && touches_land(*o, &is_land))
        .collect();

    land.into_iter()
        .zip(coastal)
        .map(|((o, t), is_coast)| {
            if is_coast {
                (o, Terrain::Coast)
            } else {
                (o, t)
            }
        })
        .collect()
}

/// The six neighbours in odd-r offset coordinates. The column deltas differ
/// between even and odd rows, which is the price of storing a sheared grid as a
/// rectangle.
fn touches_land(o: Offset, is_land: &impl Fn(i32, i32) -> bool) -> bool {
    let odd = o.row & 1 == 1;
    let shift = if odd { 0 } else { -1 };
    let deltas = [
        (-1, 0),
        (1, 0),
        (shift, -1),
        (shift + 1, -1),
        (shift, 1),
        (shift + 1, 1),
    ];
    deltas
        .iter()
        .any(|(dc, dr)| is_land(o.col + dc, o.row + dr))
}

/// Is this tile land?
///
/// Earth reads the baked coastline mask; procedural worlds fall back to noise
/// with a sea level that rises toward the poles, so the ice caps sit in water
/// and the continents do not run pole to pole as stripes.
fn is_land(spec: MapSpec, o: Offset) -> bool {
    match spec.source {
        WorldSource::Earth => {
            let (u, v) = spec.normalised(o);
            // Average over the tile's own footprint rather than its centre
            // point. A tile covers several mask cells, and sampling one throws
            // away the coastline between them -- islands come out bitty and
            // peninsulas disappear.
            let half_u = 0.5 / spec.cols as f32;
            let half_v = 0.5 / spec.rows as f32;
            // Slightly below half, so a tile only becomes land when land
            // clearly dominates it. Above half and the coasts bloat outward.
            earth::land_fraction(u, v, half_u, half_v) > 0.42
        }
        WorldSource::Procedural => {
            let lat = spec.latitude(o);
            fbm(spec, o, 0.09, 4) >= 0.46 + lat * 0.16
        }
    }
}

/// Terrain for one tile, ignoring its neighbours.
fn classify(spec: MapSpec, o: Offset) -> Terrain {
    let lat = spec.latitude(o);

    if !is_land(spec, o) {
        return Terrain::Ocean;
    }

    if lat > 0.93 {
        return Terrain::Ice;
    }
    // Pulled back from 0.76 to leave a boreal band between the ice and the
    // temperate zone, which is where the conifers live.
    if lat > 0.80 {
        return Terrain::Tundra;
    }

    // Relief, at a higher frequency than the continents so mountain chains sit
    // inside landmasses rather than defining them.
    let relief = fbm(spec, o, 0.21, 3);
    if relief > 0.74 {
        return Terrain::Mountain;
    }
    if relief > 0.62 {
        return Terrain::Hills;
    }

    let moisture = moisture(spec, o, lat);

    // Cold and wet is conifer, not broadleaf.
    if lat > 0.62 {
        return if moisture > 0.46 {
            Terrain::Taiga
        } else {
            Terrain::Plains
        };
    }

    // Hot and wet.
    if lat < 0.20 && moisture > 0.54 {
        return Terrain::Jungle;
    }

    match moisture {
        m if m < 0.36 => Terrain::Desert,
        m if m < 0.46 => Terrain::Plains,
        m if m < 0.56 => Terrain::Grassland,
        _ => Terrain::Forest,
    }
}

/// How wet a tile is, in roughly `0.2..0.8`.
///
/// The band this returns matters more than the shape. `fbm` averages several
/// octaves of value noise, so its output clusters hard around 0.5 and only
/// rarely approaches either end -- a threshold set at 0.66, as the forest one
/// was, sits outside what the noise can actually produce often enough to
/// matter, and the biome it guards effectively does not exist. The previous
/// formula also subtracted a term that reached 0.42 at its worst, pushing the
/// whole distribution below every threshold above desert. Forest came out on
/// 122 tiles out of 73728.
fn moisture(spec: MapSpec, o: Offset, lat: f32) -> f32 {
    let wet = fbm(spec, o, 0.15, 3);

    // A dry belt at the horse latitudes, where the real deserts are, fading to
    // nothing toward the equator and toward the poles. Bounded well under the
    // spread of `wet` so it biases the result rather than dominating it.
    let dryness = 0.30 * (1.0 - ((lat - 0.32).abs() / 0.20).min(1.0));

    wet - dryness
}

/// Fractal noise: several octaves of value noise summed with halving amplitude.
///
/// Returns roughly `0.0..1.0`.
fn fbm(spec: MapSpec, o: Offset, base_freq: f32, octaves: u32) -> f32 {
    let mut total = 0.0;
    let mut amplitude = 1.0;
    let mut norm = 0.0;
    let mut freq = base_freq;

    for octave in 0..octaves {
        total += value_noise(spec, o, freq, octave) * amplitude;
        norm += amplitude;
        amplitude *= 0.5;
        freq *= 2.0;
    }

    total / norm
}

/// Value noise on a torus.
///
/// Both axes are sampled as angles rather than distances, so the lattice meets
/// itself at both seams and terrain stays continuous wherever the map wraps.
/// Sampled as a plane it would leave visible discontinuities at column 0 and
/// row 0 -- exactly where a wrapping camera spends its time.
fn value_noise(spec: MapSpec, o: Offset, freq: f32, seed: u32) -> f32 {
    // Lattice cells around the cylinder. At least 2, or the wrap degenerates.
    let cells_x = ((spec.cols as f32 * freq).round() as i32).max(2);
    let cells_y = ((spec.rows as f32 * freq).round() as i32).max(2);
    let x = o.col as f32 * cells_x as f32 / spec.cols as f32;
    let y = o.row as f32 * cells_y as f32 / spec.rows as f32;

    let (x0, y0) = (x.floor(), y.floor());
    let (fx, fy) = (x - x0, y - y0);

    // Smoothstep, so cell boundaries do not show up as creases.
    let (sx, sy) = (smooth(fx), smooth(fy));

    let xi = x0 as i32;
    let yi = y0 as i32;

    let wx = |i: i32| i.rem_euclid(cells_x);
    let wy = |i: i32| i.rem_euclid(cells_y);

    let c00 = lattice(wx(xi), wy(yi), seed);
    let c10 = lattice(wx(xi + 1), wy(yi), seed);
    let c01 = lattice(wx(xi), wy(yi + 1), seed);
    let c11 = lattice(wx(xi + 1), wy(yi + 1), seed);

    let top = c00 + (c10 - c00) * sx;
    let bottom = c01 + (c11 - c01) * sx;
    top + (bottom - top) * sy
}

fn smooth(t: f32) -> f32 {
    t * t * (3.0 - 2.0 * t)
}

/// Deterministic value at a lattice point, in `0.0..1.0`.
///
/// Splitmix64-style mixing: cheap, dependency-free, and well enough distributed
/// that neighbouring cells do not correlate the way a naive `x * 31 + y` would.
fn lattice(x: i32, y: i32, seed: u32) -> f32 {
    // Through i64 first so negatives sign-extend rather than wrapping to huge
    // positives -- otherwise the halves of the map hash differently and a seam
    // appears through the origin.
    let mut z = (x as i64 as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    z ^= (y as i64 as u64).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z ^= (seed as u64).wrapping_mul(0x94D0_49BB_1331_11EB);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;
    // Top 24 bits only: plenty of resolution, and it avoids the low bits where
    // the mixing is weakest.
    ((z >> 40) as f32) / ((1u32 << 24) as f32)
}
