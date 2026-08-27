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

mod game;
#[cfg(feature = "water")]
mod private;

use game::core::map::MapSpec;
#[cfg(feature = "water")]
use game::core::terrain::SEA_LEVEL;
use game::systems::camera::CameraPlugin;
use game::systems::debug::DebugPlugin;
use game::systems::map::MapPlugin;
use game::systems::ui::UiPlugin;

// The animated surface when the key is present and the feature is on, the flat
// fallback otherwise. Same plugin shape either way, so `main` does not branch.
#[cfg(not(feature = "water"))]
use game::systems::water::WaterPlugin;
#[cfg(feature = "water")]
use private::water::WaterPlugin;

/// Where the asset server looks.
///
/// Natively the assets live beside the crate rather than beside the binary, so
/// the path is resolved from the manifest directory and the game runs from
/// anywhere in the workspace. On the web there is no filesystem to resolve
/// against: assets are fetched over HTTP relative to the page, and the build
/// copies them next to index.html.
fn asset_path() -> String {
    #[cfg(target_arch = "wasm32")]
    return "assets".to_string();

    #[cfg(not(target_arch = "wasm32"))]
    return concat!(env!("CARGO_MANIFEST_DIR"), "/assets").to_string();
}

fn main() {
    App::new()
        .add_plugins(
            DefaultPlugins
                .set(AssetPlugin {
                    file_path: asset_path(),
                    ..default()
                })
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        title: "Rent Earth".into(),
                        ..default()
                    }),
                    ..default()
                }),
        )
        // Frame time to the log, so map size changes are measured rather than
        // guessed at.
        .add_plugins((
            FrameTimeDiagnosticsPlugin::default(),
            LogDiagnosticsPlugin::default(),
        ))
        .add_plugins((MapPlugin, CameraPlugin, DebugPlugin, UiPlugin))
        .add_plugins(water_plugin())
        .run();
}

/// Sized from the same `MapSpec` the map uses, so the plane covers the world
/// exactly rather than by a guessed margin.
fn water_plugin() -> WaterPlugin {
    let spec = MapSpec::default();
    let size = Vec2::new(spec.world_width(), spec.world_depth());

    #[cfg(feature = "water")]
    return WaterPlugin {
        size,
        sea_level: SEA_LEVEL,
    };

    #[cfg(not(feature = "water"))]
    return WaterPlugin { size };
}
