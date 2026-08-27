//! Fallback water: a flat translucent plane at sea level.
//!
//! Deliberately plain. The animated version lives in `private/water` behind the
//! `water` feature, and this is what a clone without the git-crypt key gets
//! instead -- the sea is there, the right colour, at the right height, just not
//! moving. Losing the shader should cost polish, not correctness.

use bevy::prelude::*;

use crate::game::core::terrain::SEA_LEVEL;

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
                ));
            },
        );
    }
}
