//! Diagnostics. Nothing here affects the game.

use bevy::prelude::*;
#[cfg(not(target_arch = "wasm32"))]
use bevy::render::view::screenshot::{Screenshot, save_to_disk};

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

        #[cfg(all(target_arch = "wasm32", target_feature = "atomics"))]
        app.add_systems(Startup, thread_probe::spawn)
            .add_systems(Update, thread_probe::report);

        #[cfg(not(target_arch = "wasm32"))]
        if std::env::var("RENTEARTH_SCREENSHOT").is_ok() {
            app.add_systems(Update, screenshot_when_settled);
        }
    }
}

/// Frames to wait before capturing. Assets stream in over the first second or
/// so, and the water needs some wave phase before it looks like anything, so a
/// shot at frame zero compares two loading screens.
#[cfg(not(target_arch = "wasm32"))]
const SCREENSHOT_FRAME: u32 = 240;

/// Save one frame and quit, so a shader change can be compared against the one
/// before it rather than from memory:
///
/// ```text
/// RENTEARTH_SCREENSHOT=/tmp/water.png cargo run --features water
/// ```
///
/// Native only -- there is no disk to write to on the web.
#[cfg(not(target_arch = "wasm32"))]
fn screenshot_when_settled(
    mut commands: Commands,
    mut frame: Local<u32>,
    mut taken: Local<bool>,
    mut exit: MessageWriter<AppExit>,
) {
    *frame += 1;

    if *taken {
        // Not the frame the shot was requested on: the capture is observed a
        // frame or two later, and exiting immediately truncates it.
        if *frame > SCREENSHOT_FRAME + 30 {
            exit.write(AppExit::Success);
        }
        return;
    }

    if *frame < SCREENSHOT_FRAME {
        return;
    }

    let Ok(path) = std::env::var("RENTEARTH_SCREENSHOT") else {
        return;
    };

    *taken = true;
    commands
        .spawn(Screenshot::primary_window())
        .observe(save_to_disk(path));
}

/// Whether the browser worker pool is running work off the main thread.
///
/// A pool whose workers never started looks exactly like one with nothing to
/// do, so counting them is not enough -- the probe compares the thread that
/// spawned the task with the one that ran it.
#[cfg(all(target_arch = "wasm32", target_feature = "atomics"))]
mod thread_probe {
    use bevy::prelude::*;
    use bevy::tasks::{Task, block_on, poll_once};

    pub struct Report {
        spawned_on: std::thread::ThreadId,
        ran_on: std::thread::ThreadId,
    }

    #[derive(Resource)]
    pub struct Probe(Option<Task<Report>>);

    pub fn spawn(mut commands: Commands) {
        let spawned_on = std::thread::current().id();

        // No busy work: the question is where this runs, not how fast.
        let task = bevy_tasker::spawn(async move {
            Report {
                spawned_on,
                ran_on: std::thread::current().id(),
            }
        });

        commands.insert_resource(Probe(Some(task)));
    }

    pub fn report(mut probe: ResMut<Probe>) {
        let Some(task) = probe.0.as_mut() else {
            return;
        };
        let Some(report) = block_on(poll_once(task)) else {
            return;
        };
        probe.0 = None;

        // Counted here, not inside the task: the first worker to reach the
        // queue runs it, before the others have finished registering.
        let workers = bevy_tasker::worker_count();

        if report.ran_on == report.spawned_on {
            warn!("worker pool is not running tasks off the main thread ({workers} registered)");
        } else {
            info!("worker pool live: {workers} workers");
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
