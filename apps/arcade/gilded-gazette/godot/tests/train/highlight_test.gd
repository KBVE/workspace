# GdUnitTestSuite
extends GdUnitTestSuite

## The outline around whatever the cursor is on.
##
## The whole interaction surface of this game runs through the pointer: the evidence is
## looked at and picked up, the doors are pointed at rather than walked into, and the
## notices are read off the wall. None of that is visible without the marker, and a
## marker that silently stops drawing looks exactly like a game with nothing to click.

const SCENE := "res://scenes/train/train.scn"


func _pointing() -> Dictionary:
	var found: Array = Ecs.world.multi_view([CPointer, CHighlight])
	return found[0] if not found.is_empty() else {}


func _pointer() -> CPointer:
	return _pointing()[&"CPointer"]


func _marker() -> SelectionHighlight:
	return _pointing()[&"CHighlight"].view


## What the pointer resolved is cleared and rewritten every frame by [SPointing], so a
## test that set it and waited would be testing the mouse. Marking is asked for directly
## instead: this is [SHighlight]'s job and nothing else's.
func _mark() -> void:
	var system: SHighlight = Ecs.runner.get_system(&"highlight")
	system._mark(_pointer(), _marker())


func _a_seat() -> CSeat:
	var seats: Array = Ecs.world.view(&"CSeat")
	return seats[0] if not seats.is_empty() else null


## A leaf of two meshes, one of them glass, which is what a door actually is.
func _a_leaf_with_a_window() -> Node3D:
	var leaf := Node3D.new()
	var panel := MeshInstance3D.new()
	panel.mesh = BoxMesh.new()
	leaf.add_child(panel)

	var pane := MeshInstance3D.new()
	var glass := BoxMesh.new()
	var glazing := StandardMaterial3D.new()
	glazing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.surface_set_material(0, glazing)
	pane.mesh = glass
	leaf.add_child(pane)

	add_child(leaf)
	auto_free(leaf)
	return leaf


func test_the_marker_is_there_to_be_drawn_on() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	assert_object(_marker()).override_failure_message(
		"nothing in the consist holds the outline, so nothing can ever be shown selected"
	).is_not_null()


func test_pointing_at_nothing_draws_nothing() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	var pointer := _pointer()
	pointer.seat = null
	pointer.door_leaf = null
	pointer.notice_sheet = null
	_mark()
	assert_bool(_marker().visible).is_false()


func test_a_seat_is_outlined_where_the_cushion_is() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	var seat := _a_seat()
	assert_object(seat).is_not_null()

	var pointer := _pointer()
	pointer.seat = seat
	pointer.door_leaf = null
	pointer.notice_sheet = null
	_mark()

	var marker := _marker()
	assert_bool(marker.visible).is_true()
	assert_bool(marker._wire.visible).override_failure_message(
		"a seat has no mesh of its own, so it has to be the wire box or it is nothing"
	).is_true()
	assert_float(marker._wire.global_position.y).is_greater(seat.at.y)


## A door hands over its own meshes, so the outline is the shape of the door -- and a
## glb is as many meshes as whoever exported it felt like.
func test_a_door_is_outlined_by_its_own_meshes() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	var pointer := _pointer()
	pointer.seat = null
	pointer.notice_sheet = null
	pointer.door_leaf = _a_leaf_with_a_window()
	_mark()

	var marker := _marker()
	assert_bool(marker.visible).is_true()
	assert_bool(marker._wire.visible).override_failure_message(
		"a door was outlined with the seat box instead of its own shape").is_false()


## A hull around glass is a hull filled with glass: nothing is drawn over the shell to
## hide its middle, so the whole door comes back as a tinted sheet.
func test_the_window_in_a_door_is_not_outlined() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	var pointer := _pointer()
	pointer.seat = null
	pointer.notice_sheet = null
	pointer.door_leaf = _a_leaf_with_a_window()
	_mark()

	var drawn := 0
	for hull: MeshInstance3D in _marker()._hulls:
		if hull.visible:
			drawn += 1
	assert_int(drawn).override_failure_message(
		"%d of the two meshes in the leaf were outlined, and one of them is the glass"
			% drawn).is_equal(1)


## A notice hangs on the wall above the benches, so a ray that reaches one has already
## passed everything else in the carriage. It wins.
func test_a_notice_beats_the_seat_and_the_door_behind_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	var sheet := _a_leaf_with_a_window()

	var pointer := _pointer()
	pointer.seat = _a_seat()
	pointer.door_leaf = _a_leaf_with_a_window()
	pointer.notice_sheet = sheet
	_mark()

	assert_bool(_marker()._wire.visible).override_failure_message(
		"the seat box was drawn over a notice the player was pointing at").is_false()


## Nothing is left behind. The marker is one node reshaped, so an outline that is not
## put away is an outline standing in the last place anybody looked.
func test_looking_away_puts_the_outline_away() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	var pointer := _pointer()

	pointer.seat = _a_seat()
	pointer.door_leaf = null
	pointer.notice_sheet = null
	_mark()
	assert_bool(_marker().visible).is_true()

	pointer.seat = null
	_mark()
	assert_bool(_marker().visible).override_failure_message(
		"the outline stayed on a seat the player had stopped pointing at").is_false()


## [SPointing] resolves one thing, not three. Everything downstream reads the first
## field it finds set, so two of them set at once is two different answers to the same
## question depending on who is asking.
func test_the_pointer_only_ever_holds_one_answer() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	for _frame in range(10):
		await runner.simulate_frames(1)
		var pointer := _pointer()
		var claimed := 0
		if pointer.seat != null:
			claimed += 1
		if pointer.door != null:
			claimed += 1
		if pointer.notice != null:
			claimed += 1
		assert_int(claimed).override_failure_message(
			"the pointer is on %d things at once" % claimed).is_less_equal(1)
		if pointer.has_target:
			assert_int(claimed).override_failure_message(
				"the pointer says it has a target and names nothing").is_equal(1)
