//! Unit entity data.

use bevy::prelude::*;

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
}

/// A unit on the map.
#[derive(Component, Clone, Copy, Debug)]
pub struct Unit {
    pub facing: Facing,
    pub action: Action,
    /// Everything that varies between two units of the same kind: which side
    /// they are on, and the offset into their own animation so that a stack of
    /// them does not march in step.
    pub seed: f32,
}

impl Unit {
    /// The two floats the shader reads: the seed, and the facing and action
    /// packed together.
    ///
    /// Packed rather than passed as two more attributes because they are only
    /// ever read together, and because a vertex channel is the cheapest place
    /// to put per-unit data that changes rarely.
    pub fn packed(self) -> [f32; 2] {
        [self.seed, self.facing as i32 as f32 + 4.0 * (self.action as i32 as f32)]
    }
}
