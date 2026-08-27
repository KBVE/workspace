extends ECSSystem
class_name SDoor

## SDoor answers [F] with the nearest door, and drives every leaf's swing.
##
## The reach test is done here rather than by an Area3D per door because the doors
## are children of carriages that get hidden as the player walks away: a hidden
## Area3D still reports overlaps, so proximity would have to be filtered anyway, and
## a distance against a handful of doors is cheaper than the bodies would be.
##
## Only the nearest door in reach answers, so standing in a vestibule between two
## cars opens the one being looked at rather than both.

## Half a person, near enough. What the leaf has to clear to swing past somebody
## rather than into them.
const SHOULDER_METRES := 0.45

func _on_update(delta: float) -> void:
	var asked := false
	var standing_at := Vector3.ZERO
	var pointed_at: CDoor = null
	for entry: Dictionary in multi_view([CInput, CLocomotion, CPointer, ECSViewComponent]):
		var body: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if body == null:
			continue
		var intent: CInput = entry[&"CInput"]
		var pointer: CPointer = entry[&"CPointer"]
		standing_at = body.global_position
		# [G] as well as [F], because the last bench in a row stands within arm's reach
		# of the end door and [F] is answered by the bench first. With one key the door
		# is simply unreachable from there.
		asked = intent.interact_requested or intent.secondary_requested
		if intent.pointer_clicked and pointer.door != null:
			pointed_at = pointer.door
			intent.pointer_clicked = false
		break

	var nearest: Dictionary = {}
	var nearest_distance := INF
	for entry: Dictionary in multi_view([CDoor, ECSViewComponent]):
		var leaf: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if leaf == null:
			continue
		var door: CDoor = entry[&"CDoor"]
		_swing(door, leaf, delta)
		# a clicked door answers wherever it is standing: pointing at it is already
		# the unambiguous half of this, and making it also be within arm's reach would
		# throw that away
		if door == pointed_at:
			_answer(door, leaf, standing_at, 0.0)
			continue
		if not asked:
			continue
		var distance := reach_to(leaf, standing_at)
		if distance <= door.reach_metres and distance < nearest_distance:
			nearest_distance = distance
			nearest = entry

	if nearest.is_empty():
		return
	_answer(nearest[&"CDoor"], nearest[&"ECSViewComponent"].view as Node3D,
		standing_at, nearest_distance)


## Reports the attempt either way. A locked door that says nothing is
## indistinguishable from one the player failed to reach.
func _answer(door: CDoor, leaf: Node3D, standing_at: Vector3, distance: float) -> void:
	if not door.is_locked:
		if not door.is_open:
			door.swing_sign = _away_from(leaf, standing_at)
			door.is_open = true
		elif not standing_in_the_doorway(leaf, standing_at):
			door.is_open = false
	notify(GameEvents.DOOR_STATE, {
		"open": door.is_open,
		"locked": door.is_locked,
		"distance": snappedf(distance, 0.01),
	})


## Moves the leaf toward wherever the door should be, which is open if the player left
## it that way or if somebody is walking through it.
func _swing(door: CDoor, leaf: Node3D, delta: float) -> void:
	var wants := 1.0 if (door.is_open or door.held_open_by > 0) else 0.0
	if is_equal_approx(door.swing, wants):
		return
	door.swing = move_toward(door.swing, wants,
		delta / maxf(door.seconds_to_swing, 0.0001))
	# smoothstep, so the leaf eases into the stop instead of arriving at full speed
	# and halting on the frame it lands
	var eased: float = door.swing * door.swing * (3.0 - 2.0 * door.swing)
	leaf.rotation.y = eased * door.open_radians * door.swing_sign


## Which way the leaf has to turn to move away from [param standing_at].
##
## A door that opens into the person opening it shoves them down the aisle, because
## the leaf is a static body sweeping through where they are standing. Real carriage
## doors pick a side and live with it; a game door should get out of the way.
##
## Positive rotation carries the leaf toward its own local -X, so somebody on the +X
## side is escaped by turning positive, and the reverse.
func _away_from(leaf: Node3D, standing_at: Vector3) -> float:
	return 1.0 if leaf.to_local(standing_at).x > 0.0 else -1.0


## How far [param standing_at] is from a leaf, for reach.
##
## Flat, the way [SSeating] and [SDoorTraffic] both measure theirs. A leaf is measured
## from its hinge on the floor and a player from their eyes, so somebody standing a
## stride from a door is also a metre and a half above it: taken in three dimensions a
## [member CDoor.reach_metres] of 2.2 was really 1.5 metres of floor, and a door within
## arm's length reported itself out of reach.
static func reach_to(leaf: Node3D, standing_at: Vector3) -> float:
	return Vector2(leaf.global_position.x - standing_at.x,
		leaf.global_position.z - standing_at.z).length()


## Whether [param standing_at] is inside the opening the leaf would shut into.
##
## Opening cannot trap anybody, because the leaf is sent away from them. Shutting
## can: stand in the doorway with the door open, press the key, and the leaf swings
## back through you and wedges you against the frame. So it does not.
##
## Measured in the parent's frame, which does not turn with the leaf, and against
## the leaf's own bounds so the opening is whatever the door is wide.
static func standing_in_the_doorway(leaf: Node3D, standing_at: Vector3) -> bool:
	var parent := leaf.get_parent() as Node3D
	var visual := leaf as VisualInstance3D
	if parent == null or visual == null:
		return false
	var box := visual.get_aabb()
	var here := parent.to_local(standing_at) - leaf.position
	var across := here.z - (box.position.z + box.size.z * 0.5)
	return absf(here.x) < SHOULDER_METRES and absf(across) < box.size.z * 0.5
