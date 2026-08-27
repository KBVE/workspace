extends ECSSystem
class_name SCharacterAnimation

## SCharacterAnimation turns the speed a body actually covered into a place in its
## rig's blend space.
##
## Both axes are needed, because the blend space is the only thing that knows the legs
## are meant to be crossing rather than striding; fed forward speed alone, a sidestep
## played the standing clip and the character slid sideways on his heels.

func _on_update(delta: float) -> void:
	for entry: Dictionary in multi_view([CLocomotion, CGait, CCharacterRig]):
		var rig: CharacterRig = entry[&"CCharacterRig"].live()
		if rig == null:
			continue
		_step(entry[&"CLocomotion"], entry[&"CGait"], rig, delta)


func _step(locomotion: CLocomotion, gait: CGait, rig: CharacterRig, delta: float) -> void:
	var ground := Vector2(locomotion.strafe_metres_per_second,
		locomotion.forward_metres_per_second)
	var clip_metres_per_second := gait.walk_clip_metres_per_second * rig.model_scale
	var wanted := (ground / clip_metres_per_second).limit_length(1.0)
	gait.blend = gait.blend.lerp(wanted,
		clampf(delta / maxf(gait.blend_seconds, 0.0001), 0.0, 1.0))
	rig.set_gait(gait.blend, clampf(ground.length() / clip_metres_per_second,
		gait.time_scale_limits.x, gait.time_scale_limits.y))
