/**
 * GENERATED FILE - DO NOT EDIT.
 *
 * Source: shared/state.json + shared/events.json
 * Regenerate: npm run gen (from vite/). Runs automatically on dev and build.
 *
 * The bridge contract. Both sides are generated from the same file, so a wire
 * name cannot drift between Godot and React.
 *
 * Keep payloads coarse: gameplay runs at 60/120fps inside WASM, but these cross
 * the JS boundary only on real changes, or a few times a second for snapshots.
 */

/** Godot -> React. */
export interface GodotToJs {
  // The bridge is live and draining anything React queued before wasm boot. Emitted
  // directly by JsBridge itself rather than the ECS bus, so it has no bus name, (this
  // is like a race condition type situation resolver).
  'godot:ready': Record<string, never>;
  // The scene tree finished swapping scenes; `scene` is the res:// path of the new
  // scene.
  'scene:changed': { scene: string };
  // A scene is streaming in on the loader pool. `progress` is 0..1 and `status` is one
  // of `start`, `progress`, `ready`, `failed`.
  'scene:loading': { scene: string; progress: number; status: string };
  // Coarse HUD snapshot that emit at 5 / 10 / 15 / 20Hz, not per frame!!! Every emit
  // crosses the JS boundary and serialises to JSON or packed ints.
  'player:state': { health: number; max_health: number };
  // Coarse run state; both fields are packed ints from shared/state.json : Json ->
  // `run` is a RunState, `flags` is a PlayerFlags bitfield; decode with the generated
  // helpers, never with constants.
  'game:state': { run: number; flags: number; world: number };
  // Score changed, probably hook this into a clue based system later on.
  'game:score': { score: number };
  // A train level started, was won, or was lost. `level` is the level name (Aisle,
  // Orbit, Side), `index` its 0-based place in the running order and `total` how many
  // levels the run holds.
  'level:changed': { level: string; index: number; total: number; outcome: string };
  // The run or murder train ended. Shape is currently game defined, so give it real
  // fields once the game has them.
  'game:run_over': Record<string, unknown>;
  // In-world time of day, emitted when the minute changes rather than per frame.
  'world:clock': { hour: number; minute: number };
  // Where the player is standing: the carriage they are in and the room that carriage
  // stands in for.
  'viewer:state': { carriage: number; location: string };
  // A door was used, and what happened. Emitted on the press rather than per frame.
  'door:state': { open: boolean; locked: boolean; distance: number };
  // How far the world's render resolution is currently divided, and the antialiasing
  // that goes with it.
  'render:budget': { shrink: number; detail: string };
  // A posted notice on a carriage wall was read; `id` is a shared/data/notices id.
  'notice:read': { id: string };
  // One fact the run has produced: a conversation, an item used, a room entered.
  'journal:entry': { id: string; kind: number; actor: string; target: string; place: string; at: number };
}

/** React -> Godot. */
export interface JsToGodot {
  // React or devtools asked to pause or resume. It is ignored outside RunState.PLAYING,
  // with the paused menu acting like a soft lock.
  'ui:pause': { paused: boolean };
  // React , jest or playwright requested to restart the current run or murder or clue
  // scene.
  'ui:restart': Record<string, never>;
  // React asked to leave the game scene for the main menu, think of it as a quick
  // escape hatch.
  'ui:main_menu': Record<string, never>;
  // React asked for a scene to be streamed in. Loading happens on the loader pool and
  // the swap only runs once the resource is ready, so the main thread never waits on
  // it.
  'ui:load_scene': { scene: string };
}

/** Wire name -> ordered payload fields, matching the positional args Godot sends. */
export const WIRE_FIELDS: Record<string, readonly string[]> = {
  'godot:ready': [],
  'scene:changed': ['scene'],
  'scene:loading': ['scene', 'progress', 'status'],
  'player:state': ['health', 'max_health'],
  'game:state': ['run', 'flags', 'world'],
  'game:score': ['score'],
  'level:changed': ['level', 'index', 'total', 'outcome'],
  'world:clock': ['hour', 'minute'],
  'viewer:state': ['carriage', 'location'],
  'door:state': ['open', 'locked', 'distance'],
  'render:budget': ['shrink', 'detail'],
  'notice:read': ['id'],
  'journal:entry': ['id', 'kind', 'actor', 'target', 'place', 'at'],
};

export type GodotEvent = keyof GodotToJs;
export type GodotCommand = keyof JsToGodot;