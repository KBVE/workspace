# GdUnitTestSuite
extends GdUnitTestSuite

## The one wiring point between the menus, the ECS and React. Nothing here fails
## loudly: a command that does not map, a scene streaming in behind a menu, a run state
## that stops being published all just leave the page showing what is no longer true.

## Streamed but never waited on. The request goes to the loader pool either way; what
## these are about is the intent to swap to it, which is the part that can be dropped.
const SOMETHING_TO_LOAD := "res://scenes/train/train.scn"


func _loading() -> Array[GameEvent]:
	var seen: Array[GameEvent] = []
	Ecs.world.add_callable(GameEvents.SCENE_LOADING,
		func(e: GameEvent) -> void: seen.append(e))
	return seen


func after_test() -> void:
	# Nothing may be left half-streamed: the next suite's scene swap would arrive
	# behind whatever this one asked for.
	GameBridge._abandon_the_stream()


func test_asking_for_a_scene_says_it_has_started() -> void:
	var seen := _loading()
	GameBridge.load_scene_async_streaming(SOMETHING_TO_LOAD)
	assert_int(seen.size()).is_greater(0)
	assert_str(str(seen[0].data.get("status", ""))).is_equal("start")


## The bug this was written for. Leaving the train while a scene is still coming in
## used to let the load finish behind the menu and then swap to it -- taking the player
## out of the menu they asked for and back into the scene they had just left.
func test_giving_up_on_a_stream_stops_it_swapping() -> void:
	GameBridge.load_scene_async_streaming(SOMETHING_TO_LOAD)
	assert_str(GameBridge._stream_path).is_equal(SOMETHING_TO_LOAD)

	var seen := _loading()
	GameBridge._abandon_the_stream()
	assert_str(GameBridge._stream_path).override_failure_message(
		"a scene nobody wants any more is still on its way in"
	).is_empty()
	assert_int(seen.size()).is_greater(0)
	assert_str(str(seen[-1].data.get("status", ""))).override_failure_message(
		"the page was left showing a loading curtain for a scene that never arrives"
	).is_equal("failed")


## The outgoing scene is disabled while something streams, because a live scene starves
## the loader. Giving up has to give it back, or the train is left frozen and invisible
## behind a menu that never came.
func test_giving_up_wakes_the_scene_back_up() -> void:
	GameBridge.load_scene_async_streaming(SOMETHING_TO_LOAD)
	GameBridge._abandon_the_stream()
	var current := get_tree().current_scene
	if current == null:
		return
	assert_int(current.process_mode).override_failure_message(
		"the scene the player is still standing in was left switched off"
	).is_not_equal(Node.PROCESS_MODE_DISABLED)


func test_giving_up_on_nothing_says_nothing() -> void:
	GameBridge._abandon_the_stream()
	var seen := _loading()
	GameBridge._abandon_the_stream()
	assert_int(seen.size()).override_failure_message(
		"a loading failure was reported for a load nobody asked for").is_equal(0)


## Asking for the same scene twice is one load. Without this the second request would
## quiet the outgoing scene again and report a second start for one swap.
func test_asking_twice_for_the_same_scene_is_one_load() -> void:
	GameBridge.load_scene_async_streaming(SOMETHING_TO_LOAD)
	var seen := _loading()
	GameBridge.load_scene_async_streaming(SOMETHING_TO_LOAD)
	assert_int(seen.size()).is_equal(0)


## Every wire name React can send has to map to a bus name, or the command is dropped
## with a warning nobody reading the page will see.
func test_every_inbound_command_reaches_a_bus() -> void:
	for wire: String in GameEvents.INBOUND_BUS:
		assert_str(String(GameEvents.INBOUND_BUS[wire])).override_failure_message(
			"'%s' maps to nothing" % wire).is_not_empty()


## First match wins, and the train is not under /game/. A scene that resolves to the
## wrong state leaves React showing a menu over a running carriage.
func test_the_train_counts_as_playing() -> void:
	assert_int(GameBridge._state_for_scene(SOMETHING_TO_LOAD)) \
		.is_equal(StateBits.RunState.PLAYING)
	assert_int(GameBridge._state_for_scene("res://scenes/menus/main_menu/main_menu.tscn")) \
		.is_equal(StateBits.RunState.MENU)
	assert_int(GameBridge._state_for_scene("res://scenes/nowhere.tscn")) \
		.is_equal(StateBits.RunState.BOOTING)
