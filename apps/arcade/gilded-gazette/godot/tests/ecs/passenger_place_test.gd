# GdUnitTestSuite
extends GdUnitTestSuite

## &truth -> a passenger's timeline is where they ACTUALLY were. What they claim
##           is prose in their `alibi` section. The mystery is the two disagreeing,
##           so this system must never read the prose.

var _scope: ECSScope
var _system: SPassengerPlace
var _time: CTimeOfDay


func before_test() -> void:
	_scope = ECSScope.new()
	# &one -> Session owns the only clock. Spawning a second here would leave
	#         view(&"CTimeOfDay")[0] deciding which one the system reads.
	_time = Session.time_of_day
	_time.running = false
	_system = SPassengerPlace.new()
	_system.departure_minutes = Session.DEPARTURE_MINUTES
	_scope.add_system(&"passenger_place_test", _system)


func after_test() -> void:
	_scope.dispose()
	Session.begin()


func _place(content_id: String, minutes: int) -> String:
	var identity := CIdentity.new()
	identity.content_id = content_id
	var place := CLocation.new()
	_scope.spawn().add(CPassenger.new()).add(identity).add(place)
	_time.minutes_past_midnight = minutes
	_system._on_update(0.0)
	return place.location_id


func test_a_passenger_stands_where_their_timeline_says() -> void:
	assert_str(_place("dupont", 20 * 60 + 15)).is_equal("dining")
	assert_str(_place("thompson", 22 * 60 + 30)).is_equal("cabin")
	assert_str(_place("carrow", 21 * 60 + 50)).is_equal("corridor")


func test_a_timeline_step_holds_until_the_next_one() -> void:
	assert_str(_place("beaumont", 20 * 60 + 31)).is_equal("corridor")
	assert_str(_place("beaumont", 23 * 60 + 39)).is_equal("corridor")
	assert_str(_place("beaumont", 23 * 60 + 41)).is_equal("cabin")


func test_the_journey_crosses_midnight() -> void:
	assert_str(_place("weiss", 23 * 60 + 59)).is_equal("dining")
	assert_str(_place("weiss", 0 * 60 + 21)).override_failure_message(
		"00:20 comes AFTER 23:40 on this journey even though it is the smaller number"
	).is_equal("corridor")


func test_an_unknown_content_id_is_ignored_rather_than_crashing() -> void:
	assert_str(_place("nobody_by_that_name", 20 * 60)).is_equal("")


func test_every_authored_passenger_resolves_to_an_authored_location() -> void:
	var known := GameContent.locations().map(func(l: Dictionary) -> String: return l["id"])
	for passenger: Dictionary in GameContent.passengers():
		for minutes in [19 * 60, 21 * 60, 23 * 60, 0 * 60 + 30]:
			var where := _place(passenger["id"], minutes)
			assert_array(known).override_failure_message(
				"%s resolved to '%s' at %02d:%02d, which is not a shared/data/locations id"
				% [passenger["id"], where, minutes / 60, minutes % 60]
			).contains([where])


func test_a_passenger_is_nowhere_before_they_board() -> void:
	assert_str(_place("beaumont", 16 * 60 + 30)).override_failure_message(
		"Lady Beaumont boards at 18:15; before that where_was() reads the clock as "
		+ "the following day and puts her in the cabin she ends the night in"
	).is_equal("")
	assert_str(_place("beaumont", 18 * 60 + 20)).is_equal("platform")


func test_dupont_boards_first_and_is_aboard_from_departure() -> void:
	assert_str(_place("dupont", 16 * 60 + 30)).is_not_equal("")
