//! Axial hex coordinates.
//!
//! Pointy-top orientation, axial storage. Pointy-top on purpose: Bevy's
//! `RegularPolygon` puts its first vertex straight up, so a 6-gon is already
//! pointy-top and needs no rotation baked into every tile transform.
//!
//! Axial `(q, r)` is cube `(x, y, z)` with the redundant third axis dropped,
//! since `x + y + z == 0` always. Distance needs it back, so `distance()`
//! reconstructs it.

use bevy::prelude::*;

/// Centre-to-vertex radius of one tile, in world units.
pub const HEX_SIZE: f32 = 32.0;

/// Centre-to-centre distance between horizontal neighbours. For a pointy-top
/// hex that is the flat-to-flat width, `sqrt(3) * size`.
pub const HEX_WIDTH: f32 = HEX_SIZE * 1.732_050_8;

/// Centre-to-centre distance between rows. Three quarters of the full height,
/// not the whole of it, because the points interlock.
pub const HEX_HEIGHT_STEP: f32 = HEX_SIZE * 1.5;

/// A tile's position on the map. This is the identity of a tile -- the
/// `Transform` is derived from it, never the other way round.
#[derive(Component, Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Hex {
    pub q: i32,
    pub r: i32,
}

impl Hex {
    pub const ORIGIN: Self = Self { q: 0, r: 0 };

    pub const fn new(q: i32, r: i32) -> Self {
        Self { q, r }
    }

    /// The implied third cube axis.
    const fn s(self) -> i32 {
        -self.q - self.r
    }

    /// Steps between two tiles. In cube space this is the largest absolute
    /// axis difference, which is why the third axis has to be reconstructed.
    pub fn distance(self, other: Self) -> i32 {
        let dq = (self.q - other.q).abs();
        let dr = (self.r - other.r).abs();
        let ds = (self.s() - other.s()).abs();
        dq.max(dr).max(ds)
    }

    /// World centre of the tile on the ground plane.
    ///
    /// The map lies in XZ with Y as height, so this is where a tile sits before
    /// its elevation is applied. Pointy-top layout: columns offset by half a
    /// width per row, rows 3/4 of a height apart rather than a full height,
    /// because the points interlock.
    pub fn to_world(self, height: f32) -> Vec3 {
        let q = self.q as f32;
        let r = self.r as f32;
        Vec3::new(
            HEX_WIDTH * (q + r / 2.0),
            height,
            HEX_HEIGHT_STEP * r,
        )
    }

    /// Inverse of [`to_world`], for picking. Returns the tile containing a
    /// point on the ground plane; Y is ignored.
    ///
    /// The fractional axial coordinate this produces is almost never integral,
    /// so it is rounded in cube space -- rounding q and r independently picks
    /// the wrong tile near shared edges, because it can break the
    /// `q + r + s == 0` invariant.
    pub fn from_world(point: Vec3) -> Self {
        let r = point.z / HEX_HEIGHT_STEP;
        let q = point.x / HEX_WIDTH - r / 2.0;
        Self::round(q, r)
    }

    /// Cube rounding: round all three axes, then discard whichever moved
    /// furthest and rebuild it from the other two.
    fn round(qf: f32, rf: f32) -> Self {
        let sf = -qf - rf;
        let (mut q, mut r, s) = (qf.round(), rf.round(), sf.round());
        let (dq, dr, ds) = ((q - qf).abs(), (r - rf).abs(), (s - sf).abs());
        if dq > dr && dq > ds {
            q = -r - s;
        } else if dr > ds {
            r = -q - s;
        }
        Self::new(q as i32, r as i32)
    }

}
