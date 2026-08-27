extends ECSSystem
class_name SPastime

## SPastime gives a passenger something to do between the hours their timeline accounts
## for: cross the room, cross it again, then take a seat and stay in it.
##
## What it writes is where they are going, which is [CErrand], and whether they are in a
## seat, which is [CSeating]. Everything downstream is untouched: [SCastWalk] walks them
## there without knowing why, [SPosture] reads the sitting off [CSeating] exactly as it
## does for the player, and [SSeatedIdle] shifts their weight on the bench.
##
## The player is not in here. He has hands and a use key, and [SSeating] answers those.
## This is for everybody whose sitting down is decided rather than asked for.

## How close to the bench counts as being at it. Generous: the walk aims at the cushion
## and a body standing on the cushion is not what anybody wants to see.
const AT_THE_BENCH_METRES := 0.45

## How far along the carriage a passenger will wander from where they were put. Inside
## the room, so a wander is never a walk to somewhere their timeline denies they went.
const WANDER_METRES := 5.5

func _on_update(delta: float) -> void:
	for entry: Dictionary in multi_view([CPastime, CErrand, CLocation, CSeating,
			CCharacterRig]):
		_step(entry[&"CPastime"], entry[&"CErrand"], entry[&"CLocation"],
			entry[&"CSeating"], entry[&"CCharacterRig"], delta)


func _step(pastime: CPastime, errand: CErrand, location: CLocation, seating: CSeating,
		rig_slot: CCharacterRig, delta: float) -> void:
	if not errand.stationed:
		return
	if location.location_id != pastime.room:
		_moved_on(pastime, errand, seating, rig_slot.live(), location.location_id)
		return
	if pastime.state == CPastime.SEATED:
		return
	if pastime.state == CPastime.TAKING_A_SEAT:
		_arriving_at_the_bench(pastime, errand, seating, rig_slot.live())
		return
	if errand.at.distance_to(errand.station) > errand.arrive_metres:
		# Still walking. The clock on standing about does not start until they have
		# stopped, or a passenger crossing two carriages arrives already restless.
		pastime.seconds_until_restless = _a_while(pastime)
		return

	pastime.seconds_until_restless -= delta
	if pastime.seconds_until_restless > 0.0:
		return
	if pastime.wandered < pastime.wanders_before_settling:
		_wander(pastime, errand)
		return
	_look_for_a_seat(pastime, errand, seating)


## The timeline has put them in another room. Whatever they were doing is over: they get
## up, give the bench back, and [SCastBody] hands them a station in the new room to walk
## to.
func _moved_on(pastime: CPastime, errand: CErrand, seating: CSeating, rig: CharacterRig,
		room: StringName) -> void:
	if seating.seated:
		_stand(errand, seating, rig)
	pastime.room = room
	pastime.state = CPastime.ARRIVING
	pastime.wandered = 0
	pastime.seconds_until_restless = _a_while(pastime)
	errand.assigned = false


## Somewhere else in the same room, which is all a wander is. The room is what the
## timeline is a claim about, so wandering inside one contradicts nothing.
func _wander(pastime: CPastime, errand: CErrand) -> void:
	pastime.wandered += 1
	pastime.state = CPastime.MILLING
	pastime.seconds_until_restless = _a_while(pastime)
	errand.station_offset_metres += pastime.rng.randf_range(-WANDER_METRES, WANDER_METRES)


## The nearest free bench in the room they are standing in, claimed on the spot. Claimed
## rather than walked at and hoped for: two passengers crossing a carriage at the same
## bench end up on the same cushion, and the first of them to arrive would be sat on.
func _look_for_a_seat(pastime: CPastime, errand: CErrand, seating: CSeating) -> void:
	var found: CSeat = null
	var nearest := INF
	for seat: CSeat in view(&"CSeat"):
		if not seat.free_to_take():
			continue
		var away := Vector2(seat.at.x - errand.at.x, seat.at.z - errand.at.z).length()
		# In this room, not the next one along: the aisle runs the length of the train
		# and the nearest free cushion may be through two doors.
		if away > WANDER_METRES * 2.0 or away >= nearest:
			continue
		nearest = away
		found = seat
	if found == null:
		# A full carriage. Stand about a while longer and ask again; somebody will move.
		pastime.seconds_until_restless = _a_while(pastime)
		return
	found.taken_by = seating
	seating.seat = found
	# Where they were standing when they decided to sit, kept now rather than on
	# arrival: getting up has to put them back in the aisle they crossed, not leave
	# them at the cushion to walk out sideways through the bench.
	seating.stood_at = errand.at
	seating.stood_eye_height_metres = errand.station.y
	seating.stood_facing_radians = errand.facing_radians
	pastime.state = CPastime.TAKING_A_SEAT
	errand.assigned = true
	errand.assigned_station = Vector3(found.at.x,
		found.at.y + seating.seated_eye_above_cushion_metres, found.at.z)
	errand.assigned_facing = SCastWalk.facing_for(
		Vector3(-sin(found.facing_radians), 0.0, -cos(found.facing_radians)), 0.0)


func _arriving_at_the_bench(pastime: CPastime, errand: CErrand, seating: CSeating,
		rig: CharacterRig) -> void:
	if seating.seat == null:
		pastime.state = CPastime.ARRIVING
		errand.assigned = false
		return
	if errand.at.distance_to(errand.station) > AT_THE_BENCH_METRES:
		return
	_sit(pastime, errand, seating, rig)


## Down. The eye drops to the cushion and the rig hangs from the deck rather than from
## the eye, because the sitting clip sits on a floor and the eye is no longer where the
## feet are.
func _sit(pastime: CPastime, errand: CErrand, seating: CSeating, rig: CharacterRig) -> void:
	seating.seated = true
	pastime.state = CPastime.SEATED
	errand.facing_radians = errand.assigned_facing
	errand.at = errand.assigned_station
	if rig != null:
		rig.position = errand.at
		rig.rotation.y = errand.facing_radians
		rig.set_ground_drop(errand.at.y - Consist.FLOOR_Y)


## Up, and the bench given back to whoever wants it next.
func _stand(errand: CErrand, seating: CSeating, rig: CharacterRig) -> void:
	if seating.seat != null:
		seating.seat.taken_by = null
		seating.seat = null
	seating.seated = false
	errand.at = seating.stood_at
	errand.at.y = seating.stood_eye_height_metres
	if rig != null:
		rig.set_ground_drop(rig.rest_ground_drop())


func _a_while(pastime: CPastime) -> float:
	return pastime.rng.randf_range(pastime.shortest_wait_seconds,
		pastime.longest_wait_seconds)


## Systems are freed with the scene that added them, and the benches are freed with it:
## the seats are spawned into the train's own scope. The passengers are not -- they live
## on the session and are handed a fresh carriage every time one is drawn.
##
## Anybody left sitting would be holding a [CSeat] that no longer exists, in a room that
## has not been built yet, and would still be sitting on the cushion the next time the
## carriage came into view whatever the new one looks like. So everybody gets up on the
## way out, which is the same walk out of the seating they would have made anyway.
func _exit_tree() -> void:
	if _world == null:
		return
	for entry: Dictionary in multi_view([CPastime, CErrand, CSeating, CCharacterRig]):
		var pastime: CPastime = entry[&"CPastime"]
		var errand: CErrand = entry[&"CErrand"]
		if entry[&"CSeating"].seated:
			_stand(errand, entry[&"CSeating"], entry[&"CCharacterRig"].live())
		errand.assigned = false
		pastime.state = CPastime.ARRIVING
		pastime.seconds_until_restless = _a_while(pastime)
