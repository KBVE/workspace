//! Camera rig data.

use bevy::prelude::*;

/// The camera's ground-plane focus and zoom.
///
/// The camera transform is derived from this every frame rather than being
/// mutated directly. That keeps "where is the player looking" as a single
/// wrappable, clampable point, instead of state smeared across a translation
/// and a rotation that have to stay consistent with each other.
#[derive(Component, Clone, Copy, Debug)]
pub struct CameraRig {
    /// Point on the ground plane the camera is centred on. Y is ignored.
    pub focus: Vec3,
    /// Orthographic scale. Larger is further out.
    pub zoom: f32,
}

impl Default for CameraRig {
    fn default() -> Self {
        Self {
            focus: Vec3::ZERO,
            zoom: 1.0,
        }
    }
}

impl CameraRig {
    /// Closest and furthest zoom. Closer than the minimum and single tiles
    /// fill the screen; further than the maximum and the map is smaller than
    /// the window, which makes the wrap look broken rather than seamless.
    pub const MIN_ZOOM: f32 = 0.25;
    pub const MAX_ZOOM: f32 = 2.4;
}
