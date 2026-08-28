//! Diagnostics. Nothing here affects the game.

use bevy::prelude::*;
#[cfg(not(target_arch = "wasm32"))]
use bevy::asset::RenderAssetUsages;
#[cfg(not(target_arch = "wasm32"))]
use bevy::camera::{ImageRenderTarget, RenderTarget};
#[cfg(not(target_arch = "wasm32"))]
use bevy::render::render_resource::{
    Extent3d, TextureDimension, TextureFormat, TextureUsages,
};
#[cfg(not(target_arch = "wasm32"))]
use bevy::render::view::screenshot::{Screenshot, save_to_disk};

use crate::game::components::camera::CameraRig;
#[cfg(not(target_arch = "wasm32"))]
use crate::game::systems::camera::spawn_camera;

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
            app.add_systems(Startup, render_to_image.after(spawn_camera))
                .add_systems(Update, screenshot_when_settled);
        }
    }
}

/// Frames to wait before capturing. Assets stream in over the first second or
/// so, and the water needs some wave phase before it looks like anything, so a
/// shot at frame zero compares two loading screens.
#[cfg(not(target_arch = "wasm32"))]
const SCREENSHOT_FRAME: u32 = 240;

/// Size of a captured frame. Fixed rather than taken from the window, so two
/// shots can be compared pixel for pixel whatever the window happened to be.
///
/// Bevy's default window, and deliberately so. The projection scales against
/// the target's logical size, so a capture of a different size frames a
/// different amount of world at the same zoom -- and a screenshot that is not a
/// picture of what is on screen is worse than no screenshot. Matching the
/// window here is what lets `RENTEARTH_CAMERA` take the zoom you would actually
/// be looking at.
#[cfg(not(target_arch = "wasm32"))]
const CAPTURE_SIZE: (u32, u32) = (1280, 720);

/// Where a captured frame is rendered.
#[cfg(not(target_arch = "wasm32"))]
#[derive(Resource)]
struct CaptureTarget(Handle<Image>);

/// An image to capture in place of the window's own.
///
/// Anything that draws into its own target and wants to be photographed
/// inserts this. It exists so the harness does not have to name what that
/// thing is -- the museum is encrypted out of a keyless build, and a debug
/// module that referred to it by path would not compile without the key.
#[derive(Resource)]
pub struct CaptureOverride(pub Handle<Image>);

/// Point the camera at an offscreen image instead of at the window.
///
/// Capturing the window reads the window's own surface, and macOS hands back a
/// surface full of zeroes whenever that window is not in front -- occluded,
/// on another space, or behind a sleeping display. The failure is silent and
/// total: the scene, the UI text, everything comes back pure black, which looks
/// exactly like a rendering bug and wasted a while being investigated as one.
/// An offscreen target does not care what the window is doing.
#[cfg(not(target_arch = "wasm32"))]
fn render_to_image(
    mut commands: Commands,
    mut images: ResMut<Assets<Image>>,
    // The map's camera, not every camera. The museum has one of its own
    // pointed at its own image, and pointing that at the capture instead loses
    // both pictures.
    cameras: Query<Entity, With<CameraRig>>,
) {
    let (width, height) = CAPTURE_SIZE;

    let mut image = Image::new_fill(
        Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        &[0, 0, 0, 255],
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::RENDER_WORLD,
    );
    // RENDER_ATTACHMENT to be drawn into, COPY_SRC to be read back out.
    image.texture_descriptor.usage =
        TextureUsages::TEXTURE_BINDING | TextureUsages::COPY_SRC | TextureUsages::RENDER_ATTACHMENT;

    let handle = images.add(image);

    // A component in its own right in Bevy 0.19, not a field on `Camera`.
    for camera in &cameras {
        commands
            .entity(camera)
            .insert(RenderTarget::Image(ImageRenderTarget {
                handle: handle.clone(),
                // 1, and it has to be: anything else and the capture comes back
                // empty. Framing is matched by sizing the image above instead.
                scale_factor: 1.0,
            }));
    }

    commands.insert_resource(CaptureTarget(handle));
}

/// Save one frame and quit, so a change can be compared against the one before
/// it rather than from memory:
///
/// ```text
/// RENTEARTH_SCREENSHOT=/tmp/shot.png moon run rentearth-bevy:run
/// ```
///
/// `RENTEARTH_CAMERA=x,z,zoom` pins where the shot is taken from. Without it
/// the comparison is worthless: the window opens under the pointer and macOS
/// delivers the trackpad's momentum scroll to it, so `zoom_scroll` runs before
/// anyone has touched anything and every capture lands at a different place and
/// magnification. Two shots of the same build came out looking like two
/// different changes.
///
/// Native only -- there is no disk to write to on the web.
#[cfg(not(target_arch = "wasm32"))]
fn screenshot_when_settled(
    mut commands: Commands,
    target: Option<Res<CaptureTarget>>,
    mut frame: Local<u32>,
    mut taken: Local<bool>,
    mut rigs: Query<&mut CameraRig>,
    override_target: Option<Res<CaptureOverride>>,
    mut exit: MessageWriter<AppExit>,
) {
    *frame += 1;

    // Every frame, not once at startup: the stray scroll arrives several frames
    // in, so a single write at startup is overwritten before the shot is taken.
    if let Some((x, z, zoom)) = pinned_camera() {
        for mut rig in &mut rigs {
            rig.focus.x = x;
            rig.focus.z = z;
            rig.zoom = zoom;
        }
    }

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

    let Some(target) = target else {
        return;
    };

    // Whatever asked to be captured instead, if anything did.
    let image = match &override_target {
        Some(other) => other.0.clone(),
        None => target.0.clone(),
    };

    *taken = true;
    commands
        .spawn(Screenshot::image(image))
        .observe(save_to_disk(path));
}

/// `RENTEARTH_CAMERA=x,z,zoom`, if it parses. A malformed value is ignored
/// rather than fatal -- this is a debugging aid, and refusing to start because
/// a comma is missing helps nobody.
#[cfg(not(target_arch = "wasm32"))]
fn pinned_camera() -> Option<(f32, f32, f32)> {
    let raw = std::env::var("RENTEARTH_CAMERA").ok()?;
    let mut parts = raw.split(',').map(|p| p.trim().parse::<f32>());
    match (parts.next(), parts.next(), parts.next()) {
        (Some(Ok(x)), Some(Ok(z)), Some(Ok(zoom))) => Some((x, z, zoom)),
        _ => {
            warn!("RENTEARTH_CAMERA should be `x,z,zoom`; ignoring {raw:?}");
            None
        }
    }
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
