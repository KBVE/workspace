# GdUnitTestSuite
extends GdUnitTestSuite

const SCENE := "res://scenes/train/train.scn"
const ABOARD_MINUTES := 21 * 60
const SHE_RETIRES_MINUTES := 23 * 60 + 45

## What the aisle allows, the same way [Train] works it out.
const AISLE_HALF := Consist.SEAT_EDGE_Z - SCastWalk.SHOULDER_METRES


func _clock_to(minutes: int) -> void:
	Session.time_of_day.running = false
	var clock: SClock = Ecs.runner.get_system(&"clock")
	clock.set_minutes(Session.time_of_day, minutes)


func after_test() -> void:
	Session.time_of_day.running = true


## Stations were at the seat centre line for a while, which put every standing passenger
## inside a bench. The aisle is what is left between the benches, and it is narrow.
func test_nobody_is_stationed_inside_the_seating() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(30)

	var stationed := 0
	for entry: Dictionary in Ecs.world.multi_view([CErrand, CAppearance]):
		var errand: CErrand = entry[&"CErrand"]
		if not errand.stationed:
			continue
		# A bench is where somebody has decided this passenger belongs, and a bench is
		# inside the seating on purpose. The rule is about where the walk puts people,
		# not about where sitting down does.
		if errand.assigned:
			continue
		stationed += 1
		assert_float(absf(errand.station.z)).override_failure_message(
			"a station at z %.2f is inside the seating, which begins at %.2f"
			% [errand.station.z, Consist.SEAT_EDGE_Z]
		).is_less_equal(AISLE_HALF)
	assert_int(stationed).is_greater(0)


## The walk used to cut the corner between two rooms, which took a passenger diagonally
## through three rows of benches.
func test_a_walk_stays_in_the_aisle() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(30)
	_clock_to(SHE_RETIRES_MINUTES)

	var walked := 0
	for step in range(10):
		await runner.simulate_frames(45)
		for entry: Dictionary in Ecs.world.multi_view([CErrand, CLocomotion]):
			if absf(entry[&"CLocomotion"].forward_metres_per_second) < 0.05:
				continue
			# Somebody walking at a bench is leaving the aisle on purpose, which is what
			# taking a seat is. The rule is about crossing a room, not about arriving.
			if entry[&"CErrand"].assigned:
				continue
			walked += 1
			assert_float(absf(entry[&"CErrand"].at.z)).override_failure_message(
				"somebody is walking at z %.2f, and the benches start at %.2f"
				% [entry[&"CErrand"].at.z, Consist.SEAT_EDGE_Z]
			).is_less_equal(AISLE_HALF + 0.01)
	assert_int(walked).override_failure_message(
		"nobody walked, so nothing was tested").is_greater(0)


## Two people meeting in a corridor each step to their own right. Neither is told which
## of them is giving way, and both end up on opposite sides because their own right
## points opposite ways.
func test_two_walkers_meeting_step_to_opposite_sides() -> void:
	var going_up := {"at": Vector3(0.0, 0.0, 0.0), "to": Vector3(10.0, 0.0, 0.0)}
	var coming_down := {"at": Vector3(2.0, 0.0, 0.0), "to": Vector3(-10.0, 0.0, 0.0)}
	var traffic: Array[Dictionary] = [going_up, coming_down]

	# Their own right points opposite ways along the carriage, which is the whole trick.
	var his := SCastWalk.room_for_oncoming(going_up["at"], going_up["to"], 1.0, traffic, 0.3)
	var hers := SCastWalk.room_for_oncoming(coming_down["at"], coming_down["to"], -1.0,
		traffic, 0.3)

	assert_float(his).override_failure_message("the one walking up gave no room").is_not_equal(0.0)
	assert_float(hers).override_failure_message("the one walking down gave no room").is_not_equal(0.0)
	assert_float(signf(his)).override_failure_message(
		"both stepped the same way, so they walk through each other"
	).is_not_equal(signf(hers))
	assert_float(absf(his)).is_less_equal(0.3)


## Somebody walking the same way is not a meeting. In a corridor where everybody walks
## at one speed, an overtake never comes.
func test_nobody_steps_aside_for_somebody_going_their_way() -> void:
	var ahead := {"at": Vector3(2.0, 0.0, 0.0), "to": Vector3(20.0, 0.0, 0.0)}
	assert_float(SCastWalk.room_for_oncoming(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0,
		[ahead] as Array[Dictionary], 0.3)).is_equal(0.0)


## Somebody the length of a carriage away is not in the way yet, and sidling for them
## the whole distance reads as a limp.
func test_room_is_made_late_not_early() -> void:
	var far_off = {"at": Vector3(SCastWalk.MAKE_ROOM_METRES + 1.0, 0.0, 0.0),
		"to": Vector3(-20.0, 0.0, 0.0)}
	assert_float(SCastWalk.room_for_oncoming(Vector3.ZERO, Vector3(20.0, 0.0, 0.0), 1.0,
		[far_off] as Array[Dictionary], 0.3)).is_equal(0.0)
