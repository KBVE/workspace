extends ECSSystem
class_name SCastBody

## SCastBody is the seam between where a passenger is and whether anyone can see them.
##
## Anything with a place and a face is built, passenger or not. The cast move on their
## timelines; the escort in the guard's van never moves at all, and neither needs to
## know the other exists.
##
## [SPassengerPlace] decides where the passengers are, always, from their timeline. Almost
## none of that is on screen: the player stands in one carriage and [Consist] draws two
## either side. So a passenger owns a [CharacterRig] only while their carriage is drawn,
## and the moment it is culled the rig goes with it.
##
## Assembling one rig is five glb instantiations and a graft each, which is a frame the
## player feels. [constant BUILDS_PER_TICK] spreads that out, and is the number that
## decides how large the cast can grow: doubling the passengers costs one more tick of
## catching up, not one more spike.

## Rigs built per tick, at most. One is enough to keep up with a walking player and
## small enough to hide inside a frame.
const BUILDS_PER_TICK := 1

## Metres either side of a carriage centre a passenger can be placed, so five of them
## in one carriage do not stand in a heap.
const PLACEMENT_SPREAD := 7.0

## Where the eyes sit up a body, as a share of its height. Measured off the pack's own
## rigs, which put them in the same place in every body it ships: 1.70 of an unscaled
## 1.8141. Used rather than the rig's own measurement because a station is wanted for
## characters who have no rig yet, and most of them never will.
const EYE_FRACTION_OF_STATURE := 0.937

var carriage_pitch: float = 21.0
var carriage_count: int = 1

## Carriages either side of the viewer that hold a rig. Matches Consist.mesh_window, or
## passengers pop in inside a carriage that is already drawn.
var carriage_window: int = 2

## How tall a passenger stands. The rig scales to reach it and their eyes land where
## that puts them, the same way the player's does.
## What a passenger stands at when their appearance does not say. Everyone rolled or
## authored carries their own height, so this is only ever a fallback.
var stature_metres: float = 1.75
var floor_height_metres: float = 0.0

## How far off the middle of the aisle anybody may stand, shoulders included. Set from
## the carriage: the benches begin at [constant Consist.SEAT_EDGE_Z], and a station
## outside this is a passenger standing inside the seating.
var aisle_half_width: float = 0.3

## The rig's yaw offset, the same quarter turn the player's takes.
var forward_yaw_offset_radians: float = -PI * 0.5

## What built rigs are parented to. Freed with the scene, which is why nothing here
## outlives one.
var cast_root: Node3D

## Location id to carriage index, from the authored locations. Built once: the consist
## does not change shape mid-run.
var _carriage_of: Dictionary = {}

func _on_update(_delta: float) -> void:
	if cast_root == null:
		return
	if _carriage_of.is_empty():
		_map_carriages()

	var here := _viewer_carriage()
	var built := 0
	for entry: Dictionary in multi_view([CLocation, CAppearance, CCharacterRig, CErrand]):
		var rig_slot: CCharacterRig = entry[&"CCharacterRig"]
		var errand: CErrand = entry[&"CErrand"]
		# A character on rounds says where they are; everybody else is told. It is where
		# they have walked to that counts, not where they set off for: a conductor who
		# announced the dining car as he left the guard's van would be an alibi for a
		# room he had not reached.
		if not errand.beat.is_empty():
			entry[&"CLocation"].location_id = _room_at(errand.at.x)
		var carriage: int = _carriage_of.get(entry[&"CLocation"].location_id, -1)
		if not errand.beat.is_empty():
			carriage = _carriage_of.get(errand.beat[errand.beat_index], carriage)
		_station(errand, entry[&"CAppearance"], carriage)
		var within_the_drawn_window := carriage >= 0 and here >= 0 \
			and absi(carriage - here) <= carriage_window

		var rig := rig_slot.live()
		if not within_the_drawn_window:
			if rig != null:
				rig.queue_free()
				rig_slot.rig = null
			continue
		if rig != null:
			continue
		if built >= BUILDS_PER_TICK:
			continue
		rig_slot.rig = _build(entry[&"CAppearance"], errand)
		built += 1


## Their carriage, or -1 while nobody is aboard yet.
func _viewer_carriage() -> int:
	var occupants: Array = view(&"COccupant")
	return occupants[0].carriage_index if not occupants.is_empty() else -1


## The room whoever stands at [param world_x] is standing in. Mirrors the arithmetic in
## [method Consist.carriage_index_at], which is the same reason [SOccupancy] carries a
## copy: the spacing is handed over rather than the consist.
func _room_at(world_x: float) -> StringName:
	var aboard := GameContent.carriage_locations()
	if aboard.is_empty():
		return &""
	var index := clampi(int(round(world_x / carriage_pitch + (carriage_count - 1) / 2.0)),
		0, aboard.size() - 1)
	return aboard[index]


func _map_carriages() -> void:
	var aboard := GameContent.carriage_locations()
	for i in range(aboard.size()):
		_carriage_of[aboard[i]] = i


func _build(appearance: CAppearance, errand: CErrand) -> CharacterRig:
	var rig := CharacterRig.from_appearance(appearance)
	rig.stature_metres = appearance.stature_metres
	rig.floor_height_metres = floor_height_metres
	rig.forward_yaw_offset_radians = forward_yaw_offset_radians
	cast_root.add_child(rig)
	# Wherever the walk has got to, which is not where it set off: a passenger who
	# crossed two carriages unwatched is met halfway rather than at the door.
	rig.position = errand.at
	rig.rotation.y = errand.facing_radians
	return rig


## Where in the room they belong, and how high off the floor their eyes are.
##
## Rewritten every tick because the room changes underneath them: [SPassengerPlace]
## moves a passenger by rewriting their [CLocation], and this is what turns that into
## somewhere for [SCastWalk] to take them.
##
## The spot is off their own seed, so a passenger is found where they were left every
## time their carriage is walked back into, and two of them in one room do not stand in
## the same place as each other.
func _station(errand: CErrand, appearance: CAppearance, carriage: int) -> void:
	if carriage < 0:
		return
	if errand.assigned:
		# Somebody has decided where this one belongs: a bench, in [SPastime]'s case.
		# The seeded spot is what a passenger gets when nobody has.
		errand.station = errand.assigned_station
		errand.resting_facing_radians = errand.assigned_facing
		errand.stationed = true
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = appearance.character_seed
	var along := (carriage - (carriage_count - 1) / 2.0) * carriage_pitch \
		+ rng.randf_range(-PLACEMENT_SPREAD, PLACEMENT_SPREAD) + errand.station_offset_metres
	# In the aisle, never in a bench. Which side of the centre line they favour is theirs
	# and stays theirs, so two passengers in one carriage are not standing in each other.
	var side := rng.randf_range(0.35, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	var off_centre := side * aisle_half_width
	errand.station = Vector3(along,
		floor_height_metres + appearance.stature_metres * EYE_FRACTION_OF_STATURE, off_centre)
	# Turned to the seats they are standing beside rather than down the train, which is
	# what makes somebody waiting look like somebody waiting.
	errand.resting_facing_radians = SCastWalk.facing_for(
		Vector3(0.0, 0.0, -signf(off_centre)), forward_yaw_offset_radians)
	if errand.stationed:
		return
	# First time only. Everybody starts standing where they belong; after that they
	# walk to it, because it is the room that moves and not them.
	errand.at = errand.station
	errand.facing_radians = errand.resting_facing_radians
	errand.stationed = true


## Systems are freed with the scene that added them, and a rig that outlived its slot
## would leave a component pointing at a freed node.
func _exit_tree() -> void:
	if _world == null:
		return
	for entry: Dictionary in multi_view([CAppearance, CCharacterRig]):
		var rig_slot: CCharacterRig = entry[&"CCharacterRig"]
		var rig := rig_slot.live()
		if rig != null:
			rig.queue_free()
			rig_slot.rig = null
