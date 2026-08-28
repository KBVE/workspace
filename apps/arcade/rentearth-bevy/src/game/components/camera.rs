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
    /// World units per logical screen pixel. Larger is further out.
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
    /// Closest and furthest zoom, in world units per logical screen pixel.
    ///
    /// Closer than the minimum and single tiles fill the screen; further than
    /// the maximum and the map is smaller than the window, which makes the wrap
    /// look broken rather than seamless.
    ///
    /// Continuous between them, deliberately. An earlier version snapped to
    /// powers of two so the tree atlas would sample a mip level exactly rather
    /// than blending two, which is the difference between crisp pixel art and
    /// slightly soft pixel art when the camera is still. It was not worth what
    /// it cost: a ladder does not feel like a wheel, and every attempt to make
    /// it feel like one -- easing the step, then curving the ease, then tuning
    /// how long to wait before starting -- added machinery to a control that
    /// should not have any. The mip chain is what stopped the trees crawling,
    /// and it does that at any zoom. This only ever bought sharpness on top.
    pub const MIN_ZOOM: f32 = 0.25;
    pub const MAX_ZOOM: f32 = 4.0;
}
