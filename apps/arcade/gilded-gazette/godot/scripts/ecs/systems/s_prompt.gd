extends ECSSystem
class_name SPrompt

## SPrompt works out what the interaction key would do if it were pressed now.
##
## The order is the order the systems themselves run in: a notice is read before a
## bench is taken and a bench before a door is opened, because that is what [SNotice],
## [SSeating] and [SDoor] do with a press when more than one of them could answer it.
## A label that guessed differently would be wrong exactly when it mattered, which is
## standing at the bench nearest the door.
##
## The refusals are the same tests the systems make, called where they are: a locked
## door, a taken bench, a leaf that cannot shut because somebody is standing in its way.
## What it must never do is decide any of it: this is a report.

func _on_update(_delta: float) -> void:
	for entry: Dictionary in multi_view([CPrompt, CPointer, CSeating, CLocomotion,
			ECSViewComponent]):
		var body: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if body == null:
			continue
		_read(entry[&"CPrompt"], entry[&"CPointer"], entry[&"CSeating"],
			body.global_position)


func _read(prompt: CPrompt, pointer: CPointer, seating: CSeating,
		standing_at: Vector3) -> void:
	prompt.action = CPrompt.NOTHING
	prompt.refusal = CPrompt.NOTHING
	prompt.within_reach = false
	prompt.under_the_pointer = false

	# Sitting outranks everything, because a seated player has only one thing to do
	# with the key and pressing it while pointing at a door should not open the door
	# from a bench.
	if seating.seated:
		prompt.action = CPrompt.STAND_UP
		prompt.within_reach = true
		return

	if pointer.notice != null:
		prompt.action = CPrompt.READ_IT
		prompt.under_the_pointer = true
		prompt.within_reach = true
		return

	if _offer_a_seat(prompt, pointer, seating, standing_at):
		return
	_offer_a_door(prompt, pointer, standing_at)


## A bench, pointed at or stood beside. [SSeating] takes the nearest free one on a press
## and the pointed one on a click, so both are offered and the refusal is the same
## either way: somebody is in it.
func _offer_a_seat(prompt: CPrompt, pointer: CPointer, seating: CSeating,
		standing_at: Vector3) -> bool:
	# The free one first, because that is the one [SSeating] would answer with. Only
	# when there is nothing free within reach does the nearest taken bench get named,
	# and then it is named to say it is taken: a player standing at a full row was
	# being told nothing at all, which reads as a bench that does not work.
	var near := _nearest_seat(seating, standing_at, true)
	if near == null:
		near = _nearest_seat(seating, standing_at, false)
	var seat: CSeat = pointer.seat if pointer.seat != null else near
	if seat == null:
		return false
	prompt.action = CPrompt.SIT_DOWN
	prompt.under_the_pointer = pointer.seat != null
	prompt.within_reach = near != null and (pointer.seat == null or pointer.seat == near)
	if not seat.free_to_take():
		prompt.refusal = CPrompt.TAKEN
	return true


## Nearest free bench within arm's length, which is the one [SSeating] would answer a
## press with. Flat, as it measures it: the eye is a metre above the cushion and that
## metre is not a reason to be out of reach of a bench you are standing beside.
func _nearest_seat(seating: CSeating, standing_at: Vector3, free_only: bool) -> CSeat:
	var found: CSeat = null
	var nearest := seating.reach_metres
	for seat: CSeat in view(&"CSeat"):
		if free_only and not seat.free_to_take():
			continue
		var away := Vector2(standing_at.x - seat.at.x, standing_at.z - seat.at.z).length()
		if away < nearest:
			nearest = away
			found = seat
	return found


func _offer_a_door(prompt: CPrompt, pointer: CPointer, standing_at: Vector3) -> void:
	var leaf: Node3D = pointer.door_leaf
	var door: CDoor = pointer.door
	var pointed := door != null
	if door == null:
		var near := _nearest_door(standing_at)
		if near.is_empty():
			return
		door = near[&"CDoor"]
		leaf = near[&"ECSViewComponent"].view as Node3D

	prompt.under_the_pointer = pointed
	prompt.within_reach = leaf != null \
		and SDoor.reach_to(leaf, standing_at) <= door.reach_metres
	prompt.action = CPrompt.SHUT_THE_DOOR if door.is_open else CPrompt.OPEN_THE_DOOR
	if door.is_locked:
		prompt.refusal = CPrompt.LOCKED
		return
	if not door.is_open:
		return
	# Two ways a shut is refused, and neither of them is the door's fault. Standing in
	# the opening is [SDoor]'s own rule; a leaf being held by somebody walking through
	# it is [SDoorTraffic]'s, and it outlasts the press.
	if leaf != null and SDoor.standing_in_the_doorway(leaf, standing_at):
		prompt.refusal = CPrompt.IN_THE_DOORWAY
	elif door.held_open_by > 0:
		prompt.refusal = CPrompt.HELD_OPEN


func _nearest_door(standing_at: Vector3) -> Dictionary:
	var found: Dictionary = {}
	var nearest := INF
	for entry: Dictionary in multi_view([CDoor, ECSViewComponent]):
		var leaf: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if leaf == null:
			continue
		var away := SDoor.reach_to(leaf, standing_at)
		if away <= entry[&"CDoor"].reach_metres and away < nearest:
			nearest = away
			found = entry
	return found
