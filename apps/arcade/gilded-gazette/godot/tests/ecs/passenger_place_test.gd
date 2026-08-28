# GdUnitTestSuite
extends GdUnitTestSuite

## &truth -> a passenger is where the drawn night says, and what they claim is prose in
##           their `alibi` section. The mystery is the two disagreeing, so this system
##           must never read the prose. [TheNight] is tested on its own rules; what is
##           here is that the system hands them to the world faithfully.

var _scope: ECSScope
var _system: SPassengerPlace
var _time: CTimeOfDay
var _night: TheNight


func before_test() -> void:
	_scope = ECSScope.new()
	# &one -> Session owns the only clock. Spawning a second here would leave
	#         view(&"CTimeOfDay")[0] deciding which one the system reads.
	_time = Session.time_of_day
	_time.running = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_night = TheNight.draw(rng, Session.DEPARTURE_MINUTES)
	_system = SPassengerPlace.new()
	_system.departure_minutes = Session.DEPARTURE_MINUTES
	_system.night = _night
	_scope.add_system(&"passenger_place_test", _system)


func after_test() -> void:
	_scope.dispose()
	Session.begin()


func _spawn(content_id: String) -> Dictionary:
	var identity := CIdentity.new()
	identity.content_id = content_id
	var place := CLocation.new()
	var posture := CPosture.new()
	_scope.spawn().add(CPassenger.new()).add(identity).add(place).add(posture)
	return {"place": place, "posture": posture}


func _at(entity: Dictionary, elapsed: int) -> String:
	_time.minutes_past_midnight = (Session.DEPARTURE_MINUTES + elapsed) % 1440
	_system._on_update(0.0)
	return entity["place"].location_id


func test_a_passenger_stands_where_the_night_says() -> void:
	for id: String in ["beaumont", "weiss", "moreau"]:
		var entity := _spawn(id)
		for elapsed in [4 * 60, 7 * 60, 9 * 60]:
			assert_str(_at(entity, elapsed)).override_failure_message(
				"%s was not put where the night placed them at +%d" % [id, elapsed]
			).is_equal(String(_night.where_is(StringName(id), elapsed)))


func test_nobody_is_aboard_before_the_train_leaves() -> void:
	# Boarding is part of the night, so a passenger who has not boarded is nowhere
	# rather than standing in whichever room the content happens to name first.
	var entity := _spawn("weiss")
	assert_str(_at(entity, 0)).is_equal("")


func test_the_victim_is_left_where_it_happened() -> void:
	var entity := _spawn(String(_night.victim_id))
	assert_str(_at(entity, _night.murder_elapsed + 45)).is_equal(String(_night.scene))
	assert_bool(entity["posture"].dead).is_true()


func test_nobody_else_is_ever_put_down() -> void:
	var entity := _spawn(String(_night.culprit_id))
	_at(entity, _night.murder_elapsed + 45)
	assert_bool(entity["posture"].dead).override_failure_message(
		"only the victim's evening ends"
	).is_false()


func test_an_unknown_content_id_is_ignored_rather_than_crashing() -> void:
	assert_str(_at(_spawn("nobody_by_that_name"), 5 * 60)).is_equal("")
