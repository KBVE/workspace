//! Diagnostics. Nothing here affects the game.

use bevy::prelude::*;

use crate::game::components::camera::CameraRig;

use crate::game::components::tile::Tile;

pub struct DebugPlugin;

impl Plugin for DebugPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Update, report_visibility);

        // Temporary harness: drive the camera across the seam repeatedly and
        // log any frame that draws nothing, so the black flash can be caught
        // in the log rather than in the eye.
        if std::env::var("RENTEARTH_SEAM_PROBE").is_ok() {
            app.add_systems(Update, seam_probe)
                .add_systems(PostUpdate, catch_blank);
        }
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

/// Pan north fast enough to cross the pole seam every couple of seconds.
fn seam_probe(time: Res<Time>, mut rigs: Query<&mut CameraRig>) {
    for mut rig in &mut rigs {
        rig.focus.z -= 1400.0 * time.delta_secs();
    }
}

/// Log frames that draw no tiles at all, with the camera position that caused
/// it. Runs late in PostUpdate, after visibility has been computed.
fn catch_blank(
    // Everything drawable, not just tiles. Counting only tiles is what let the
    // seam flash hide: at the poles every tile is ocean and carries no mesh, so
    // the water plane was the only thing on screen and went unmeasured.
    tiles: Query<&ViewVisibility, With<Mesh3d>>,
    rigs: Query<&CameraRig>,
    mut frame: Local<u64>,
) {
    *frame += 1;
    let visible = tiles.iter().filter(|v| v.get()).count();
    if visible == 0 {
        let z = rigs.single().map(|r| r.focus.z).unwrap_or(f32::NAN);
        warn!("BLANK frame {} focus.z {:.1}", *frame, z);
    }
}
