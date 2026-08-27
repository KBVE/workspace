extends ECSSystem
class_name SDoorTraffic

## SDoorTraffic opens the doors for everybody who is not the player.
##
## The player asks with [F] and [SDoor] answers. Nobody else has hands to ask with, so
## a door in front of a walking character opens because they are walking through it and
## shuts once they are not.
##
## Recounted from nothing every tick rather than incremented and decremented. A rig is
## thrown away the moment its carriage stops being drawn, and a count that survived that
## would leave a door standing open on a character who no longer exists.
##
## A character standing still does not hold anything, and neither does one walking away
## from a door or past it. Both matter for the escort: they pace a few metres of the
## guard's van all night, and on distance alone the end door flapped every time one of
## them turned round at that end of their beat.

## How close a walking character has to be for the door to answer them. Wider than the
## player's own reach, because a door that opens as it is arrived at has already been
## walked into.
const HOLD_METRES := 3.4

## Below this they count as standing rather than walking.
const WALKING_METRES_PER_SECOND := 0.05

## How far past where they are going a door still counts as being on the way there.
## A stride, so a character whose destination is the doorway itself opens it, and one
## whose beat merely ends near a door does not.
const PAST_THE_DESTINATION_METRES := 0.6

## How far to the side of the line they are walking a door can sit and still be in the
## way. The aisle is two metres across, so anything wider than this is a door in the
## other half of the vestibule.
const ASIDE_METRES := 1.4

func _on_update(_delta: float) -> void:
	# Where each walker is and which way they are pointed, gathered once: the doors are
	# walked for every one of them, and the facing is what tells a door being used from
	# a door being stood beside.
	var walkers: Array[Dictionary] = []
	for entry: Dictionary in multi_view([CErrand, CLocomotion]):
		var errand: CErrand = entry[&"CErrand"]
		if not errand.stationed:
			continue
		# A patrol is not going anywhere. Their beat ends a stride or two short of the
		# van door and the geometry alone cannot tell that from a passenger whose walk
		# ends at the doorway, so what settles it is that one of them has a destination
		# beyond the door and the other is walking back and forth in front of it.
		if errand.patrol_metres > 0.0:
			continue
		var locomotion: CLocomotion = entry[&"CLocomotion"]
		var speed := Vector2(locomotion.forward_metres_per_second,
			locomotion.strafe_metres_per_second).length()
		if speed > WALKING_METRES_PER_SECOND:
			walkers.append({"at": errand.at, "to": errand.target})

	for entry: Dictionary in multi_view([CDoor, ECSViewComponent]):
		var leaf: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if leaf == null:
			continue
		var door: CDoor = entry[&"CDoor"]
		door.held_open_by = 0
		for walker: Dictionary in walkers:
			if _is_in_the_way(leaf.global_position, walker["at"], walker["to"]):
				door.held_open_by += 1


## Whether a door stands on the stretch between somebody and where they are going.
##
## Distance alone is not enough, and neither is which way they are pointed. The escort
## pace a few metres of the guard's van, and by both of those measures they are walking
## at its end door every time they turn round at that end of the beat. What tells the
## two apart is that their beat stops short of the door and a passenger's walk goes
## through it.
##
## Height is left out of it throughout: a leaf is measured from its hinge at the floor
## and a character from their eyes, and the two are never level.
static func _is_in_the_way(leaf_at: Vector3, walker_at: Vector3, walking_to: Vector3) -> bool:
	var toward := Vector2(leaf_at.x - walker_at.x, leaf_at.z - walker_at.z)
	if toward.length() > HOLD_METRES:
		return false
	var journey := Vector2(walking_to.x - walker_at.x, walking_to.z - walker_at.z)
	if journey.length() < 0.01:
		return false
	var along := journey.normalized()
	var ahead := toward.dot(along)
	if ahead <= 0.0 or ahead > journey.length() + PAST_THE_DESTINATION_METRES:
		return false
	return absf(toward.dot(Vector2(-along.y, along.x))) <= ASIDE_METRES
