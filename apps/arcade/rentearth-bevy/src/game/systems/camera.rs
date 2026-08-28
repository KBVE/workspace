//! Camera: pan, zoom, and the east-west wrap.

use bevy::camera::ScalingMode;
use bevy::input::mouse::{MouseMotion, MouseWheel};
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

/// Scroll accumulated before the zoom moves a level.
///
/// The levels are discrete now, so a notch cannot be a fraction of one. A
/// trackpad emits a stream of small deltas where a wheel emits ones, and
/// without a threshold the former crosses the whole range in a flick.
const ZOOM_THRESHOLD: f32 = 1.0;

pub struct CameraPlugin;

impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_camera).add_systems(
            Update,
            // Order matters: move, then wrap the result, then derive the
            // transform from it. Deriving before wrapping would show one frame
            // of the camera outside the world every time it crosses the seam.
            (pan_keyboard, pan_drag, zoom_scroll, wrap_focus, apply_rig).chain(),
        );
    }
}

pub fn spawn_camera(mut commands: Commands, spec: Res<MapSpec>) {
    // Start centred on the map rather than at the origin corner.
    let focus = Vec3::new(spec.world_width() / 2.0, 0.0, spec.world_depth() / 2.0);

    commands.spawn((
        Camera3d::default(),
        Projection::from(OrthographicProjection {
            scaling_mode: ScalingMode::FixedVertical {
                viewport_height: 900.0,
            },
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
    mut rigs: Query<(&mut CameraRig, &Projection)>,
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

    for (mut rig, projection) in &mut rigs {
        // Pixels to world units. Orthographic height maps to the viewport, so
        // this only depends on zoom, not on distance.
        let Projection::Orthographic(ortho) = projection else {
            continue;
        };
        let units_per_pixel = ortho.area.height() / 900.0;
        rig.focus.x -= delta.x * units_per_pixel;
        // Screen-vertical drag moves the focus along the ground, which is
        // foreshortened by the tilt, so undo that or dragging feels sticky.
        rig.focus.z -= delta.y * units_per_pixel / CAMERA_PITCH.sin().max(0.1);
    }
}

fn zoom_scroll(
    mut wheel: MessageReader<MouseWheel>,
    mut pending: Local<f32>,
    mut rigs: Query<&mut CameraRig>,
) {
    *pending += wheel.read().map(|w| w.y).sum::<f32>();

    let steps = (*pending / ZOOM_THRESHOLD).trunc();
    if steps == 0.0 {
        return;
    }
    // Keep the remainder, or a slow scroll never accumulates enough to move.
    *pending -= steps * ZOOM_THRESHOLD;

    for mut rig in &mut rigs {
        // Scrolling up zooms in, which is toward a smaller scale.
        rig.zoom = rig.stepped(-steps as i32);
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
