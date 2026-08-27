extends ECSSystem
class_name SCameraAim

## SCameraAim points the head. Yaw rides the body, so this is pitch and the fixed
## quarter turn that makes the camera look down the train rather than across it.

## Set by the loop before the containment runs, which needs to know how far toward the
## seated rest offset to put the camera back but is handed only the camera.
var _seated_weight := 0.0


func _on_update(_delta: float) -> void:
	for entry: Dictionary in multi_view([CLocomotion, CCamera, CSeating]):
		var eye: CCamera = entry[&"CCamera"]
		if eye.pivot == null:
			continue
		var locomotion: CLocomotion = entry[&"CLocomotion"]
		var seating: CSeating = entry[&"CSeating"]
		var seated := seating.seated_weight()
		locomotion.pitch_radians = clampf(locomotion.pitch_radians,
			eye.lowest_pitch_radians, eye.highest_pitch_radians)
		eye.pivot.rotation = Vector3(locomotion.pitch_radians,
			locomotion.forward_yaw_offset_radians
				+ seating.camera_yaw_radians * seated, 0.0)
		var arm := eye.pivot as SpringArm3D
		if arm != null:
			arm.spring_length = lerpf(eye.standing_boom_metres,
				eye.seated_boom_metres, seated)
		_seated_weight = seated
		_keep_inside_the_carriage(eye)


## Runs after the arm has placed the camera, and only ever pulls it in. The rest offset
## goes back on first, so what this does lasts exactly as long as the look that needs it.
func _keep_inside_the_carriage(eye: CCamera) -> void:
	if eye.camera == null:
		return
	eye.camera.position = eye.rest_offset.lerp(eye.seated_rest_offset, _seated_weight)
	eye.camera.force_update_transform()
	var at := eye.camera.global_position
	var inside := Vector3(at.x,
		clampf(at.y, eye.lowest_y, eye.highest_y),
		clampf(at.z, -eye.interior_half_z, eye.interior_half_z))
	if inside != at:
		eye.camera.global_position = inside
