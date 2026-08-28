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

pub struct CameraPlugin;

impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_camera).add_systems(
            Update,
            // Order matters: move, then wrap the result, then derive the
            // transform from it. Deriving before wrapping would show one frame
            // of the camera outside the world every time it crosses the seam.
            (pan_keyboard, pan_drag, zoom_control, wrap_focus, apply_rig).chain(),
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
            // what makes `zoom` mean "world units per logical pixel", which is
            // the unit `MouseMotion` reports drags in and the unit the tree
            // atlas's texel density is measured against.
            scaling_mode: ScalingMode::WindowSize,
            // The camera sits far back to clear the terrain, so the far plane
            // has to reach past it or the map is clipped away entirely.
            far: CAMERA_DISTANCE * 4.0,
            // Behind the camera, which an orthographic projection allows and
            // this one needs. The default is zero, and the ground nearest the
            // viewer has negative view depth once the view is wide enough --
            // the camera is a fixed distance back but the visible ground grows
            // with the zoom, so past a point the bottom of the map is in front
            // of the camera's own position and was being clipped away. It read
            // as the water plane ending in a line, which is a much more
            // plausible bug than the one it was.
            near: -CAMERA_DISTANCE * 4.0,
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

/// Zoom on the wheel.
fn zoom_control(mut wheel: MessageReader<MouseWheel>, mut rigs: Query<&mut CameraRig>) {
    let mut notches = 0.0;
    for event in wheel.read() {
        debug!("scroll {:?} y {}", event.unit, event.y);
        notches += match event.unit {
            MouseScrollUnit::Line => event.y,
            MouseScrollUnit::Pixel => event.y / PIXELS_PER_NOTCH,
        };
    }

    if notches == 0.0 {
        return;
    }

    for mut rig in &mut rigs {
        // Scrolling up zooms in, which is toward a smaller scale.
        let zoom = rig.zoom * ZOOM_PER_NOTCH.powf(-notches);
        rig.zoom = zoom.clamp(CameraRig::MIN_ZOOM, CameraRig::MAX_ZOOM);
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
