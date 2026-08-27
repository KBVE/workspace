//! The world's shape.
//!
//! A Civ-style map, which is a rectangle of hexes that wraps east-west and does
//! not wrap north-south. That asymmetry is the whole reason this type exists:
//! the wrap makes "how far apart are two tiles" and "where does the camera stop"
//! different questions than they are on a flat rectangle, and both answers have
//! to come from one place.

use bevy::prelude::*;

use super::hex::{Hex, HEX_HEIGHT_STEP, HEX_WIDTH};

/// Where a world's coastlines come from.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum WorldSource {
    /// Earth, from the baked Natural Earth land mask.
    #[default]
    Earth,
    /// Generated coastlines. Same relief and biome rules, different land.
    Procedural,
}

/// Dimensions of the world, in tiles.
///
/// Held as a resource so map size is set once at startup and every system --
/// generation, camera clamping, wrapping -- reads the same numbers.
#[derive(Resource, Clone, Copy, Debug)]
pub struct MapSpec {
    pub cols: i32,
    pub rows: i32,
    pub source: WorldSource,
}

impl Default for MapSpec {
    fn default() -> Self {
        // Roughly Civ's "small": wide enough that the wrap matters, short
        // enough that the poles stay on screen at full zoom-out.
        Self {
            // 2:1, the aspect an equirectangular Earth wants. A different ratio
            // stretches the continents rather than cropping them.
            cols: 384,
            rows: 192,
            source: WorldSource::Earth,
        }
    }
}

impl MapSpec {
    pub fn tile_count(self) -> i32 {
        self.cols * self.rows
    }

    /// Width of the world in world units. Panning this far east returns you to
    /// where you started.
    pub fn world_width(self) -> f32 {
        self.cols as f32 * HEX_WIDTH
    }

    /// North-south extent in world units.
    pub fn world_depth(self) -> f32 {
        self.rows as f32 * HEX_HEIGHT_STEP
    }

    /// Every tile, row by row.
    pub fn tiles(self) -> impl Iterator<Item = Offset> {
        (0..self.rows).flat_map(move |row| (0..self.cols).map(move |col| Offset { col, row }))
    }

    /// Bring an x coordinate back into `0..world_width`, so a camera that has
    /// panned off one edge reappears at the other.
    pub fn wrap_x(self, x: f32) -> f32 {
        x.rem_euclid(self.world_width())
    }

    /// The same north-south.
    ///
    /// This makes the world a torus, not a globe: pan north far enough and you
    /// arrive at the south pole. It only reads as continuous because both
    /// edges are ice, so the terrain matches across the seam even though the
    /// geography does not.
    pub fn wrap_z(self, z: f32) -> f32 {
        z.rem_euclid(self.world_depth())
    }

    /// A tile's position as fractions of the world, west-to-east and
    /// north-to-south. This is the space the Earth mask is sampled in.
    pub fn normalised(self, offset: Offset) -> (f32, f32) {
        (
            (offset.col as f32 + 0.5) / self.cols as f32,
            (offset.row as f32 + 0.5) / self.rows as f32,
        )
    }

    /// How far north-south a tile sits, as `0.0` at the equator to `1.0` at
    /// either pole. Terrain generation bands off this.
    pub fn latitude(self, offset: Offset) -> f32 {
        let mid = (self.rows - 1) as f32 / 2.0;
        ((offset.row as f32 - mid) / mid).abs().min(1.0)
    }
}

/// A tile's address in the rectangle: column and row.
///
/// Storage and wrapping use this rather than axial coordinates, because "wrap
/// the column" is meaningful and "wrap q" is not -- axial rows are sheared, so
/// a constant q is a diagonal across the map, not a column of it.
#[derive(Component, Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Offset {
    pub col: i32,
    pub row: i32,
}

impl Offset {
    /// The six neighbours, in odd-r offset coordinates.
    ///
    /// The column deltas differ between even and odd rows -- that is the price
    /// of storing a sheared grid as a rectangle. Wrapping is the caller's job,
    /// because it needs the map dimensions and this does not.
    pub fn neighbours(self) -> [Offset; 6] {
        let shift = if self.row & 1 == 1 { 0 } else { -1 };
        [
            (-1, 0),
            (1, 0),
            (shift, -1),
            (shift + 1, -1),
            (shift, 1),
            (shift + 1, 1),
        ]
        .map(|(dc, dr)| Offset {
            col: self.col + dc,
            row: self.row + dr,
        })
    }

    /// Bring a neighbour back inside the map. Both axes wrap.
    pub fn wrapped(self, spec: MapSpec) -> Offset {
        Offset {
            col: self.col.rem_euclid(spec.cols),
            row: self.row.rem_euclid(spec.rows),
        }
    }

    /// Index into a row-major buffer of `spec.tile_count()` entries.
    pub fn index(self, spec: MapSpec) -> usize {
        (self.row * spec.cols + self.col) as usize
    }

    /// Inverse of [`to_hex`]: axial back to column and row.
    ///
    /// Needed for picking, where the geometry gives an axial coordinate but the
    /// map is addressed by column and row.
    pub fn from_hex(hex: Hex) -> Self {
        Self {
            col: hex.q + (hex.r - (hex.r & 1)) / 2,
            row: hex.r,
        }
    }

    /// Convert to axial for anything geometric -- distance, neighbours,
    /// world position.
    ///
    /// Odd-r layout: odd rows shift half a tile east, which is what makes the
    /// rows interlock instead of stacking into a grid.
    pub fn to_hex(self) -> Hex {
        let q = self.col - (self.row - (self.row & 1)) / 2;
        Hex::new(q, self.row)
    }
}
