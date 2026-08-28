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
    /// Orthographic scale, as drawn this frame. Larger is further out.
    ///
    /// Eased toward `zoom_target` rather than set to it. While it is moving it
    /// sits between two zoom levels and the tree atlas blends two mips, which
    /// does not matter: nobody reads pixel art during a zoom, and it lands back
    /// on a level the moment it settles.
    pub zoom: f32,
    /// The zoom level being eased toward. Always one of [`Self::ZOOM_LEVELS`].
    pub zoom_target: f32,
}

impl Default for CameraRig {
    fn default() -> Self {
        Self {
            focus: Vec3::ZERO,
            // One of the levels, or the first scroll would snap rather than
            // step.
            zoom: 1.0,
            zoom_target: 1.0,
        }
    }
}

impl CameraRig {
    /// World units per logical screen pixel, at each zoom level.
    ///
    /// Chosen so the tree atlas lands on a mip level exactly rather than
    /// between two. A tree's apparent height on screen is `TREE_HEIGHT` world
    /// units -- the quad is built `1/cos(pitch)` taller than that and the
    /// camera's tilt takes the difference straight back out -- so it covers
    /// `TREE_HEIGHT / zoom` logical pixels, and the atlas's 144-texel cell is
    /// drawn at `144 * zoom / (TREE_HEIGHT * scale_factor)` texels per physical
    /// pixel. At `TREE_HEIGHT = 36` on a 2x display that is `2 * zoom`, so
    /// these four levels give 1, 2, 4 and 8 -- one per level of the mip chain,
    /// which is why there are four of each.
    ///
    /// Powers of two are the whole point. At any other ratio the sampler sits
    /// between two mip levels and blends both, and the pixel art is soft at
    /// every zoom and crisp at none of them. An earlier version of this used
    /// four arbitrary levels and bought nothing: the ratio was a constant 3,
    /// so every level blended 58/42 rather than landing anywhere.
    ///
    /// The cost is that zoom is now tied to the window: a bigger window shows
    /// more map rather than showing it larger. That is the usual bargain for
    /// pixel art, and it is what makes the alignment hold at all -- the ratio
    /// depends on the window's pixel height, so nothing that ignores the window
    /// can be aligned to it. A fractional display scale (1.5x, say) would put
    /// the ratio back between levels; 1x and 2x both work.
    pub const ZOOM_LEVELS: [f32; 4] = [0.5, 1.0, 2.0, 4.0];

    /// The level `steps` away from the current one.
    ///
    /// Works on the index rather than on the value so a notch is always one
    /// level, whatever the gaps between them happen to be.
    pub fn stepped(self, steps: i32) -> f32 {
        // From the target, not from the current zoom. Scrolling again mid-ease
        // should step from where the camera is going rather than from wherever
        // the animation happens to have reached.
        let current = Self::ZOOM_LEVELS
            .iter()
            .position(|z| (z - self.zoom_target).abs() < 1e-3)
            .unwrap_or(Self::ZOOM_LEVELS.len() / 2) as i32;

        let next = (current + steps).clamp(0, Self::ZOOM_LEVELS.len() as i32 - 1);
        Self::ZOOM_LEVELS[next as usize]
    }
}
