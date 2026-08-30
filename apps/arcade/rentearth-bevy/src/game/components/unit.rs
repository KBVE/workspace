//! Unit data.
//!
//! Not a `Component`. At the scale this is built for -- a hundred thousand and
//! upward -- a unit must not be an entity that carries a mesh, a transform and
//! a visibility computation, because every one of those costs is paid per unit
//! per frame whether or not anyone can see it. Units live in one array and are
//! drawn by `systems::units`, which builds geometry only for the ones on
//! screen. See that module for the argument in full.

use bevy::prelude::*;

use crate::game::core::map::Offset;

/// Which way a unit is bearing.
///
/// Four of them and only three drawings: the camera never yaws, so east is west
/// seen from the other side and the shader draws it mirrored. That is the same
/// economy the 16-bit sprite packs use, arrived at for the same reason.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Facing {
    South = 0,
    West = 1,
    North = 2,
    East = 3,
}

/// What a unit is doing, which is what the shader poses it as.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Action {
    Idle = 0,
    Walk = 1,
    /// Striking with whatever is in the near hand. A loop rather than a single
    /// blow: a melee is repeated strikes, and a one-shot would need a start
    /// time per unit for the shader to measure from. That field earns its keep
    /// the day a strike has to land on a particular tick, and not before.
    Attack = 2,
}

/// What a unit is carrying. One bit each, so kit combines freely -- which is
/// the point of hanging equipment off joints rather than drawing it into a
/// sprite: a helm and a shield together cost no more art than either alone.
pub mod equipment {
    pub const HELM: u32 = 1;
    pub const SPEAR: u32 = 2;
    pub const SHIELD: u32 = 4;
    /// A metal head on the spear. Its own bit rather than its own weapon: a
    /// sharpened shaft and an ironed one are the same stick to everything
    /// except the two pixels at the end of it, and a militia carrying the
    /// first alongside a line carrying the second is the distinction worth
    /// being able to draw.
    pub const SPEAR_TIP: u32 = 8;
}

/// Under nobody's orders.
pub const NO_COMPANY: u32 = u32::MAX;

/// What a quad in the unit mesh is a picture of.
pub mod quad_kind {
    /// A jointed figure.
    pub const FIGURE: u32 = 0;
    /// One banner standing for every unit on a tile.
    pub const BANNER: u32 = 1;
}

/// A unit on the map.
///
/// Position is a tile plus an offset inside it, rather than a world point,
/// because the world wraps. A world point has to be moved into whichever copy
/// of the world the camera is looking at before it can be drawn, and doing that
/// to a raw coordinate loses which tile the unit is actually on. Holding the
/// tile keeps the wrap exact and makes "who is on this hex" a lookup rather
/// than a search.
#[derive(Clone, Copy, Debug)]
pub struct Unit {
    pub tile: Offset,
    /// Where it stands within its hex, in world units on the ground plane.
    pub local: Vec2,
    pub facing: Facing,
    pub action: Action,
    pub equipment: u32,
    /// Which side it belongs to. Its own field rather than something read off
    /// the seed: the seed sets the animation phase, and taking both from it
    /// tied a unit's faction to where it happened to be in its walk cycle.
    pub team: u32,
    /// Which body of men this one belongs to, as an index rather than an
    /// `Entity`: this is stored a hundred thousand times, and four bytes
    /// against eight matters at that count. `NO_COMPANY` for a man under
    /// nobody's orders.
    pub company: u32,
    /// This unit's identity -- where it starts in its own animation, so a
    /// stack of them does not march in step.
    pub seed: f32,
}

/// Everything but the seed, packed into the one float a vertex carries.
///
/// ```text
/// bits 0-1   facing
/// bits 2-3   action
/// bits 4-7   equipment
/// bits 8-9   team
/// bit  10    quad kind: figure or banner
/// bits 11-15 company, so the shader can tell which men are picked out
/// ```
///
/// Packed rather than spread across more vertex attributes because it is only
/// ever read together, and because these are small integers: an f32 carries
/// whole numbers up to 2^24 exactly, so there is a great deal of room left
/// before this has to become something else.
pub fn pack(
    facing: Facing,
    action: Action,
    equipment: u32,
    team: u32,
    kind: u32,
    company: u32,
) -> f32 {
    let code = (facing as u32 & 3)
        | (action as u32 & 3) << 2
        | (equipment & 15) << 4
        | (team & 3) << 8
        | (kind & 1) << 10
        | (company & COMPANY_MASK) << 11;
    code as f32
}

/// How many companies the packing can tell apart.
///
/// Five bits, so thirty-two: eight standing bodies of men -- a field army and
/// a garrison a side -- and twenty-four squads split out of them. Raised from
/// four bits the day squads existed, which is exactly the day sixteen stopped
/// being enough.
///
/// The ceiling is not the packing, which has room to two to the twenty-fourth
/// and uses sixteen of it. It is the selection mask: the shader is told which
/// companies are picked out as one bit each, and a bit per company has to fit
/// in floats that carry whole numbers exactly only to twenty-four bits. Two of
/// them, sixteen bits apiece, is where thirty-two comes from.
pub const COMPANY_MASK: u32 = 31;

/// How many companies fit in one bank of the selection mask.
///
/// The mask is split over two floats because one cannot hold thirty-two bits
/// exactly. Companies below this go in the first, the rest in the second.
pub const COMPANIES_PER_BANK: u32 = 16;

impl Unit {
    pub fn packed(self) -> [f32; 2] {
        [
            self.seed,
            pack(
                self.facing,
                self.action,
                self.equipment,
                self.team,
                quad_kind::FIGURE,
                self.company,
            ),
        ]
    }
}
