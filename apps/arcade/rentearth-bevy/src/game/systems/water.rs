//! Fallback water: a flat translucent plane at sea level.
//!
//! Deliberately plain. The animated version lives in `private/water` behind the
//! `water` feature, and this is what a clone without the git-crypt key gets
//! instead -- the sea is there, the right colour, at the right height, just not
//! moving. Losing the shader should cost polish, not correctness.

use bevy::prelude::*;
use bevy::transform::TransformSystems;

use crate::game::components::camera::CameraRig;

use crate::game::core::terrain::SEA_LEVEL;

/// Marks the fallback surface, so it can be tracked to the camera.
#[derive(Component)]
struct WaterSurface;

pub struct WaterPlugin {
    pub size: Vec2,
}

impl Plugin for WaterPlugin {
    fn build(&self, app: &mut App) {
        let size = self.size;
        app.add_systems(
            Startup,
            move |mut commands: Commands,
                  mut meshes: ResMut<Assets<Mesh>>,
                  mut materials: ResMut<Assets<StandardMaterial>>| {
                // Two triangles are enough: nothing displaces this one.
                let mesh = meshes.add(Plane3d::default().mesh().size(size.x, size.y));
                let material = materials.add(StandardMaterial {
                    base_color: Color::srgba(0.09, 0.24, 0.44, 0.92),
                    perceptual_roughness: 0.25,
                    alpha_mode: AlphaMode::Blend,
                    ..default()
                });
                commands.spawn((
                    Mesh3d(mesh),
                    MeshMaterial3d(material),
                    Transform::from_xyz(size.x / 2.0, SEA_LEVEL, size.y / 2.0),
                    WaterSurface,
                ));
            },
        )
        // In PostUpdate, not Update: the camera wraps its focus during
        // Update, and unordered against that this could place the water at
        // the pre-wrap focus while the camera teleports a world away. At
        // the poles that is a black frame, because the Arctic is all ocean
        // and ocean tiles carry no mesh -- the plane is the only thing
        // there is to draw.
        .add_systems(
            PostUpdate,
            follow_camera.before(TransformSystems::Propagate),
        );
    }
}

/// Keep the water centred on the camera.
///
/// The map wraps by moving tiles into whichever copy of the world is nearest
/// the camera, but a single plane has no copies to move between -- panning far
/// enough simply ran off the edge of it, and the sea stopped following.
///
/// Water is homogeneous, so rather than wrap it, it just tracks the camera: a
/// plane always centred on the focus is indistinguishable from an infinite
/// ocean. Wave phase and the depth lookup are both keyed to world position, so
/// sliding the mesh moves no waves and shifts no coastline.
fn follow_camera(
    camera: Query<&CameraRig, Changed<CameraRig>>,
    mut surfaces: Query<&mut Transform, With<WaterSurface>>,
) {
    let Ok(rig) = camera.single() else {
        return;
    };
    // Tracked exactly, with no snapping: this surface is flat, so there is no
    // displacement to slide through and nothing to swim.
    for mut transform in &mut surfaces {
        transform.translation.x = rig.focus.x;
        transform.translation.z = rig.focus.z;
    }
}
