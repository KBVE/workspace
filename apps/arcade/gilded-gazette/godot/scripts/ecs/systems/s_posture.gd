extends ECSSystem
class_name SPosture

## SPosture decides whether the body is walking, leaving the floor, in the air or
## arriving, and tells the rig when that answer changes.
##
## The decision is here rather than in an [AnimationNodeStateMachine] because the thing
## it is decided from is [CLocomotion], which the rig cannot see and should not: a
## passenger and the player run the same rig off different locomotion.

func _on_update(delta: float) -> void:
	for entry: Dictionary in multi_view([CLocomotion, CPosture, CCharacterRig]):
		var rig: CharacterRig = entry[&"CCharacterRig"].rig
		if rig == null:
			continue
		# A body, a posture and something to see it with is all this needs. What it
		# might be sitting on and what it does with its hands are asked of the entity
		# rather than named in the view, because neither is true of everybody: the
		# Order's escort never sit down, and the player -- who is behind the camera --
		# has no standing idles. Naming them here made a knight fail the query and
		# stand through the whole night in the middle of the walk blend space.
		var entity: ECSEntity = entry["entity"]
		_step(entry[&"CLocomotion"], entry[&"CPosture"],
			entity.get_component(CSeating) as CSeating,
			entity.get_component(CSeatedIdle) as CSeatedIdle,
			entity.get_component(CStandingIdle) as CStandingIdle, rig, delta)


func _step(locomotion: CLocomotion, posture: CPosture, seating: CSeating,
		idle: CSeatedIdle, standing: CStandingIdle, rig: CharacterRig, delta: float) -> void:
	if posture.dead:
		# Outranks the sit-down, which otherwise outranks everything: a body that was
		# put down in a compartment must not stand up to take a seat in it.
		posture.state = CPosture.DEAD
		posture.was_airborne = false
		posture.landing_seconds_left = 0.0
		if posture.state != posture.requested:
			posture.requested = posture.state
			rig.set_posture(posture.state)
		return
	if seating != null and seating.moving():
		# the sit-down and the stand-up outrank even the sitting: they are one-shots
		# that have to be allowed to run, and [SSeating] holds the body for exactly as
		# long as they do.
		posture.state = CPosture.SEATING if seating.settling_seconds_left > 0.0 \
			else CPosture.RISING
		posture.was_airborne = false
		posture.landing_seconds_left = 0.0
		if posture.state != posture.requested:
			posture.requested = posture.state
			rig.set_posture(posture.state)
		return
	if seating != null and seating.seated:
		# outranks the rest of it: he is not walking, falling or landing, he is sitting.
		# Which sitting is [SSeatedIdle]'s to say.
		posture.state = idle.state if idle != null else CPosture.SEATED
		posture.was_airborne = false
		posture.landing_seconds_left = 0.0
		if posture.state != posture.requested:
			posture.requested = posture.state
			rig.set_posture(posture.state)
		return
	var airborne := locomotion.airborne()
	if airborne:
		# rising is the launch and falling is the fall, which is the whole state machine
		posture.state = CPosture.LAUNCHING if locomotion.rise_metres_per_second > 0.0 \
			else CPosture.AIRBORNE
		posture.landing_seconds_left = 0.0
	elif posture.was_airborne:
		posture.state = CPosture.LANDING
		posture.landing_seconds_left = posture.landing_seconds
	elif posture.landing_seconds_left > 0.0:
		posture.landing_seconds_left -= delta
		if posture.landing_seconds_left <= 0.0:
			posture.state = CPosture.AFOOT
	else:
		# On their feet and going nowhere, which is where [SStandingIdle] has a say:
		# the plain Idle at the middle of the gait is one of the things to stand about
		# doing rather than the only one. A character without that component -- the
		# player, who is behind the camera -- stands the way everybody used to.
		posture.state = standing.state if standing != null else CPosture.AFOOT
	posture.was_airborne = airborne

	if posture.state != posture.requested:
		posture.requested = posture.state
		rig.set_posture(posture.state)
