extends ECSSystem
class_name SOccupancy

## SOccupancy resolves a viewer's world position to a carriage and the room that
## carriage stands in for. Pure arithmetic, so it could run on the scheduler; one
## division is not worth dispatching to the worker pool.
##
## Mirrors Consist::carriage_index_at, so the spacing is handed over.

var carriage_pitch: float = 21.0
var carriage_count: int = 1

## What each viewer was last reported as, by entity. Keyed rather than held as one
## pair, because one pair is one viewer's worth of memory: a second viewer -- a
## spectator, a replay, the debug camera -- would have its own crossings swallowed by
## the first one's, and the panel would report whichever of them moved last.
var _published: Dictionary = {}

func _on_update(_delta: float) -> void:
	var last_index := carriage_count - 1
	var rooms := _rooms_by_car()
	for entry: Dictionary in multi_view([CViewer, COccupant, CLocation]):
		var world_x: float = entry[&"CViewer"].world_x
		var index := clampi(int(round(world_x / carriage_pitch + last_index / 2.0)), 0, last_index)
		entry[&"COccupant"].carriage_index = index
		entry[&"CLocation"].location_id = rooms.get(index, &"")
		_publish(entry["entity"].get_instance_id(), entry[&"COccupant"],
			entry[&"CLocation"])


## Walking the aisle crosses a carriage boundary a few times a run, so this is a
## handful of events, not a per-frame stream.
func _publish(who: int, occupant: COccupant, here: CLocation) -> void:
	var was: Array = _published.get(who, [-1, &"\uffff"])
	if occupant.carriage_index == was[0] and here.location_id == was[1]:
		return
	_published[who] = [occupant.carriage_index, here.location_id]
	notify(GameEvents.VIEWER_STATE, {
		"carriage": occupant.carriage_index,
		"location": String(here.location_id),
	})


func _rooms_by_car() -> Dictionary:
	var by_car := {}
	for entry: Dictionary in multi_view([CCarriage, CLocation]):
		by_car[entry[&"CCarriage"].index] = entry[&"CLocation"].location_id
	return by_car
