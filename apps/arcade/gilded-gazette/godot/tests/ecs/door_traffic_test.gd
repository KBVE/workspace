# GdUnitTestSuite
extends GdUnitTestSuite

const SCENE := "res://scenes/train/train.scn"

## Late enough that the cast are aboard and standing in rooms they will later leave.
const ABOARD_MINUTES := 21 * 60

## When Lady Beaumont's timeline takes her from the corridor to her cabin, which is a
## carriage along and a door in between.
const SHE_RETIRES_MINUTES := 23 * 60 + 45


func _clock_to(minutes: int) -> void:
	Session.time_of_day.running = false
	var clock: SClock = Ecs.runner.get_system(&"clock")
	clock.set_minutes(Session.time_of_day, minutes)


func after_test() -> void:
	Session.time_of_day.running = true


func _doors() -> Array:
	return Ecs.world.multi_view([CDoor, ECSViewComponent])


## Nobody has hands to press [F] with but the player, so a door in front of a walking
## character has to open because they are walking through it.
func test_a_door_opens_for_somebody_walking_through_it() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(30)
	# Not "a settled cast holds nothing open" any more: passengers cross their room for
	# a bench now, and one of them doing that at a doorway is a door that should open.
	# What holds either way is that a door being held has somebody at it.
	for entry: Dictionary in _doors():
		if entry[&"CDoor"].held_open_by == 0:
			continue
		var leaf: Node3D = entry[&"ECSViewComponent"].view as Node3D
		assert_bool(_anybody_walking_at(leaf.global_position)).override_failure_message(
			"a door is being held open with nobody near it"
		).is_true()

	_clock_to(SHE_RETIRES_MINUTES)
	var opened := false
	for step in range(14):
		await runner.simulate_frames(60)
		for entry: Dictionary in _doors():
			if entry[&"CDoor"].held_open_by > 0 and entry[&"CDoor"].swing > 0.9:
				opened = true
	assert_bool(opened).override_failure_message(
		"walking the cast to their cabins should have swung a door open on the way"
	).is_true()


## The escort pace a few metres of the guard's van all night. On distance alone the end
## door flapped every time one of them turned round at that end of their beat.
##
## Measured against whoever else is aboard rather than on a still train: the cast walk
## their timelines the whole time, and waiting for them to settle takes twenty seconds
## of walking. What is asserted is narrower and truer for it -- a van door standing open
## with nobody but the escort near it is the escort having opened it.
func test_pacing_beside_a_door_does_not_work_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)

	var posted: Array[Vector3] = []
	for entry: Dictionary in Ecs.world.multi_view([CWatch, CErrand]):
		if entry[&"CWatch"].duty == CWatch.POST:
			posted.append(entry[&"CErrand"].station)
	assert_array(posted).override_failure_message(
		"the guard's van should hold knights on post over the crate").is_not_empty()

	var theirs: Array = _doors().filter(func(entry: Dictionary) -> bool:
		var leaf: Node3D = entry[&"ECSViewComponent"].view as Node3D
		for station: Vector3 in posted:
			if absf(leaf.global_position.x - station.x) < 12.0:
				return true
		return false)
	assert_array(theirs).is_not_empty()

	var sampled := 0
	for step in range(12):
		await runner.simulate_frames(45)
		for entry: Dictionary in theirs:
			var leaf: Node3D = entry[&"ECSViewComponent"].view as Node3D
			if _someone_else_is_at(leaf.global_position):
				continue
			sampled += 1
			assert_int(entry[&"CDoor"].held_open_by).override_failure_message(
				"the escort turning round at the end of their beat worked the door"
			).is_equal(0)
	assert_int(sampled).override_failure_message(
		"never once was the van door left to the escort alone").is_greater(0)


## Whether anybody who is not on a beat is close enough to a door to be the one using
## it. Generous on purpose: what this rules out is crediting the escort with a door
## somebody else opened.
func _someone_else_is_at(door_at: Vector3) -> bool:
	for entry: Dictionary in Ecs.world.multi_view([CErrand, CLocomotion]):
		var errand: CErrand = entry[&"CErrand"]
		# Anybody on the watch is the escort, whichever duty they are holding: the one
		# out on patrol works doors the length of the train, and rightly.
		if entry["entity"].has(CWatch) or not errand.stationed:
			continue
		if absf(errand.at.x - door_at.x) < SDoorTraffic.HOLD_METRES + 2.0:
			return true
	return false


## Whether anybody who is walking is close enough to the door to be the one holding it.
func _anybody_walking_at(door_at: Vector3) -> bool:
	for entry: Dictionary in Ecs.world.multi_view([CErrand, CLocomotion]):
		if absf(entry[&"CLocomotion"].forward_metres_per_second) < 0.05:
			continue
		if entry[&"CErrand"].at.distance_to(door_at) <= SDoorTraffic.HOLD_METRES + 0.5:
			return true
	return false
