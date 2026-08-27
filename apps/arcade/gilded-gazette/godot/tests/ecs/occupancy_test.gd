# GdUnitTestSuite
extends GdUnitTestSuite

## &pins -> SOccupancy duplicates Consist::carriage_index_at. Consist owns the
##          geometry, the system owns the query, so the two have to agree or the
##          player's carriage disagrees with the carriage they can see.

const PITCH := 21.0
const CARS := 5

var _scope: ECSScope
var _system: SOccupancy


func before_test() -> void:
	_scope = ECSScope.new()
	_system = SOccupancy.new()
	_system.carriage_pitch = PITCH
	_system.carriage_count = CARS
	_scope.add_system(&"occupancy_test", _system)


func after_test() -> void:
	_scope.dispose()


func test_the_index_matches_consist_at_every_position() -> void:
	var consist: Consist = auto_free(Consist.new())
	consist.carriage_count = CARS
	consist.pitch = PITCH
	var viewer := CViewer.new()
	var occupant := COccupant.new()
	_scope.spawn().add(viewer).add(occupant).add(CLocation.new())

	for step in range(-60, 61):
		viewer.world_x = step * 2.0
		_system._on_update(0.0)
		assert_int(occupant.carriage_index).override_failure_message(
			"at x=%.1f the system said %d and Consist said %d"
			% [viewer.world_x, occupant.carriage_index, consist.carriage_index_at(viewer.world_x)]
		).is_equal(consist.carriage_index_at(viewer.world_x))


func test_the_index_clamps_to_the_ends_of_the_train() -> void:
	var viewer := CViewer.new()
	var occupant := COccupant.new()
	_scope.spawn().add(viewer).add(occupant).add(CLocation.new())
	viewer.world_x = -10000.0
	_system._on_update(0.0)
	assert_int(occupant.carriage_index).is_equal(0)
	viewer.world_x = 10000.0
	_system._on_update(0.0)
	assert_int(occupant.carriage_index).is_equal(CARS - 1)


func test_the_room_comes_from_the_carriage_standing_there() -> void:
	var here := CLocation.new()
	var occupant := COccupant.new()
	var viewer := CViewer.new()
	_scope.spawn().add(viewer).add(occupant).add(here)
	for index in range(CARS):
		var carriage := CCarriage.new()
		carriage.index = index
		var room := CLocation.new()
		room.location_id = &"room_%d" % index
		_scope.spawn().add(carriage).add(room)

	viewer.world_x = 0.0
	_system._on_update(0.0)
	assert_str(here.location_id).is_equal("room_%d" % occupant.carriage_index)


func test_a_carriage_with_no_room_reports_empty_rather_than_failing() -> void:
	var here := CLocation.new()
	var viewer := CViewer.new()
	_scope.spawn().add(viewer).add(COccupant.new()).add(here)
	viewer.world_x = 0.0
	_system._on_update(0.0)
	assert_str(here.location_id).is_equal("")
