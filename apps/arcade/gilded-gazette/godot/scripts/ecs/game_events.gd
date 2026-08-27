class_name GameEvents

## GENERATED FILE - DO NOT EDIT.
##
## Source: shared/state.json + shared/events.json
## Regenerate: npm run gen (from vite/). Runs automatically on dev and build.
##
## The event vocabulary shared by the ECS world, the Maaack menus, and the
## React shell. Gameplay emits these names and nothing else - the mapping onto
## JS wire names lives in [constant OUTBOUND_WIRE], so producers stay unaware
## that a browser exists.

# ==============================================================================
# Outbound - Godot to React
# ==============================================================================

## The scene tree finished swapping scenes; `scene` is the res:// path of the new scene.
##
## Deliberately not driven by SceneLoader.scene_loaded, because it fires before the swap
## and also for background loads that never swap at all. Currently, our gameBridge
## watches the tree's current scene instead, so this reports what actually happened and
## catches changes made without SceneLoader.
##
## Payload: {"scene": string}. Reaches JS as "scene:changed".
const SCENE_CHANGED := &"scene_changed"

## A scene is streaming in on the loader pool. `progress` is 0..1 and `status` is one of
## `start`, `progress`, `ready`, `failed`.
##
## The swap itself still reports through scene:changed; this reports the wait before it,
## which is the window React fills with the newspaper instead of a black canvas.
##
## Payload: {"scene": string, "progress": number, "status": string}. Reaches JS as
## "scene:loading".
const SCENE_LOADING := &"scene_loading"

## Coarse HUD snapshot that emit at 5 / 10 / 15 / 20Hz, not per frame!!! Every emit
## crosses the JS boundary and serialises to JSON or packed ints.
##
## Payload: {"health": number, "max_health": number}. Reaches JS as "player:state".
const PLAYER_STATE := &"player_state"

## Coarse run state; both fields are packed ints from shared/state.json : Json -> `run`
## is a RunState, `flags` is a PlayerFlags bitfield; decode with the generated helpers,
## never with constants.
##
## Payload: {"run": number, "flags": number, "world": number}. Reaches JS as
## "game:state".
const STATE_CHANGED := &"state_changed"

## Score changed, probably hook this into a clue based system later on.
##
## Payload: {"score": number}. Reaches JS as "game:score".
const SCORE_CHANGED := &"score_changed"

## A train level started, was won, or was lost. `level` is the level name (Aisle, Orbit,
## Side), `index` its 0-based place in the running order and `total` how many levels the
## run holds.
##
## `outcome` is one of `start`, `won`, `lost` -> the loop never leaves the train scene,
## so scene:changed cannot report this; a level swap is a camera and rule swap inside
## one carriage.
##
## Payload: {"level": string, "index": number, "total": number, "outcome": string}.
## Reaches JS as "level:changed".
const LEVEL_CHANGED := &"level_changed"

## The run or murder train ended. Shape is currently game defined, so give it real
## fields once the game has them.
##
## Payload: game-defined. Reaches JS as "game:run_over".
const RUN_OVER := &"run_over"

## In-world time of day, emitted when the minute changes rather than per frame.
##
## The train runs a day/night cycle, and the Gazette prints by the clock: an article
## whose frontmatter carries `after`/`before` only reaches the front page inside that
## window. Wall-clock time is irrelevant; this is the world's.
##
## Payload: {"hour": number, "minute": number}. Reaches JS as "world:clock".
const WORLD_CLOCK := &"world_clock"

## Where the player is standing: the carriage they are in and the room that carriage
## stands in for.
##
## Emitted only when one of them changes, never per frame. This replaces the in-engine
## debug label, so the information lives in the React panel with everything else.
##
## Payload: {"carriage": number, "location": string}. Reaches JS as "viewer:state".
const VIEWER_STATE := &"viewer_state"

## A door was used, and what happened. Emitted on the press rather than per frame.
##
## A locked door reports too, with open unchanged: silence would be indistinguishable
## from the player failing to reach it, and the panel is the only place to tell the
## difference while the run has no dialogue.
##
## Payload: {"open": boolean, "locked": boolean, "distance": number}. Reaches JS as
## "door:state".
const DOOR_STATE := &"door_state"

## How far the world's render resolution is currently divided, and the antialiasing that
## goes with it.
##
## The engine picks this from measured frame time, not from a device name, so it changes
## during a run on hardware that cannot hold the frame rate. Emitted only when it
## changes. Without it a soft-looking phone gives no way to tell whether the scaler
## decided that or something else went wrong.
##
## Payload: {"shrink": number, "detail": string}. Reaches JS as "render:budget".
const RENDER_BUDGET := &"render_budget"

## A posted notice on a carriage wall was read; `id` is a shared/data/notices id.
##
## The poster in the world is a quad the player points at; the sheet React opens over it
## is the notice itself. Only the id crosses the boundary, because both runtimes already
## hold the compiled notice and sending the prose would be sending what the other side
## is reading from.
##
## Payload: {"id": string}. Reaches JS as "notice:read".
const NOTICE_READ := &"notice_read"

## One fact the run has produced: a conversation, an item used, a room entered.
##
## `id` is a ULID, so entries sort by creation without comparing any other field. `kind`
## is a JournalKind. `actor` and `target` are content ids (`beaumont`, `telegram`) or
## empty. `at` is in-world minutes past midnight, which is what the player reasons
## about; the ULID carries the real ordering.
##
## Payload: {"id": string, "kind": number, "actor": string, "target": string, "place":
## string, "at": number}. Reaches JS as "journal:entry".
const JOURNAL_ENTRY := &"journal_entry"

# ==============================================================================
# Inbound - React to Godot
# ==============================================================================

## React or devtools asked to pause or resume. It is ignored outside RunState.PLAYING,
## with the paused menu acting like a soft lock.
##
## Payload: {"paused": boolean}. Reaches JS as "ui:pause".
const UI_PAUSE := &"ui_pause"

## React , jest or playwright requested to restart the current run or murder or clue
## scene.
##
## Payload: none. Reaches JS as "ui:restart".
const UI_RESTART := &"ui_restart"

## React asked to leave the game scene for the main menu, think of it as a quick escape
## hatch.
##
## Payload: none. Reaches JS as "ui:main_menu".
const UI_MAIN_MENU := &"ui_main_menu"

## React asked for a scene to be streamed in. Loading happens on the loader pool and the
## swap only runs once the resource is ready, so the main thread never waits on it.
##
## Payload: {"scene": string}. Reaches JS as "ui:load_scene".
const UI_LOAD_SCENE := &"ui_load_scene"

# ==============================================================================
# Wire mapping
# ==============================================================================

## Bus name to JS wire name. [JsBridgeObserver] forwards every entry, so adding
## an outbound event is a shared/events.json edit and nothing more.
const OUTBOUND_WIRE: Dictionary[StringName, String] = {
	SCENE_CHANGED: "scene:changed",
	SCENE_LOADING: "scene:loading",
	PLAYER_STATE: "player:state",
	STATE_CHANGED: "game:state",
	SCORE_CHANGED: "game:score",
	LEVEL_CHANGED: "level:changed",
	RUN_OVER: "game:run_over",
	WORLD_CLOCK: "world:clock",
	VIEWER_STATE: "viewer:state",
	DOOR_STATE: "door:state",
	RENDER_BUDGET: "render:budget",
	NOTICE_READ: "notice:read",
	JOURNAL_ENTRY: "journal:entry",
}

## Ordered payload fields, passed to JS as positional primitives.
## An absent event has no flat primitive record and goes as JSON.
const WIRE_FIELDS: Dictionary[String, Array] = {
	"godot:ready": [],
	"scene:changed": ["scene"],
	"scene:loading": ["scene", "progress", "status"],
	"player:state": ["health", "max_health"],
	"game:state": ["run", "flags", "world"],
	"game:score": ["score"],
	"level:changed": ["level", "index", "total", "outcome"],
	"world:clock": ["hour", "minute"],
	"viewer:state": ["carriage", "location"],
	"door:state": ["open", "locked", "distance"],
	"render:budget": ["shrink", "detail"],
	"notice:read": ["id"],
	"journal:entry": ["id", "kind", "actor", "target", "place", "at"],
}

## JS wire name to bus name. [GameBridge] republishes every entry, so a command
## from React is indistinguishable from in-game intent downstream.
const INBOUND_BUS: Dictionary[String, StringName] = {
	"ui:pause": UI_PAUSE,
	"ui:restart": UI_RESTART,
	"ui:main_menu": UI_MAIN_MENU,
	"ui:load_scene": UI_LOAD_SCENE,
}