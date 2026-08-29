extends ECSSystem
class_name SStandingIdle

## SStandingIdle moves a stopped character between the standing clips.
##
## The mirror of [SSeatedIdle], and it runs in the same place for the same reason:
## before [SPosture], which is what actually asks the rig for a state. This only says
## which standing one it ought to be.
##
## A body that is moving is left alone. Its variation is the gait, which already answers
## to how fast the legs are going, and a walk interrupted by a man folding his arms is
## worse than no variation at all.

func _on_update(delta: float) -> void:
	for entry: Dictionary in multi_view([CLocomotion, CStandingIdle, CPosture,
			CCharacterRig]):
		# Seating is optional for the same reason it is in [SPosture]: the Order's
		# escort stand their watch and never sit down, and requiring a seat to have an
		# opinion about would leave the four of them out of the one system that gives a
		# standing body anything to do.
		_step(entry[&"CLocomotion"], entry[&"CStandingIdle"], entry[&"CPosture"],
			entry["entity"].get_component(CSeating) as CSeating,
			entry[&"CCharacterRig"], delta)


func _step(locomotion: CLocomotion, idle: CStandingIdle, posture: CPosture,
		seating: CSeating, body: CCharacterRig, delta: float) -> void:
	# Sitting, dying and being in the air are all somebody else's answer, and each of
	# them outranks this one in [SPosture] anyway. Resetting rather than merely not
	# choosing is what stops a character who sat down mid-look standing back up with
	# the look already half over.
	var sitting := seating != null and (seating.seated or seating.moving())
	if posture.dead or sitting or locomotion.airborne():
		idle.state = CPosture.AFOOT
		idle.still_seconds = 0.0
		idle.seconds_until_change = 0.0
		return

	var ground := Vector2(locomotion.strafe_metres_per_second,
		locomotion.forward_metres_per_second).length()
	if ground > idle.still_metres_per_second:
		idle.state = CPosture.AFOOT
		idle.still_seconds = 0.0
		idle.seconds_until_change = 0.0
		return

	idle.still_seconds += delta
	if idle.still_seconds < idle.settling_seconds:
		return

	idle.seconds_until_change -= delta
	if idle.seconds_until_change > 0.0:
		return
	idle.state = _another(idle, _with_company(idle, body))
	idle.seconds_until_change = idle.rng.randf_range(
		idle.shortest_seconds, idle.longest_seconds)


## A standing state that is not the one already playing. Asking the transition for the
## state it is in restarts the crossfade, which reads as a stutter rather than a change.
func _another(idle: CStandingIdle, choices: Array[StringName]) -> StringName:
	var rest := choices.filter(func(state: StringName) -> bool: return state != idle.state)
	if rest.is_empty():
		return idle.state
	return rest[idle.rng.randi_range(0, rest.size() - 1)]


## What this character might do next, which is what they were given plus talking when
## there is anybody stood near enough to talk to.
##
## Company is another character on their feet and within reach. Somebody sitting down is
## not company for this: the standing talk gestures at head height, and the person it
## would be aimed at is a foot and a half lower.
##
## Measured off the rigs rather than off anything the entity holds, because where a
## passenger is standing is a fact about the body [SCastBody] built and nothing else
## knows it. A character whose carriage is out of view has no rig, so nobody talks to
## them and they talk to nobody -- which costs nothing, since there is also nobody
## there to see it.
func _with_company(idle: CStandingIdle, body: CCharacterRig) -> Array[StringName]:
	var choices := idle.choices.duplicate()
	var rig := body.live()
	if rig == null:
		return choices
	var here := rig.global_position
	for entry: Dictionary in multi_view([CStandingIdle, CCharacterRig]):
		var other: CharacterRig = entry[&"CCharacterRig"].live()
		if other == null or other == rig:
			continue
		var sat: CSeating = entry["entity"].get_component(CSeating) as CSeating
		if sat != null and sat.seated:
			continue
		if here.distance_to(other.global_position) <= idle.talking_reach_metres:
			choices.append(CPosture.STANDING_TALKING)
			break
	return choices
