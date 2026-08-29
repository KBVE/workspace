# GdUnitTestSuite
extends GdUnitTestSuite

## The gas lamps, carriage by carriage.
##
## Lit per carriage rather than per train so one car can go dark or start stuttering
## while the rest stays lit. The train is ten carriages now, and nothing checked that
## the far ones were lit at all: a lamp system that stops at the fifth car looks exactly
## like a lamp system that works, from the first car.

const SCENE := "res://scenes/train/train.scn"

## Midnight and midday, in minutes, which are the two ends of what the lamps answer to.
const NIGHT_MINUTES := 0
const NOON_MINUTES := 12 * 60


func _clock_to(minutes: int) -> void:
	Session.time_of_day.running = false
	var clock: SClock = Ecs.runner.get_system(&"clock")
	clock.set_minutes(Session.time_of_day, minutes)


func after_test() -> void:
	Session.time_of_day.running = true


func _lamps() -> Array:
	return Ecs.world.multi_view([CLamp, CCarriage])


func test_every_carriage_in_the_consist_is_lit() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	assert_int(_lamps().size()).override_failure_message(
		"the train is %d carriages long and %d of them have lamps"
			% [GameContent.carriage_locations().size(), _lamps().size()]
	).is_equal(GameContent.carriage_locations().size())


func test_the_lamps_burn_brighter_at_night() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)

	_clock_to(NOON_MINUTES)
	await runner.simulate_frames(4)
	var by_day: Array = _lamps().map(func(e: Dictionary) -> float: return e[&"CLamp"].energy)

	_clock_to(NIGHT_MINUTES)
	await runner.simulate_frames(4)
	var by_night: Array = _lamps().map(func(e: Dictionary) -> float: return e[&"CLamp"].energy)

	for i in range(by_night.size()):
		assert_float(by_night[i]).override_failure_message(
			"carriage %d burns at %f by night and %f by noon" % [i, by_night[i], by_day[i]]
		).is_greater(by_day[i])


## The whole reason it is per carriage. A dark car is somewhere the player cannot see
## what is on the floor, and it has to be one car rather than the train.
func test_one_carriage_can_be_put_out_without_the_rest() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_clock_to(NIGHT_MINUTES)
	await runner.simulate_frames(4)

	var lamps := _lamps()
	var doused: CLamp = lamps[0][&"CLamp"]
	doused.dimming = 0.0
	await runner.simulate_frames(4)

	assert_float(doused.energy).is_equal_approx(0.0, 0.001)
	for i in range(1, lamps.size()):
		assert_float(lamps[i][&"CLamp"].energy).override_failure_message(
			"putting one carriage out took carriage %d with it" % i).is_greater(0.0)


## A flicker is a fault, not a pulse, and either way it is never brighter than the lamp
## and never darker than off.
func test_a_stuttering_lamp_stays_between_off_and_lit() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_clock_to(NIGHT_MINUTES)
	await runner.simulate_frames(4)

	var lamps := _lamps()
	var steady: float = lamps[1][&"CLamp"].energy
	var faulty: CLamp = lamps[0][&"CLamp"]
	faulty.flicker_hz = 7.0
	faulty.flicker_depth = 0.8

	for _frame in range(40):
		await runner.simulate_frames(1)
		assert_float(faulty.energy).is_between(0.0, steady + 0.001)


func test_a_steady_lamp_does_not_wander() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_clock_to(NIGHT_MINUTES)
	await runner.simulate_frames(4)

	var lamp: CLamp = _lamps()[0][&"CLamp"]
	var held := lamp.energy
	await runner.simulate_frames(20)
	assert_float(lamp.energy).override_failure_message(
		"a lamp with no fault drifted from %f to %f" % [held, lamp.energy]
	).is_equal_approx(held, 0.001)
