//! Cursor readout: what the mouse is over, and where the camera is.
//!
//! Doubles as the diagnostic display -- the camera focus is shown so a visual
//! glitch can be reported as a coordinate rather than as "somewhere near the
//! pole".

use bevy::prelude::*;
use bevy::text::FontSize;

use crate::game::components::camera::CameraRig;
use crate::game::components::command::{Garrison, Group, Player, Populace, Stance, Stock};
use crate::game::core::hex::Hex;
use crate::game::core::map::{MapSpec, Offset};
use crate::game::core::terrain::SEA_LEVEL;
use crate::game::systems::map::WorldTiles;

pub struct UiPlugin;

impl Plugin for UiPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_readout)
            .add_systems(Update, update_readout);
    }
}

#[derive(Component)]
struct Readout;

fn spawn_readout(mut commands: Commands) {
    commands.spawn((
        Text::new("--"),
        TextFont {
            font_size: FontSize::Px(13.0),
            ..default()
        },
        TextColor(Color::srgb(0.92, 0.94, 0.98)),
        Node {
            position_type: PositionType::Absolute,
            top: Val::Px(10.0),
            left: Val::Px(10.0),
            ..default()
        },
        // Sits over the map, so it needs its own backing to stay legible over
        // ice as well as over deep ocean.
        BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.55)),
        Readout,
    ));
}

fn update_readout(
    spec: Res<MapSpec>,
    world: Option<Res<WorldTiles>>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform, &CameraRig)>,
    sides: Query<(&Player, &Stock, &Populace, &Garrison)>,
    groups: Query<(&Group, &Stance)>,
    mut readout: Query<&mut Text, With<Readout>>,
) {
    let Ok(mut text) = readout.single_mut() else {
        return;
    };
    let Ok((camera, camera_transform, rig)) = cameras.single() else {
        return;
    };

    let focus = format!("camera  x {:.0}  z {:.0}", rig.focus.x, rig.focus.z);

    let hover = hovered_tile(&windows, camera, camera_transform)
        .map(|(point, offset)| {
            let terrain = world
                .as_ref()
                .and_then(|w| w.at(*spec, offset))
                .map(|t| format!("{t:?}"))
                .unwrap_or_else(|| "--".into());

            // Wrapped for display, because the raw pick can land in a
            // neighbouring copy of the world and a column of -3 helps nobody.
            let wrapped = offset.wrapped(*spec);
            format!(
                "tile    col {:>4}  row {:>4}   {terrain}\nworld   x {:.0}  z {:.0}",
                wrapped.col, wrapped.row, point.x, point.z,
            )
        })
        .unwrap_or_else(|| "tile    (cursor off map)".into());

    // Only the player's own books. The other three sides keep theirs, and a
    // readout that showed them would be a readout of what an opponent knows.
    let empire = sides
        .iter()
        .find(|(player, _, _, _)| player.human)
        .map(|(_, stock, populace, garrison)| {
            format!(
                "\nempire  wood {}  citizens {}  garrison {}",
                stock.wood, populace.citizens, garrison.men,
            )
        })
        .unwrap_or_default();

    // The groups the player has made, in key order, each with what it is
    // standing to do and how many are in it. `{2} P 40` is the second group,
    // on patrol, forty strong.
    let mut row: Vec<(u32, char, u32)> = groups
        .iter()
        .map(|(group, stance)| (group.number, stance.badge(), group.strength))
        .collect();
    row.sort_unstable();

    let formed = match row.is_empty() {
        true => String::new(),
        false => {
            let listed: Vec<String> = row
                .iter()
                .map(|(number, badge, strength)| format!("{{{number}}} {badge} {strength}"))
                .collect();
            format!("\ngroups  {}", listed.join("   "))
        }
    };

    **text = format!("{hover}\n{focus}{empire}{formed}");
}

/// Which tile is under the cursor.
///
/// Ray from the cursor into the scene, intersected with the sea-level plane.
/// Deliberately one flat plane rather than the terrain's own height: picking
/// against relief means a tall mountain is selected by pointing at the empty
/// sky above the tile behind it, which is exactly the fiddly behaviour that
/// makes 4X maps annoying to click.
fn hovered_tile(
    windows: &Query<&Window>,
    camera: &Camera,
    camera_transform: &GlobalTransform,
) -> Option<(Vec3, Offset)> {
    let cursor = windows.iter().find_map(|w| w.cursor_position())?;
    let ray = camera.viewport_to_world(camera_transform, cursor).ok()?;

    let distance = ray.intersect_plane(
        Vec3::new(0.0, SEA_LEVEL, 0.0),
        InfinitePlane3d::new(Vec3::Y),
    )?;
    let point = ray.get_point(distance);

    Some((point, Offset::from_hex(Hex::from_world(point))))
}
