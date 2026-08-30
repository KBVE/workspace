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

#[cfg(target_arch = "wasm32")]
use bevy::asset::AssetMetaCheck;
use bevy::diagnostic::{FrameTimeDiagnosticsPlugin, LogDiagnosticsPlugin};
use bevy::prelude::*;

mod game;
#[cfg(any(feature = "trees", feature = "units", feature = "water"))]
mod private;

use game::core::map::MapSpec;
#[cfg(feature = "water")]
use game::core::terrain::SEA_LEVEL;
use game::systems::borders::BordersPlugin;
use game::systems::camera::CameraPlugin;
use game::systems::debug::DebugPlugin;
use game::systems::map::MapPlugin;
#[cfg(feature = "trees")]
use private::trees::TreePlugin;
#[cfg(feature = "units")]
use private::units::UnitPlugin;
#[cfg(feature = "units")]
use private::units::march::MarchPlugin;
#[cfg(feature = "units")]
use private::units::realm::RealmPlugin;
#[cfg(feature = "units")]
use private::units::select::SelectPlugin;
#[cfg(feature = "units")]
use private::units::museum::MuseumPlugin;
use game::systems::ui::UiPlugin;

// The animated surface when the key is present and the feature is on, the flat
// fallback otherwise. Same plugin shape either way, so `main` does not branch.
#[cfg(not(feature = "water"))]
use game::systems::water::WaterPlugin;
#[cfg(feature = "water")]
use private::water::WaterPlugin;

/// Everything that is encrypted, when the key is present and the features are
/// on, and nothing at all otherwise.
///
/// One plugin rather than a cfg at the call site, because a tuple of plugins is
/// `Plugins` and not `Plugin`, and the arms would have to be different types
/// for `main` to name any of them.
struct PrivatePlugins;

impl Plugin for PrivatePlugins {
    fn build(&self, app: &mut App) {
        #[cfg(feature = "trees")]
        app.add_plugins(TreePlugin);
        #[cfg(feature = "units")]
        app.add_plugins((UnitPlugin, MuseumPlugin, MarchPlugin, RealmPlugin, SelectPlugin));
        let _ = app;
    }
}

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

/// The wasm-bindgen glue a pool worker has to instantiate.
///
/// It is named rather than discovered because the build ships two bundles from
/// one directory -- WebGPU and WebGL2 -- and a worker must join the binary the
/// main thread is already running, not the other one. The feature that decides
/// the backend decides this too, so the two cannot drift apart.
#[cfg(all(target_arch = "wasm32", target_feature = "atomics"))]
const BUNDLE: &str = if cfg!(feature = "webgpu") {
    "./rentearth-webgpu.js"
} else {
    "./rentearth-webgl2.js"
};

fn main() {
    // Every pool thread instantiates this same module, and wasm-bindgen runs
    // the start section -- this function -- on each one. Only the page's main
    // thread builds an App; a worker returns here and its script then parks it
    // on the shared queue.
    #[cfg(all(target_arch = "wasm32", target_feature = "atomics"))]
    {
        if bevy_tasker::is_worker() {
            return;
        }

        // Before the app, because `App::run` never returns on the web:
        // wasm-bindgen unwinds it by throwing, so anything after it is
        // unreachable.
        bevy_tasker::start_workers("./worker.js", BUNDLE, None);
    }

    App::new()
        .add_plugins(
            DefaultPlugins
                .set(AssetPlugin {
                    file_path: asset_path(),
                    // The asset server asks for `<asset>.meta` before every
                    // load and falls back to defaults when it 404s. This
                    // project ships none, so on the web that is one failed
                    // round trip per asset and a console full of red that
                    // hides real errors. Natively a miss is a stat, so the
                    // check stays on there.
                    #[cfg(target_arch = "wasm32")]
                    meta_check: AssetMetaCheck::Never,
                    ..default()
                })
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        title: "Rent Earth".into(),
                        // A capture reads the window's own surface, so a window
                        // that is not in front reads back as pure black -- the
                        // UI text along with the scene, which is the tell that
                        // it is the capture and not the frame. Kept to the
                        // screenshot run so an ordinary session does not get a
                        // window it cannot put behind anything.
                        #[cfg(not(target_arch = "wasm32"))]
                        window_level: if std::env::var("RENTEARTH_SCREENSHOT").is_ok() {
                            bevy::window::WindowLevel::AlwaysOnTop
                        } else {
                            bevy::window::WindowLevel::Normal
                        },
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
        .add_plugins((
            MapPlugin,
            CameraPlugin,
            DebugPlugin,
            UiPlugin,
            BordersPlugin,
        ))
        // Encrypted, and so optional. Without the git-crypt key the map, the
        // camera and the terrain still build and run -- a world with no trees
        // on it and nobody standing about.
        .add_plugins(PrivatePlugins)
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
