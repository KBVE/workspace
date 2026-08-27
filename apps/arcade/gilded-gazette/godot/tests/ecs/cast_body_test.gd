# GdUnitTestSuite
extends GdUnitTestSuite

const SCENE := "res://scenes/train/train.scn"

## Late enough that everybody has boarded and spread out along the train. At the
## departure the carriages are empty and every one of these would be a test of nothing.
const ABOARD_MINUTES := 21 * 60


## Through the clock system rather than by writing the minute: the minute is derived
## from a phase, and setting it by hand is overwritten on the next tick.
func _clock_to(minutes: int) -> void:
	Session.time_of_day.running = false
	var clock: SClock = Ecs.runner.get_system(&"clock")
	clock.set_minutes(Session.time_of_day, minutes)


func _rigs_in(train: Node) -> Array:
	var cast_root: Node = train.get_node_or_null("Screen/Frame/World/Cast")
	return cast_root.get_children().filter(func(n: Node) -> bool: return n is CharacterRig) \
		if cast_root != null else []


## Everybody with a face and a place, not only the passengers: the guard's van holds an
## escort that is on no timeline and in no content file.
func _cast_within(train: Node) -> int:
	var aboard := GameContent.carriage_locations()
	var here: int = train._occupant.carriage_index
	var window: int = train.get_node("Screen/Frame/World/Consist").mesh_window
	var count := 0
	for entry: Dictionary in Ecs.world.multi_view([CLocation, CAppearance]):
		var carriage := aboard.find(entry[&"CLocation"].location_id)
		if carriage >= 0 and absi(carriage - here) <= window:
			count += 1
	return count


## What a passenger looks like, without where they are standing. The escort paces their
## post, so a position compared across a rebuild is a test of the clock rather than of
## anybody's identity; where a rebuilt character stands is
## [method test_a_rebuilt_passenger_is_met_where_they_walked_to].
func _looks_of(train: Node) -> Array:
	return _rigs_in(train).map(func(rig: CharacterRig) -> Array:
		return [rig.appearance.outfit, rig.appearance.hair, rig.appearance.accessories,
			rig.appearance.tints, rig.appearance.stature_metres])


func after_test() -> void:
	Session.time_of_day.running = true


## Nobody is built for a carriage that is not drawn, which is the whole reason the
## passengers are not five rigs standing in the scene from the start.
func test_only_passengers_in_a_drawn_carriage_have_a_body() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(30)
	var train: Node = runner.scene()

	var expected := _cast_within(train)
	assert_int(expected).override_failure_message(
		"the evening was picked so that somebody is aboard and near the player"
	).is_greater(0)
	assert_int(_rigs_in(train).size()).override_failure_message(
		"every passenger in a drawn carriage should have been built by now"
	).is_equal(expected)


## One rig a tick. A cast that all arrived on the same frame would be a visible hitch
## the moment a carriage came into view, and the whole point of the budget is that a
## larger cast costs more ticks rather than a longer one.
func test_bodies_are_built_one_tick_at_a_time() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(2)
	var train: Node = runner.scene()
	var so_far := _rigs_in(train).size()

	await runner.simulate_frames(1)
	assert_int(_rigs_in(train).size() - so_far).override_failure_message(
		"a single frame should not add more than one body"
	).is_less_equal(SCastBody.BUILDS_PER_TICK)


## A passenger is evidence. Walking out of a carriage and back has to hand back the
## same person in the same place, not a fresh roll wearing somebody else's coat.
func test_a_rebuilt_passenger_is_the_same_person() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(30)
	var train: Node = runner.scene()

	var before := _looks_of(train)
	assert_array(before).is_not_empty()

	var bodies: SCastBody = Ecs.runner.get_system(&"cast_body")
	var window := bodies.carriage_window
	bodies.carriage_window = -1
	await runner.simulate_frames(2)
	assert_array(_rigs_in(train)).override_failure_message(
		"out of view, a passenger should not still be holding a rig"
	).is_empty()

	bodies.carriage_window = window
	await runner.simulate_frames(30)
	assert_array(_looks_of(train)).override_failure_message(
		"the same passengers should come back identical, down to where they stand"
	).is_equal(before)


## The Order does not send one knight with a crate. The escort is aboard from the first
## frame and on no timeline that could move them, so the ones on the cargo stay on it.
##
## Not all four. One of them is walking the train, and that is what makes it a watch
## rather than a tableau: [SGuardWatch] gives the patrol a beat and [SCastBody] then
## reads their room off where the walk has got to. Asserting the whole escort was in the
## van only passed while the patrol had not had time to leave it yet, which is a test of
## how fast the machine is.
func test_the_escort_stands_with_the_cargo() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)

	var sworn := 0
	var on_rounds := 0
	for entry: Dictionary in _escort():
		sworn += 1
		if _is_on_patrol(entry):
			on_rounds += 1
			assert_array(_errand_of(entry).beat).override_failure_message(
				"the knight on patrol was given no rounds to walk"
			).is_not_empty()
			continue
		assert_str(String(entry[&"CLocation"].location_id)).override_failure_message(
			"a sworn knight who is not on patrol should be with the crate"
		).is_equal(String(Session.ESCORT_LOCATION))
	assert_int(sworn).override_failure_message(
		"the guard's van should hold the Order's escort"
	).is_equal(Session.ESCORT.size())
	assert_int(on_rounds).override_failure_message(
		"nobody is walking the train, so the watch never turns"
	).is_equal(1)


## Escorts have no timeline, so nothing should ever move them; passengers do, and the
## same system must not confuse the two.
func test_the_escort_is_never_moved_by_the_clock() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(4)
	var clock: SClock = Ecs.runner.get_system(&"clock")
	Session.time_of_day.running = false

	for minutes: int in [17 * 60, 21 * 60, 2 * 60]:
		clock.set_minutes(Session.time_of_day, minutes)
		await runner.simulate_frames(2)
		for entry: Dictionary in _escort():
			assert_str(String(entry[&"CLocation"].location_id)).override_failure_message(
				"the escort left the cargo at %d minutes past midnight" % minutes
			).is_equal(String(Session.ESCORT_LOCATION))
	Session.time_of_day.running = true


## Whether this knight is the one walking the train. Their duty rather than their room:
## where the patrol has got to is the answer, not the question.
func _is_on_patrol(entry: Dictionary) -> bool:
	var duty: CWatch = entry["entity"].getc(CWatch) as CWatch
	return duty != null and duty.duty == CWatch.PATROL


func _errand_of(entry: Dictionary) -> CErrand:
	return entry["entity"].getc(CErrand) as CErrand


## The escort, told from the cast by what they lack: Dame Marchand wears the same plate
## and is a passenger, with a timeline that moves her off the cargo at twenty to ten.
func _escort() -> Array:
	return Ecs.world.multi_view([CLocation, CAppearance]).filter(
		func(entry: Dictionary) -> bool:
			return not entry["entity"].has(CPassenger))


## A rig is thrown away when its carriage stops being drawn and built again when it
## comes back, but the character does not stop existing in between: [CErrand] keeps
## walking them. Coming back into view has to find them where the walk got to, not
## where the rig was left.
func test_a_rebuilt_passenger_is_met_where_they_walked_to() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(30)
	var train: Node = runner.scene()
	var bodies: SCastBody = Ecs.runner.get_system(&"cast_body")

	var window := bodies.carriage_window
	bodies.carriage_window = -1
	await runner.simulate_frames(2)
	bodies.carriage_window = window
	await runner.simulate_frames(30)

	for entry: Dictionary in Ecs.world.multi_view([CErrand, CCharacterRig]):
		var rig: CharacterRig = entry[&"CCharacterRig"].live()
		if rig == null:
			continue
		assert_float(rig.global_position.distance_to(entry[&"CErrand"].at)) \
			.override_failure_message("a rebuilt rig stands somewhere its character is not") \
			.is_less(0.5)
