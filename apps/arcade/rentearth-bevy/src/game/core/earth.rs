//! Earth's coastlines, as a baked land mask.
//!
//! Generated from Natural Earth's public-domain 10m land polygons by
//! `tools/gen_earth_mask.py` and committed, so the game ships no GeoJSON parser
//! and loads no asset. Regenerate only when the source or the resolution
//! changes.
//!
//! The mask is equirectangular -- column 0 is longitude -180, row 0 is latitude
//! +90 -- which is why it drops onto a wrapping hex map without special casing:
//! longitude is already cyclic.

/// Rows of `#` (land) and `.` (water), newline separated.
const MASK: &str = include_str!("earth_mask.txt");

pub const MASK_WIDTH: usize = 1024;
pub const MASK_HEIGHT: usize = 512;

/// Is the tile at this fraction of the way across the world on land?
///
/// Takes normalised coordinates rather than tile indices so the mask's
/// resolution stays independent of the map's: a 64-column map and a 200-column
/// map both sample the same data, just at different densities.
///
/// `u` runs 0..1 west to east and wraps; `v` runs 0..1 north to south and
/// clamps, because the poles are edges of the data even when the game's world
/// wraps through them.
pub fn is_land(u: f32, v: f32) -> bool {
    let x = ((u.rem_euclid(1.0) * MASK_WIDTH as f32) as usize).min(MASK_WIDTH - 1);
    let y = ((v.clamp(0.0, 1.0) * MASK_HEIGHT as f32) as usize).min(MASK_HEIGHT - 1);

    // Fixed-width rows plus one newline each, so a cell is a single index
    // rather than a split or a scan.
    let stride = MASK_WIDTH + 1;
    MASK.as_bytes()[y * stride + x] == b'#'
}

/// How much of the neighbourhood around a point is land, in `0.0..1.0`.
///
/// A hex tile on a 64-wide map covers about four mask cells, so testing only
/// the centre throws away most of the coastline and produces ragged, bitty
/// islands. Sampling a small window and returning the fraction lets the caller
/// decide the threshold -- which is also what makes coastlines land on tile
/// boundaries rather than inside them.
pub fn land_fraction(u: f32, v: f32, radius_u: f32, radius_v: f32) -> f32 {
    const STEPS: i32 = 3;

    let mut land = 0;
    let mut total = 0;
    for sy in -STEPS..=STEPS {
        for sx in -STEPS..=STEPS {
            let du = radius_u * sx as f32 / STEPS as f32;
            let dv = radius_v * sy as f32 / STEPS as f32;
            if is_land(u + du, v + dv) {
                land += 1;
            }
            total += 1;
        }
    }
    land as f32 / total as f32
}
