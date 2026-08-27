//! Diagnostics. Nothing here affects the game.

use bevy::prelude::*;

use crate::components::tile::Tile;

pub struct DebugPlugin;

impl Plugin for DebugPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Update, report_visibility);
    }
}

/// How many tiles actually survive culling.
///
/// Bevy frustum-culls and batches on its own, but "automatic" is not the same
/// as "working here" -- a mis-sized bounding box or a shadow cascade covering
/// the whole world would quietly send everything to the GPU anyway. This counts
/// what the camera view kept, so the claim can be checked rather than assumed.
fn report_visibility(
    tiles: Query<&ViewVisibility, With<Tile>>,
    time: Res<Time>,
    mut next: Local<f32>,
) {
    let now = time.elapsed_secs();
    if now < *next {
        return;
    }
    *next = now + 2.0;

    let total = tiles.iter().len();
    let visible = tiles.iter().filter(|v| v.get()).count();
    info!(
        "tiles drawn {visible}/{total} ({:.0}% culled)",
        100.0 * (1.0 - visible as f32 / total.max(1) as f32)
    );
}
