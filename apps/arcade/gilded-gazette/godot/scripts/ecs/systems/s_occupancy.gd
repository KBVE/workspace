extends ECSSystem
class_name SOccupancy

## SOccupancy resolves a viewer's world position to a carriage and the room that
## carriage stands in for. Pure arithmetic, so it could run on the scheduler; one
## division is not worth dispatching to the worker pool.
##
## Mirrors Consist::carriage_index_at, so the spacing is handed over.

var carriage_pitch: float = 21.0
var carriage_count: int = 1

var _last_published_carriage: int = -1
var _last_published_location: StringName = &"\uffff"

func _on_update(_delta: float) -> void:
	var last_index := carriage_count - 1
	var rooms := _rooms_by_car()
	for entry: Dictionary in multi_view([CViewer, COccupant, CLocation]):
		var world_x: float = entry[&"CViewer"].world_x
		var index := clampi(int(round(world_x / carriage_pitch + last_index / 2.0)), 0, last_index)
		entry[&"COccupant"].carriage_index = index
		entry[&"CLocation"].location_id = rooms.get(index, &"")
		_publish(entry[&"COccupant"], entry[&"CLocation"])


## Walking the aisle crosses a carriage boundary a few times a run, so this is a
## handful of events, not a per-frame stream.
func _publish(occupant: COccupant, here: CLocation) -> void:
	if occupant.carriage_index == _last_published_carriage \
			and here.location_id == _last_published_location:
		return
	_last_published_carriage = occupant.carriage_index
	_last_published_location = here.location_id
	notify(GameEvents.VIEWER_STATE, {
		"carriage": occupant.carriage_index,
		"location": String(here.location_id),
	})


func _rooms_by_car() -> Dictionary:
	var by_car := {}
	for entry: Dictionary in multi_view([CCarriage, CLocation]):
		by_car[entry[&"CCarriage"].index] = entry[&"CLocation"].location_id
	return by_car
