//! Camera: pan, zoom, and the east-west wrap.

use bevy::camera::ScalingMode;
use bevy::input::mouse::{MouseMotion, MouseScrollUnit, MouseWheel};
use bevy::prelude::*;

use crate::game::components::camera::CameraRig;
use crate::game::core::map::MapSpec;

/// Tilt, as a fraction of the way from overhead to horizontal. About 40
/// degrees down: shallow enough that column sides show, steep enough that near
/// tiles do not hide the ones behind them.
///
/// Public because it is not only the camera's business: the camera never yaws,
/// so this angle is the whole of the projection anything upright has to be
/// built against. The tree billboards read it to undo the foreshortening.
pub const CAMERA_PITCH: f32 = 0.72;

/// How far back the camera sits. Only affects clipping, not apparent size --
/// the projection is orthographic -- but it has to clear the tallest terrain.
const CAMERA_DISTANCE: f32 = 1400.0;

/// World units per second at zoom 1.0, panning by keyboard.
const PAN_SPEED: f32 = 900.0;

/// Zoom change per wheel notch, as a multiplier.
///
/// Multiplicative so a notch alters the view by the same proportion wherever
/// you are. Additive zoom crawls when far out and lurches when close.
const ZOOM_PER_NOTCH: f32 = 1.12;

/// Pixels of scroll that count as one wheel notch.
///
/// A wheel reports a line per notch; a trackpad -- and plenty of mice on macOS,
/// which is what makes this matter -- reports pixels instead. Treating both as
/// the same unit sends a single swipe through the whole range at once.
///
/// If the zoom ever feels wrong on a new device, the `debug!` in `zoom_control`
/// says which unit it is sending and how much of it, which beats guessing at
/// this number twice.
const PIXELS_PER_NOTCH: f32 = 12.0;

/// Quiet time before the zoom settles onto a level.
///
/// Long enough to span the gap between notches of a turning wheel, so settling
/// happens when you stop rather than between clicks.
const ZOOM_SETTLE_DELAY: f32 = 0.10;

/// How long the settle takes.
///
/// It has real distance to cover: the levels double, so the furthest the zoom
/// can sit from one is a factor of root two, and a 41% change of scale is not
/// something to rush. Slower than this and the camera feels like it is
/// correcting you; faster and the arrival is the jump it is meant to avoid.
const ZOOM_SETTLE_TIME: f32 = 0.28;

pub struct CameraPlugin;

impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_camera).add_systems(
            Update,
            // Order matters: move, then wrap the result, then derive the
            // transform from it. Deriving before wrapping would show one frame
            // of the camera outside the world every time it crosses the seam.
            (
                pan_keyboard,
                pan_drag,
                zoom_control,
                wrap_focus,
                apply_rig,
            )
                .chain(),
        );
    }
}

pub fn spawn_camera(mut commands: Commands, spec: Res<MapSpec>) {
    // Start centred on the map rather than at the origin corner.
    let focus = Vec3::new(spec.world_width() / 2.0, 0.0, spec.world_depth() / 2.0);

    commands.spawn((
        Camera3d::default(),
        Projection::from(OrthographicProjection {
            // Against the window rather than a fixed world height, which is
            // what makes `zoom` mean "world units per logical pixel" and lets
            // the zoom levels be chosen to land on mip levels. See
            // `CameraRig::ZOOM_LEVELS`.
            scaling_mode: ScalingMode::WindowSize,
            // The camera sits far back to clear the terrain, so the far plane
            // has to reach past it or the map is clipped away entirely.
            far: CAMERA_DISTANCE * 4.0,
            ..OrthographicProjection::default_3d()
        }),
        Transform::default(),
        // Ambient is per-camera in Bevy 0.19 -- a Component that requires
        // Camera, not a global Resource. Without it the shadowed column sides
        // go black, losing terrain colour where the relief is most visible.
        AmbientLight {
            color: Color::srgb(0.75, 0.80, 0.95),
            brightness: 260.0,
            ..default()
        },
        CameraRig { focus, ..default() },
    ));

    // Sun, angled across the map rather than straight down so column sides
    // catch light unevenly and the relief is legible.
    commands.spawn((
        DirectionalLight {
            illuminance: 12_000.0,
            shadow_maps_enabled: true,
            ..default()
        },
        Transform::from_rotation(Quat::from_euler(EulerRot::YXZ, -0.7, -0.9, 0.0)),
    ));
}

fn pan_keyboard(keys: Res<ButtonInput<KeyCode>>, time: Res<Time>, mut rigs: Query<&mut CameraRig>) {
    let mut dir = Vec2::ZERO;
    if keys.any_pressed([KeyCode::KeyW, KeyCode::ArrowUp]) {
        dir.y -= 1.0;
    }
    if keys.any_pressed([KeyCode::KeyS, KeyCode::ArrowDown]) {
        dir.y += 1.0;
    }
    if keys.any_pressed([KeyCode::KeyA, KeyCode::ArrowLeft]) {
        dir.x -= 1.0;
    }
    if keys.any_pressed([KeyCode::KeyD, KeyCode::ArrowRight]) {
        dir.x += 1.0;
    }
    if dir == Vec2::ZERO {
        return;
    }
    let dir = dir.normalize();

    for mut rig in &mut rigs {
        // Scaled by zoom so a keypress moves the same distance on screen
        // whether you are zoomed in or out.
        let step = PAN_SPEED * rig.zoom * time.delta_secs();
        rig.focus.x += dir.x * step;
        rig.focus.z += dir.y * step;
    }
}

fn pan_drag(
    buttons: Res<ButtonInput<MouseButton>>,
    mut motion: MessageReader<MouseMotion>,
    mut rigs: Query<&mut CameraRig>,
) {
    if !buttons.any_pressed([MouseButton::Middle, MouseButton::Right]) {
        // Drain, or the next drag replays everything that happened while the
        // button was up and the map jumps.
        motion.clear();
        return;
    }

    let delta: Vec2 = motion.read().map(|m| m.delta).sum();
    if delta == Vec2::ZERO {
        return;
    }

    for mut rig in &mut rigs {
        // Pixels to world units, which under `ScalingMode::WindowSize` is just
        // the zoom -- and `MouseMotion` is in logical pixels, the same ones it
        // is measured in. The old form divided the projection height by a
        // hardcoded 900, so dragging tracked the pointer only on a window that
        // happened to be that tall.
        let units_per_pixel = rig.zoom;
        rig.focus.x -= delta.x * units_per_pixel;
        // Screen-vertical drag moves the focus along the ground, which is
        // foreshortened by the tilt, so undo that or dragging feels sticky.
        rig.focus.z -= delta.y * units_per_pixel / CAMERA_PITCH.sin().max(0.1);
    }
}

/// Zoom on the wheel, then settle onto a level once the wheel stops.
///
/// Continuous while you are scrolling and discrete when you are not, which is
/// the only way to have both. The zoom levels exist because the tree atlas is
/// pixel art and only samples a mip level exactly at a power of two -- but
/// stepping between them directly is a hard doubling of everything on screen,
/// and no amount of easing makes a ladder feel like a wheel. So the wheel drives
/// the zoom smoothly wherever it likes, and a moment after it stops the zoom
/// glides to the nearest level and locks there.
///
/// The cost is that the trees are slightly soft while the view is moving, which
/// is when nobody is looking closely at them, and sharp again by the time
/// anyone is.
fn zoom_control(
    time: Res<Time>,
    mut wheel: MessageReader<MouseWheel>,
    mut idle: Local<f32>,
    mut rigs: Query<&mut CameraRig>,
) {
    let mut notches = 0.0;
    for event in wheel.read() {
        debug!("scroll {:?} y {}", event.unit, event.y);
        notches += match event.unit {
            MouseScrollUnit::Line => event.y,
            MouseScrollUnit::Pixel => event.y / PIXELS_PER_NOTCH,
        };
    }

    if notches != 0.0 {
        *idle = 0.0;

        for mut rig in &mut rigs {
            // Scrolling up zooms in, which is toward a smaller scale.
            let zoom = rig.zoom * ZOOM_PER_NOTCH.powf(-notches);
            rig.zoom = zoom.clamp(CameraRig::MIN_ZOOM, CameraRig::MAX_ZOOM);
            // Nothing to settle toward while the wheel is still turning.
            rig.zoom_target = rig.zoom;
        }

        return;
    }

    *idle += time.delta_secs();
    if *idle < ZOOM_SETTLE_DELAY {
        return;
    }

    for mut rig in &mut rigs {
        if rig.zoom_target == rig.zoom {
            let target = rig.nearest_level();
            if target == rig.zoom {
                // Already on a level. Left untouched, so the camera stays out
                // of change detection and the tile wrap has nothing to do.
                continue;
            }
            rig.zoom_target = target;
            rig.zoom_from = rig.zoom;
            rig.zoom_elapsed = 0.0;
        }

        rig.zoom_elapsed += time.delta_secs();
        let t = (rig.zoom_elapsed / ZOOM_SETTLE_TIME).clamp(0.0, 1.0);

        if t >= 1.0 {
            // Landed exactly, not merely near: the levels are chosen so the
            // tree atlas samples a mip exactly, and a value that stopped a
            // fraction short would miss it every time.
            rig.zoom = rig.zoom_target;
            continue;
        }

        // Smoothstep, which is flat at both ends -- the move begins at the
        // standstill the wheel left behind and arrives at another one, so
        // neither end is a visible edge.
        let eased = t * t * (3.0 - 2.0 * t);

        // Interpolated in log space, because zoom is a scale: halfway between
        // 1 and 4 should look like 2, and arithmetically it is 2.5.
        let from = rig.zoom_from.ln();
        let to = rig.zoom_target.ln();
        rig.zoom = (from + (to - from) * eased).exp();
    }
}

/// Wrap on both axes, so panning in any direction eventually returns you to
/// where you began.
fn wrap_focus(spec: Res<MapSpec>, mut rigs: Query<&mut CameraRig>) {
    for mut rig in &mut rigs {
        rig.focus.x = spec.wrap_x(rig.focus.x);
        rig.focus.z = spec.wrap_z(rig.focus.z);
    }
}

/// Derive the transform and projection from the rig.
fn apply_rig(mut rigs: Query<(&CameraRig, &mut Transform, &mut Projection)>) {
    for (rig, mut transform, mut projection) in &mut rigs {
        // Behind and above the focus, looking back at it. Pitch is fixed --
        // a 4X wants a consistent readable angle, not a free orbit.
        let back = Vec3::new(0.0, CAMERA_PITCH.sin(), CAMERA_PITCH.cos()) * CAMERA_DISTANCE;

        *transform = Transform::from_translation(rig.focus + back).looking_at(rig.focus, Vec3::Y);

        if let Projection::Orthographic(ortho) = &mut *projection {
            ortho.scale = rig.zoom;
        }
    }
}
