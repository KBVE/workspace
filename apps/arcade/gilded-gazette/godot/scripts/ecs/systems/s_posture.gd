extends ECSSystem
class_name SPosture

## SPosture decides whether the body is walking, leaving the floor, in the air or
## arriving, and tells the rig when that answer changes.
##
## The decision is here rather than in an [AnimationNodeStateMachine] because the thing
## it is decided from is [CLocomotion], which the rig cannot see and should not: a
## passenger and the player run the same rig off different locomotion.

func _on_update(delta: float) -> void:
	for entry: Dictionary in multi_view([CLocomotion, CPosture, CSeating, CSeatedIdle,
			CCharacterRig]):
		var rig: CharacterRig = entry[&"CCharacterRig"].rig
		if rig == null:
			continue
		_step(entry[&"CLocomotion"], entry[&"CPosture"], entry[&"CSeating"],
			entry[&"CSeatedIdle"], rig, delta)


func _step(locomotion: CLocomotion, posture: CPosture, seating: CSeating,
		idle: CSeatedIdle, rig: CharacterRig, delta: float) -> void:
	if seating.moving():
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
	if seating.seated:
		# outranks the rest of it: he is not walking, falling or landing, he is sitting.
		# Which sitting is [SSeatedIdle]'s to say.
		posture.state = idle.state
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
		posture.state = CPosture.AFOOT
	posture.was_airborne = airborne

	if posture.state != posture.requested:
		posture.requested = posture.state
		rig.set_posture(posture.state)
