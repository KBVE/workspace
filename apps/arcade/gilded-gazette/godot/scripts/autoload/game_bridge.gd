extends Node

## GameBridge : Maaack <-> ECS <-> React, one wiring point
##
## Gameplay never imports [JsBridge], menus never import the ECS.


## First match wins.
const SCENE_STATES: Array[Array] = [
	["/game/", StateBits.RunState.PLAYING],
	# the three levels live in one carriage scene, outside /game/
	["/train/", StateBits.RunState.PLAYING],
	["/end_credits/", StateBits.RunState.ENDED],
	["/menus/", StateBits.RunState.MENU],
]

var _last_scene_path: String = ""
var _run_state: int = StateBits.RunState.BOOTING
var _player_flags: int = 0
var _world_mode: int = StateBits.WorldMode.NONE
var _stream_path: String = ""
var _stream_clock: float = 0.0

var _menu_scene: PackedScene = null
var _menu_path: String = ""
var _menu_pending: bool = false

func _ready() -> void:
	Ecs.add_observer(JsBridgeObserver.new())
	JsBridge.command_received.connect(_on_js_command)
	Ecs.world.add_callable(GameEvents.UI_PAUSE, _on_ui_pause)
	Ecs.world.add_callable(GameEvents.UI_MAIN_MENU, _on_ui_main_menu)
	Ecs.world.add_callable(GameEvents.UI_LOAD_SCENE, _on_ui_load_scene)
	process_priority = 100
	# unpause is a React command; Ecs pauses with the tree, this cannot
	process_mode = Node.PROCESS_MODE_ALWAYS
	_begin_menu_preload()

## Polls rather than listening: scene_loaded fires before the swap, and never at
## all for a load that does not swap.
func _process(delta: float) -> void:
	_poll_menu_preload()
	if not _stream_path.is_empty():
		_poll_stream(delta)
	var current := get_tree().current_scene
	if current == null:
		return
	var path := current.scene_file_path
	if path == _last_scene_path:
		return
	_last_scene_path = path
	Ecs.notify(GameEvents.SCENE_CHANGED, {"scene": path})
	if get_tree().paused:
		get_tree().paused = false
	_set_run_state(_state_for_scene(path))

func _on_js_command(cmd: String, payload: Dictionary) -> void:
	if not GameEvents.INBOUND_BUS.has(cmd):
		push_warning("GameBridge: unmapped JS command '%s'." % cmd)
		return
	Ecs.notify(GameEvents.INBOUND_BUS[cmd], payload)

func _on_ui_pause(event: GameEvent) -> void:
	var payload: Variant = event.data
	var paused: bool = payload.get("paused", true) if payload is Dictionary else true
	# a paused menu is a soft lock
	var scene_state := _state_for_scene(_last_scene_path)
	if scene_state != StateBits.RunState.PLAYING:
		return
	get_tree().paused = paused
	_set_run_state(StateBits.RunState.PAUSED if paused else StateBits.RunState.PLAYING)

func load_scene_async_streaming(path: String) -> void:
	if path.is_empty() or path == _stream_path:
		return
	if ResourceLoader.load_threaded_request(path, "", true) != OK:
		_notify_loading(path, 0.0, "failed")
		return
	_stream_path = path
	_stream_clock = 0.0
	_quiet_outgoing_scene()
	_notify_loading(path, 0.0, "start")

## A live scene starves the loader: a menu asked for while the carriage ran
## crawled to 33% in 150 seconds and never landed.
func _quiet_outgoing_scene(quiet: bool = true) -> void:
	var current := get_tree().current_scene
	if current == null:
		return
	current.process_mode = Node.PROCESS_MODE_DISABLED if quiet else Node.PROCESS_MODE_INHERIT
	if current.has_method("set_visible"):
		current.call("set_visible", not quiet)

func _on_ui_load_scene(event: GameEvent) -> void:
	var payload: Variant = event.data
	if payload is Dictionary:
		load_scene_async_streaming(payload.get("scene", ""))

## Progress crosses the JS boundary, so it goes out at 10Hz, not per frame.
func _poll_stream(delta: float) -> void:
	var parts: Array = []
	var status := ResourceLoader.load_threaded_get_status(_stream_path, parts)
	var progress: float = parts[0] if not parts.is_empty() else 0.0
	var path := _stream_path

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_stream_clock += delta
			if _stream_clock >= 0.1:
				_stream_clock = 0.0
				_notify_loading(path, progress, "progress")
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			_stream_path = ""
			_notify_loading(path, 1.0, "ready")
			# change_scene_to_packed swaps at the end of the frame
			get_tree().change_scene_to_packed(packed)
		_:
			_stream_path = ""
			_quiet_outgoing_scene(false)
			_notify_loading(path, progress, "failed")

func _notify_loading(path: String, progress: float, status: String) -> void:
	Ecs.notify(GameEvents.SCENE_LOADING, {
		"scene": path,
		"progress": progress,
		"status": status,
	})

func _begin_menu_preload() -> void:
	_menu_path = ProjectSettings.get_setting(
		"maaacks_game_template/main_menu_scene_path", "")
	if _menu_path.is_empty():
		return
	_menu_pending = ResourceLoader.load_threaded_request(_menu_path, "", true) == OK

func _poll_menu_preload() -> void:
	if not _menu_pending:
		return
	var status := ResourceLoader.load_threaded_get_status(_menu_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_menu_pending = false
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_menu_scene = ResourceLoader.load_threaded_get(_menu_path) as PackedScene
	else:
		push_warning("GameBridge: main menu preload failed; will stream on demand.")

func _on_ui_main_menu(_event: GameEvent) -> void:
	var path: String = ProjectSettings.get_setting(
		"maaacks_game_template/main_menu_scene_path", "")
	if path.is_empty():
		push_warning("GameBridge: no main_menu_scene_path set.")
		return
	get_tree().paused = false
	if _menu_scene != null:
		# already in memory, so no scene:loading pair is reported
		get_tree().change_scene_to_packed(_menu_scene)
		return
	load_scene_async_streaming(path)

func set_world_mode(mode: int) -> void:
	if mode == _world_mode:
		return
	_world_mode = mode
	_publish()


func set_player_flags(flags: int) -> void:
	if flags == _player_flags:
		return
	_player_flags = flags
	_publish()

func _state_for_scene(path: String) -> int:
	for entry: Array in SCENE_STATES:
		if path.contains(entry[0]):
			return entry[1]
	return StateBits.RunState.BOOTING

func _set_run_state(state: int) -> void:
	if state == _run_state:
		return
	_run_state = state
	_publish()

func _publish() -> void:
	Ecs.notify(GameEvents.STATE_CHANGED, {"run": _run_state, "flags": _player_flags, "world": _world_mode})
