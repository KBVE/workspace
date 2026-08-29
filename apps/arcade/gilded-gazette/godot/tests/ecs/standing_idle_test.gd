# GdUnitTestSuite
extends GdUnitTestSuite

## What a body on its feet and going nowhere does with itself. The standing half of the
## cast stood in the middle of the walk blend space, in step with each other, for as
## long as they were still.

const SCENE := "res://scenes/train/train.scn"

## A stopped body, its idle, and the two things that get a say before it does.
func _standing() -> Array:
	return Ecs.world.multi_view([CStandingIdle, CPosture, CLocomotion])


func _idle_of(content_id: StringName) -> CStandingIdle:
	for entry: Dictionary in Ecs.world.multi_view([CStandingIdle, CIdentity]):
		if entry[&"CIdentity"].content_id == content_id:
			return entry[&"CStandingIdle"]
	return null


## Wound past the settle and the wait rather than sat through: the waits are rolled
## between seven and eighteen seconds so a corridor does not change as one, and a test
## that waited would take a quarter of a minute to learn nothing.
func _make_them_restless() -> void:
	for entry: Dictionary in _standing():
		var idle: CStandingIdle = entry[&"CStandingIdle"]
		idle.still_seconds = idle.settling_seconds
		idle.seconds_until_change = 0.0


func test_everybody_standing_has_something_to_stand_about() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	assert_int(_standing().size()).override_failure_message(
		"nobody aboard has a standing idle, so every stopped body plays the same loop"
	).is_greater(0)


func test_a_stopped_body_stops_playing_the_plain_idle() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_make_them_restless()
	await runner.simulate_frames(4)

	var moved_on := 0
	for entry: Dictionary in _standing():
		if entry[&"CStandingIdle"].state != CPosture.AFOOT:
			moved_on += 1
	assert_int(moved_on).override_failure_message(
		"every standing body was still on the plain idle after its wait ran out"
	).is_greater(0)


## The one thing about a standing body that is not interchangeable. Give the passengers
## the escort's list and eight people stand in the corridor like guards.
func test_a_passenger_is_never_given_the_guard_s_stance() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	for entry: Dictionary in Ecs.world.multi_view([CStandingIdle, CPassenger]):
		assert_bool(entry[&"CStandingIdle"].choices.has(CPosture.STANDING_FOLDED)) \
			.override_failure_message("a passenger was given the folded arms of a knight") \
			.is_false()


func test_the_escort_stand_like_the_escort() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	var sworn := Ecs.world.multi_view([CStandingIdle, CWatch])
	assert_int(sworn.size()).is_equal(Session.ESCORT.size())
	for entry: Dictionary in sworn:
		assert_bool(entry[&"CStandingIdle"].choices.has(CPosture.STANDING_FOLDED)) \
			.override_failure_message("a knight on watch has nothing to do with his hands") \
			.is_true()


## Two knights either side of one crate folding their arms on the same frame is worse
## than neither of them moving at all.
func test_two_of_them_do_not_move_together() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	var seeds := {}
	for entry: Dictionary in _standing():
		seeds[entry[&"CStandingIdle"].rng.seed] = true
	assert_int(seeds.size()).override_failure_message(
		"the standing cast share %d seeds between them, so they move as one"
			% seeds.size()
	).is_equal(_standing().size())


## A walk interrupted by a man folding his arms is worse than no variation at all.
func test_a_walking_body_is_left_to_walk() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_make_them_restless()
	await runner.simulate_frames(4)

	var entry: Dictionary = _standing()[0]
	var idle: CStandingIdle = entry[&"CStandingIdle"]
	var locomotion: CLocomotion = entry[&"CLocomotion"]
	locomotion.forward_metres_per_second = 1.2
	await runner.simulate_frames(2)
	assert_str(idle.state).override_failure_message(
		"a body that started walking kept standing about"
	).is_equal(CPosture.AFOOT)


## Somebody who paused to let a door open does not fold their arms about it.
func test_a_pause_is_not_a_wait() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	var entry: Dictionary = _standing()[0]
	var idle: CStandingIdle = entry[&"CStandingIdle"]
	var locomotion: CLocomotion = entry[&"CLocomotion"]

	locomotion.forward_metres_per_second = 1.2
	await runner.simulate_frames(2)
	locomotion.forward_metres_per_second = 0.0
	idle.seconds_until_change = 0.0
	await runner.simulate_frames(2)

	assert_str(idle.state).override_failure_message(
		"a body stopped for two frames had already found something to do with its hands"
	).is_equal(CPosture.AFOOT)


## The rig is told a state it has an input for, or the transition silently keeps the
## one it had and the whole system is a component nobody can see.
func test_every_standing_state_is_a_state_the_rig_knows() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	for entry: Dictionary in _standing():
		for state: StringName in entry[&"CStandingIdle"].choices:
			assert_bool(CPosture.STANDING_STATES.has(state)).override_failure_message(
				"'%s' is not one of the standing states" % state).is_true()


## Sitting outranks standing about, and a character who sat down mid-look must not
## stand back up with the look already half over.
func test_sitting_down_puts_the_standing_idle_away() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_make_them_restless()
	await runner.simulate_frames(4)

	for entry: Dictionary in Ecs.world.multi_view([CStandingIdle, CSeating]):
		if not entry[&"CSeating"].seated:
			continue
		assert_str(entry[&"CStandingIdle"].state).override_failure_message(
			"somebody sat down and went on looking around the corridor"
		).is_equal(CPosture.AFOOT)
