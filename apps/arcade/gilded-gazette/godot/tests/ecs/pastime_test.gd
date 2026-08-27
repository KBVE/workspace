# GdUnitTestSuite
extends GdUnitTestSuite

const SCENE := "res://scenes/train/train.scn"

## Late enough that everybody has boarded and is in a room with benches in it.
const ABOARD_MINUTES := 22 * 60 + 30


func _clock_to(minutes: int) -> void:
	Session.time_of_day.running = false
	var clock: SClock = Ecs.runner.get_system(&"clock")
	clock.set_minutes(Session.time_of_day, minutes)


func after_test() -> void:
	Session.time_of_day.running = true


func _cast() -> Array:
	return Ecs.world.multi_view([CPastime, CErrand, CSeating, CIdentity])


## Wound forward rather than waited out: the waits are rolled between six and twenty-two
## seconds so that a carriage does not move as one, and a test that sat through them
## would take most of a minute to learn nothing.
func _make_them_restless() -> void:
	for entry: Dictionary in _cast():
		var pastime: CPastime = entry[&"CPastime"]
		pastime.wanders_before_settling = 0
		pastime.seconds_until_restless = 0.0


## The whole point. A passenger left standing where their timeline put them, facing the
## seats, for the length of an hour, is a shop dummy.
func test_a_passenger_takes_a_seat() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(30)
	_make_them_restless()
	await runner.simulate_frames(240)

	var sat := _cast().filter(func(entry: Dictionary) -> bool:
		return entry[&"CSeating"].seated)
	assert_array(sat).override_failure_message(
		"nobody found a bench in four seconds of walking").is_not_empty()

	for entry: Dictionary in sat:
		var seating: CSeating = entry[&"CSeating"]
		assert_object(seating.seat).override_failure_message(
			"somebody is sitting on nothing").is_not_null()
		assert_object(seating.seat.taken_by).override_failure_message(
			"a seat somebody is in should say so, or the next passenger sits on them"
		).is_same(seating)


## Two passengers crossing a carriage at the same bench is a passenger sat on. The seat
## is claimed when they set off, not when they arrive.
func test_no_two_passengers_take_the_same_seat() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(30)
	_make_them_restless()
	await runner.simulate_frames(240)

	var claimed := {}
	for entry: Dictionary in _cast():
		var seat: CSeat = entry[&"CSeating"].seat
		if seat == null:
			continue
		assert_bool(claimed.has(seat)).override_failure_message(
			"%s is taking a bench somebody else already has"
			% entry[&"CIdentity"].content_id).is_false()
		claimed[seat] = true


## The timeline outranks the bench. When the hour says they are somewhere else, they get
## up, give the seat back and walk, whatever they were in the middle of.
func test_the_timeline_gets_them_out_of_their_seat() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(30)
	_make_them_restless()
	await runner.simulate_frames(240)

	var sitting: Dictionary = {}
	for entry: Dictionary in _cast():
		if entry[&"CSeating"].seated:
			sitting = entry
			break
	assert_dict(sitting).override_failure_message("nobody sat down to be moved").is_not_empty()
	var seat: CSeat = sitting[&"CSeating"].seat
	var location: CLocation = sitting["entity"].getc(CLocation) as CLocation
	var was_in := location.location_id

	# Wound with the clock rather than written by hand: [SPassengerPlace] rewrites the
	# room from the timeline every tick, so a room set here is gone before anything
	# reads it. The hours are theirs, whoever they turned out to be.
	var moved := false
	for minutes: int in [23 * 60 + 45, 0, 60, 2 * 60, 4 * 60]:
		_clock_to(minutes)
		await runner.simulate_frames(4)
		if location.location_id != was_in:
			moved = true
			break
	assert_bool(moved).override_failure_message(
		"the night never moved %s out of %s" % [sitting[&"CIdentity"].content_id, was_in]
	).is_true()

	assert_bool(sitting[&"CSeating"].seated).override_failure_message(
		"the hour moved them on and they stayed in their seat").is_false()
	assert_object(seat.taken_by).override_failure_message(
		"they took the bench with them").is_null()


## The benches belong to the carriage and the passengers do not. Walking far enough that
## the carriage stops being drawn used to leave them sitting on a [CSeat] that had been
## freed with it, holding a seat nobody could take, in a carriage not yet built.
func test_nobody_is_left_sitting_on_a_carriage_that_is_gone() -> void:
	var runner := scene_runner(SCENE)
	_clock_to(ABOARD_MINUTES)
	await runner.simulate_frames(30)
	_make_them_restless()
	await runner.simulate_frames(240)
	assert_array(_cast().filter(func(entry: Dictionary) -> bool:
		return entry[&"CSeating"].seated)
	).override_failure_message("nobody sat down, so nothing was torn out from under them"
	).is_not_empty()

	var train: Node = runner.scene()
	train.get_parent().remove_child(train)
	train.free()
	await await_idle_frame()

	for entry: Dictionary in _cast():
		var who: String = entry[&"CIdentity"].content_id
		assert_bool(entry[&"CSeating"].seated).override_failure_message(
			"%s is still sitting in a carriage that no longer exists" % who).is_false()
		assert_object(entry[&"CSeating"].seat).override_failure_message(
			"%s is holding a bench that was freed with the carriage" % who).is_null()
		assert_bool(entry[&"CErrand"].assigned).override_failure_message(
			"%s is still walking at a bench that is gone" % who).is_false()


## He is on his rounds all night. A conductor found sitting down is a conductor with
## something to explain.
func test_the_conductor_never_sits() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	for entry: Dictionary in Ecs.world.multi_view([CIdentity, CErrand]):
		if entry[&"CIdentity"].content_id != Session.ROUNDS_OF_THE_TRAIN:
			continue
		assert_bool(entry["entity"].has(CPastime)).override_failure_message(
			"the conductor has been given something to do besides his rounds").is_false()
