extends ECSSystem
class_name SCastWalk

## SCastWalk walks everyone the player does not.
##
## The movement is arithmetic, not physics: a passenger has no [CharacterBody3D] and
## wants none. What the aisle needs is a line down the middle of it, and putting five
## capsules in a corridor two metres wide buys nothing but a bill for the collisions
## between them.
##
## It runs whether or not a rig exists, because [CErrand.at] is where the character is
## and the rig is only what that looks like. A conductor who walked only while watched
## would arrive at the dining car the moment the player turned to look down the train.
##
## The speeds it writes into [CLocomotion] are the ones actually covered, so a character
## held up by a shut door has legs that stop with them.

## Half a pair of shoulders. What the aisle has to keep clear of the benches for a body
## walking down the middle of it not to be inside one.
const SHOULDER_METRES := 0.25

## How far ahead somebody coming the other way is worth stepping aside for. Much less
## and they are already on top of each other; much more and a passenger sidles the
## length of a carriage for somebody who turns off before reaching them.
const MAKE_ROOM_METRES := 2.6

## How much of the aisle to give up when passing. Two of them at this offset walk past
## each other with a shoulder's width between, which is what a corridor this narrow has
## to offer.
const PASSING_SHARE := 0.85

## How far off the centre line of the aisle a walk may wander, shoulders included.
## Written by [Train] off the seating, because the benches decide where the aisle ends.
var aisle_half_width: float = 0.3

func _on_update(delta: float) -> void:
	# Gathered once and reused: everybody has to be able to see everybody, and the walk
	# is over before the next tick redraws the picture.
	var traffic: Array[Dictionary] = []
	for entry: Dictionary in multi_view([CErrand, CLocomotion]):
		var errand: CErrand = entry[&"CErrand"]
		if errand.stationed:
			traffic.append({"at": errand.at, "to": errand.target})

	for entry: Dictionary in multi_view([CErrand, CLocomotion, CGait, CCharacterRig]):
		_step(entry[&"CErrand"], entry[&"CLocomotion"], entry[&"CCharacterRig"].live(),
			traffic, delta)


func _step(errand: CErrand, locomotion: CLocomotion, rig: CharacterRig,
		traffic: Array[Dictionary], delta: float) -> void:
	if not errand.stationed:
		return
	_choose_target(errand, delta)

	var was_at := errand.at
	var wanted := _walk_to(errand, locomotion, traffic)
	var step := wanted - errand.at
	step.y = 0.0
	if step.length() > errand.arrive_metres:
		errand.at += step.normalized() * minf(
			errand.walk_metres_per_second * delta, step.length())
		_turn_toward(errand, step.normalized(), locomotion, delta)
	else:
		errand.at.x = wanted.x
		errand.at.z = wanted.z
		_turn_to(errand, errand.resting_facing_radians, locomotion, delta)
	errand.at.y = errand.target.y

	_report_speed(errand, locomotion, errand.at - was_at, delta)
	if rig != null:
		rig.position = errand.at
		rig.rotation.y = errand.facing_radians


## The point actually walked at, which is not the destination until the last stride.
##
## The length of the carriage is walked in the aisle and the step out of it happens on
## arrival. Cutting the corner instead would take a passenger diagonally through three
## rows of benches, which is what the seats are: mesh with collision the cast do not use.
func _walk_to(errand: CErrand, locomotion: CLocomotion,
		traffic: Array[Dictionary]) -> Vector3:
	var to_go := errand.target.x - errand.at.x
	if absf(to_go) <= errand.arrive_metres:
		return errand.target
	var lane := clampf(_make_room_for_oncoming(errand, locomotion, traffic),
		-aisle_half_width, aisle_half_width)
	return Vector3(errand.target.x, errand.target.y, lane)


## Which side of the aisle to walk down. The middle, until somebody is coming the other
## way, and then their own right: two characters each giving way to their right pass
## rather than walk through one another, and neither has to be told which is which.
func _make_room_for_oncoming(errand: CErrand, locomotion: CLocomotion,
		traffic: Array[Dictionary]) -> float:
	return room_for_oncoming(errand.at, errand.target,
		SLocomotion.right_of(locomotion).z, traffic, aisle_half_width)


## Written as arithmetic on plain values rather than on the components, because what it
## decides is worth being able to state a case to directly: two walkers, this far apart,
## going these ways, should or should not step aside.
##
## [param right_z] is which way the walker's own right points along the carriage. Both
## halves of a meeting compute it for themselves and come out on opposite sides.
static func room_for_oncoming(at: Vector3, target: Vector3, right_z: float,
		traffic: Array[Dictionary], aisle_half_width: float) -> float:
	var going := signf(target.x - at.x)
	if is_zero_approx(going):
		return 0.0
	for other: Dictionary in traffic:
		var them: Vector3 = other["at"]
		var gap := them.x - at.x
		if absf(gap) > MAKE_ROOM_METRES or is_zero_approx(gap):
			continue
		# Ahead of them, and headed back this way. Somebody overtaken from behind is not
		# a collision anybody has to solve in a corridor with one speed in it.
		if signf(gap) != going:
			continue
		var theirs: Vector3 = other["to"]
		if signf(theirs.x - them.x) == going:
			continue
		return right_z * aisle_half_width * PASSING_SHARE
	return 0.0


## A patrol turns round at each end and waits a moment before setting off again.
## Everyone else is going where their room is, which [SCastBody] has already written
## into the station.
func _choose_target(errand: CErrand, delta: float) -> void:
	if not errand.beat.is_empty():
		_walk_the_beat(errand, delta)
		return
	if errand.patrol_metres <= 0.0:
		errand.target = errand.station
		return
	var reach := errand.patrol_metres * 0.5
	var end := errand.station + Vector3(reach if errand.patrol_outbound else -reach, 0.0, 0.0)
	if errand.at.distance_to(end) > errand.arrive_metres:
		errand.target = end
		return
	if errand.pausing_seconds <= 0.0:
		errand.pausing_seconds = errand.patrol_pause_seconds
	errand.pausing_seconds -= delta
	errand.target = end
	if errand.pausing_seconds <= 0.0:
		errand.patrol_outbound = not errand.patrol_outbound


## Rounds: arrive in a room, stand in it a moment, then set off for the next. The room
## itself is [SCastBody]'s business -- it is what turns a room into somewhere to stand --
## so all that happens here is the counting.
func _walk_the_beat(errand: CErrand, delta: float) -> void:
	errand.target = errand.station
	if errand.at.distance_to(errand.station) > errand.arrive_metres:
		errand.pausing_seconds = errand.beat_pause_seconds
		return
	errand.pausing_seconds -= delta
	if errand.pausing_seconds > 0.0:
		return
	errand.pausing_seconds = errand.beat_pause_seconds
	errand.beat_index = (errand.beat_index + 1) % errand.beat.size()


## The yaw that puts a character's front along [param direction], in the same measure
## the player's facing is kept in: [SLocomotion] reads a facing plus the rig's own
## offset, and so does everything downstream of it.
static func facing_for(direction: Vector3, yaw_offset_radians: float) -> float:
	return wrapf(atan2(-direction.x, -direction.z) - yaw_offset_radians, -PI, PI)


func _turn_toward(errand: CErrand, direction: Vector3, locomotion: CLocomotion,
		delta: float) -> void:
	_turn_to(errand, facing_for(direction, locomotion.forward_yaw_offset_radians),
		locomotion, delta)


func _turn_to(errand: CErrand, wanted: float, locomotion: CLocomotion, delta: float) -> void:
	var turn := wrapf(wanted - errand.facing_radians, -PI, PI)
	errand.facing_radians = wrapf(errand.facing_radians + clampf(turn,
		-errand.turn_radians_per_second * delta,
		errand.turn_radians_per_second * delta), -PI, PI)
	locomotion.facing_radians = errand.facing_radians


## Distance actually covered, split into the two axes the blend space wants. Taken from
## where they ended up rather than from what they were asked to do, so a character who
## did not move has legs that know it.
func _report_speed(errand: CErrand, locomotion: CLocomotion, covered: Vector3,
		delta: float) -> void:
	var forward := SLocomotion.forward_of(locomotion)
	var right := SLocomotion.right_of(locomotion)
	locomotion.forward_metres_per_second = forward.dot(covered) / maxf(delta, 0.0001)
	locomotion.strafe_metres_per_second = right.dot(covered) / maxf(delta, 0.0001)
	locomotion.eye_height_metres = errand.at.y
