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
    /// The zoom levels, in orthographic scale.
    ///
    /// Discrete, and each one twice the last. Continuous zoom put the tree
    /// sprites at an arbitrary fraction of their texel size, which is the worst
    /// case for a mip chain: the sampler sits between two levels and blends
    /// both, so the pixel art is soft at every zoom and never crisp at any of
    /// them. Powers of two land on a level exactly.
    ///
    /// Below the first, single tiles fill the screen. Above the last, the map
    /// is smaller than the window and the wrap looks broken rather than
    /// seamless.
    pub const ZOOM_LEVELS: [f32; 4] = [0.25, 0.5, 1.0, 2.0];


    /// The level `steps` away from the current one.
    ///
    /// Works on the index rather than on the value so a notch is always one
    /// level, whatever the gaps between them happen to be.
    pub fn stepped(self, steps: i32) -> f32 {
        let current = Self::ZOOM_LEVELS
            .iter()
            .position(|z| (z - self.zoom).abs() < 1e-3)
            .unwrap_or(Self::ZOOM_LEVELS.len() / 2) as i32;

        let next = (current + steps).clamp(0, Self::ZOOM_LEVELS.len() as i32 - 1);
        Self::ZOOM_LEVELS[next as usize]
    }
}
