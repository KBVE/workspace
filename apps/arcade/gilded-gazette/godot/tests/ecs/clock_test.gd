# GdUnitTestSuite
extends GdUnitTestSuite

## &pins -> content timelines are authored in minutes past midnight, so the phase
##          to minute mapping is a contract with shared/data, not an internal detail.
## &regression -> _derive truncates, so set_minutes has to aim at the middle of
##                the target minute. Aiming at its edge round-tripped to 16:04
##                when Session asked for 16:05.

var _clock: SClock
var _time: CTimeOfDay
var _scope: ECSScope


func before_test() -> void:
	_scope = ECSScope.new()
	_time = CTimeOfDay.new()
	_scope.spawn().add(_time)
	_clock = SClock.new()
	_scope.add_system(&"clock_test", _clock)


func after_test() -> void:
	_scope.dispose()


func test_every_minute_of_the_day_survives_a_round_trip() -> void:
	for minute in range(1440):
		_clock.set_minutes(_time, minute)
		assert_int(_time.minutes_past_midnight).override_failure_message(
			"set_minutes(%d) came back as %d" % [minute, _time.minutes_past_midnight]
		).is_equal(minute)


func test_the_published_hour_and_minute_are_always_in_range() -> void:
	for step in range(0, 1000):
		_clock.set_phase(_time, step / 1000.0)
		var minutes := _time.minutes_past_midnight
		assert_int(minutes).is_between(0, 1439)
		assert_int(minutes / 60).is_between(0, 23)
		assert_int(minutes % 60).is_between(0, 59)


func test_phase_zero_is_noon_and_phase_half_is_midnight() -> void:
	_clock.set_phase(_time, 0.0)
	assert_int(_time.minutes_past_midnight).is_equal(720)
	assert_float(_time.daylight).is_equal_approx(1.0, 0.001)
	_clock.set_phase(_time, 0.5)
	assert_int(_time.minutes_past_midnight).is_equal(0)
	assert_float(_time.daylight).is_equal_approx(0.0, 0.001)


func test_a_held_clock_does_not_advance() -> void:
	_clock.set_minutes(_time, 8 * 60)
	_time.running = false
	for frame in range(10):
		_clock._on_update(1.0)
	assert_int(_time.minutes_past_midnight).is_equal(8 * 60)


func test_one_real_second_is_one_world_minute_at_the_session_rate() -> void:
	_clock.world_minutes_per_second = 1.0
	_clock.set_minutes(_time, 0)
	for second in range(60):
		_clock._on_update(1.0)
	assert_int(_time.minutes_past_midnight).is_between(59, 61)
