//! Rent Earth -- a 4X on a hex map.
//!
//! 2.5D: real 3D geometry under an orthographic camera at a fixed tilt.
//! Orthographic because a 4X needs tiles the same size wherever they are on
//! screen -- perspective would shrink distant tiles, making them harder to read
//! and to click -- while the tilt and shadows supply the relief.
//!
//! Layout is `core` / `components` / `systems`:
//!   core       -- map logic that does not depend on the engine
//!   components -- data on entities, no behaviour
//!   systems    -- behaviour, one plugin per feature
//!
//! Dependencies run one way: systems may use core, never the reverse.

use bevy::diagnostic::{FrameTimeDiagnosticsPlugin, LogDiagnosticsPlugin};
use bevy::prelude::*;

mod components;
mod core;
mod systems;

use systems::camera::CameraPlugin;
use systems::debug::DebugPlugin;
use systems::map::MapPlugin;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "Rent Earth".into(),
                ..default()
            }),
            ..default()
        }))
        // Frame time to the log, so map size changes are measured rather than
        // guessed at.
        .add_plugins((
            FrameTimeDiagnosticsPlugin::default(),
            LogDiagnosticsPlugin::default(),
        ))
        .add_plugins((MapPlugin, CameraPlugin, DebugPlugin))
        .run();
}
