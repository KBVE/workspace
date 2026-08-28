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

        #[cfg(all(target_arch = "wasm32", target_feature = "atomics"))]
        app.add_systems(Startup, thread_probe::spawn)
            .add_systems(Update, thread_probe::report);
    }
}

/// Whether the browser worker pool is running work off the main thread.
///
/// Worth one log line because the failure is invisible: a pool whose workers
/// never started looks exactly like a pool with nothing to do, and the symptom
/// downstream is a task that quietly never resolves. Counting workers is not
/// enough either -- a worker can register and still be executing on the thread
/// that spawned the work if the shared memory was not actually shared. So the
/// probe compares the two thread ids and says which case it is.
#[cfg(all(target_arch = "wasm32", target_feature = "atomics"))]
mod thread_probe {
    use bevy::prelude::*;
    use bevy::tasks::{Task, block_on, poll_once};

    pub struct Report {
        spawned_on: std::thread::ThreadId,
        ran_on: std::thread::ThreadId,
        workers: usize,
    }

    #[derive(Resource)]
    pub struct Probe(Option<Task<Report>>);

    pub fn spawn(mut commands: Commands) {
        let spawned_on = std::thread::current().id();

        // No busy work on purpose. The question is where this runs, not how
        // fast, and burning a worker for a visible interval on every player's
        // machine would be a cost paid to learn nothing extra.
        let task = bevy_tasker::spawn(async move {
            Report {
                spawned_on,
                ran_on: std::thread::current().id(),
                workers: bevy_tasker::worker_count(),
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

        if report.ran_on == report.spawned_on {
            warn!(
                "worker pool is not running tasks off the main thread ({} workers registered)",
                report.workers
            );
        } else {
            info!("worker pool live: {} workers", report.workers);
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
