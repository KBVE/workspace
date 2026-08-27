# GdUnitTestSuite
extends GdUnitTestSuite

const SCENE := "res://scenes/train/train.scn"

## Frame length to hand simulate_frames where a test is waiting on somebody to walk
## somewhere, so the wait is a number of seconds rather than a number of frames.
const SIMULATED_MILLISECONDS := 20


func _conductor() -> Dictionary:
	for entry: Dictionary in Ecs.world.multi_view([CIdentity, CErrand, CLocation]):
		if entry[&"CIdentity"].content_id == Session.ROUNDS_OF_THE_TRAIN:
			return entry
	return {}


## The rounds are the length of the train and back. Walking only one way would put him
## at the far end with nowhere to go but a jump back to the first carriage.
func test_the_rounds_return_the_way_they_came() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var beat: Array[StringName] = _conductor()[&"CErrand"].beat
	var aboard := GameContent.carriage_locations()

	for room: StringName in aboard:
		assert_bool(beat.has(room)).override_failure_message(
			"the rounds never reach %s" % room).is_true()
	assert_int(beat.size()).override_failure_message(
		"a beat that only runs one way ends with a jump back to the front"
	).is_equal(aboard.size() * 2 - 2)


## Thirty years of the same corridor. The point of him is that he is somewhere else
## every time you look up.
func test_the_conductor_crosses_carriages() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var conductor := _conductor()
	var seen := {}
	# with a delta, because he walks in metres per second and simulate_frames without
	# one advances by however long a headless frame happens to take. Twenty-four
	# hundred bare frames is nine seconds of him on this machine and a fraction of that
	# on a busy runner, and a carriage is eighteen metres at one metre a second.
	for step in range(20):
		await runner.simulate_frames(50, SIMULATED_MILLISECONDS)
		seen[conductor[&"CLocation"].location_id] = true
	assert_int(seen.size()).override_failure_message(
		"the conductor spent the whole night in %s" % seen.keys()).is_greater(1)


## Where he says he is has to be where his feet are. Announcing the room he set off for
## would give him an alibi for a carriage he had not reached.
func test_his_room_is_the_one_he_is_standing_in() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var conductor := _conductor()
	var consist: Consist = runner.scene().get_node("Screen/Frame/World/Consist")
	var aboard := GameContent.carriage_locations()

	for step in range(12):
		await runner.simulate_frames(50, SIMULATED_MILLISECONDS)
		var standing_in: StringName = aboard[consist.carriage_index_at(conductor[&"CErrand"].at.x)]
		assert_str(String(conductor[&"CLocation"].location_id)).override_failure_message(
			"he is at x %.1f, which is %s, and claims %s"
			% [conductor[&"CErrand"].at.x, standing_in, conductor[&"CLocation"].location_id]
		).is_equal(String(standing_in))


## The timeline is what he tells an enquiry. Where he is, is where he walked to, and the
## clock must not drag him back up the train mid-stride.
func test_the_timeline_does_not_move_him() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var conductor := _conductor()
	Session.time_of_day.running = false
	var clock: SClock = Ecs.runner.get_system(&"clock")

	for minutes: int in [17 * 60, 19 * 60 + 30, 22 * 60 + 15]:
		var was_at: Vector3 = conductor[&"CErrand"].at
		clock.set_minutes(Session.time_of_day, minutes)
		await runner.simulate_frames(2)
		assert_float(conductor[&"CErrand"].at.distance_to(was_at)).override_failure_message(
			"winding the clock to %d teleported the conductor" % minutes).is_less(0.5)
	Session.time_of_day.running = true
