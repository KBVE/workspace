extends ECSSystem
class_name SLocomotion

func _on_update(delta: float) -> void:
	for entry: Dictionary in multi_view([CInput, CLocomotion, CSeating, ECSViewComponent]):
		var body: CharacterBody3D = entry[&"ECSViewComponent"].view as CharacterBody3D
		if body == null:
			continue
		var seating: CSeating = entry[&"CSeating"]
		if seating.approaching:
			# walking to a bench. [SSeating] is driving, and it has already written the
			# stride it covered onto the locomotion for the legs to play; parking here
			# would wipe that and slide him in on his heels.
			continue
		if seating.seated or seating.moving():
			_sit_still(entry[&"CLocomotion"], body)
			continue
		_step(entry[&"CInput"], entry[&"CLocomotion"], body, delta)


## A seated body is parked, and so is one on its way onto a cushion or off it: while
## the sit-down runs it is [SSeating] that says where the body is, a share of the way
## along, and a move_and_slide between those writes is a body fighting itself.
##
## Parking is not a move. Calling move_and_slide on it would be: the capsule is a
## standing man's, so dropping the eye to cushion height pushes its base through the
## deck and the floor shoves him back up by a foot.
static func _sit_still(locomotion: CLocomotion, body: CharacterBody3D) -> void:
	body.velocity = Vector3.ZERO
	body.rotation.y = locomotion.facing_radians
	body.position.y = locomotion.eye_height_metres
	locomotion.forward_metres_per_second = 0.0
	locomotion.strafe_metres_per_second = 0.0


func _step(intent: CInput, locomotion: CLocomotion, body: CharacterBody3D, delta: float) -> void:
	# wraps rather than clamps: the player can turn all the way round and look
	# back down the train
	locomotion.facing_radians = wrapf(
		locomotion.facing_radians + intent.turn_units * locomotion.turn_radians_per_unit,
		-PI, PI)
	# clamped by [SCameraAim], which owns the bounds along with the head
	locomotion.pitch_radians += intent.pitch_units * locomotion.turn_radians_per_unit
	if intent.recentring_view:
		locomotion.pitch_radians = move_toward(locomotion.pitch_radians, 0.0,
			locomotion.pitch_recentre_radians_per_second * delta)
	body.rotation.y = locomotion.facing_radians
	_rise(intent, locomotion, delta)
	body.position.y = locomotion.eye_height_metres + locomotion.height_above_stance_metres

	var forward := forward_of(locomotion)
	var right := right_of(locomotion)
	var step := forward * intent.walk_units + right * intent.strafe_units
	var metres := step.length() * locomotion.walk_metres_per_unit
	var was_at := body.global_position
	# the step is already a distance, so it becomes a velocity only because
	# move_and_slide wants one; sliding is what carries the player along a wall
	# instead of stopping dead against it
	body.velocity = Vector3.ZERO if is_zero_approx(metres) \
		else step.normalized() * metres / maxf(delta, 0.0001)
	body.move_and_slide()
	var covered := body.global_position - was_at
	locomotion.forward_metres_per_second = forward.dot(covered) / maxf(delta, 0.0001)
	locomotion.strafe_metres_per_second = right.dot(covered) / maxf(delta, 0.0001)


## Flattened, so looking is never a way to climb.
static func forward_of(locomotion: CLocomotion) -> Vector3:
	var yaw := locomotion.facing_radians + locomotion.forward_yaw_offset_radians
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func right_of(locomotion: CLocomotion) -> Vector3:
	var yaw := locomotion.facing_radians + locomotion.forward_yaw_offset_radians
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## A jump is height above the stance, not a fall onto a floor. Nothing here touches the
## collision capsule: it is pinned to the deck the player can see, and letting gravity
## own it would drop him to the collision floor a metre and a quarter below.
static func _rise(intent: CInput, locomotion: CLocomotion, delta: float) -> void:
	if intent.jump_requested and not locomotion.airborne():
		locomotion.rise_metres_per_second = sqrt(2.0
			* locomotion.gravity_metres_per_second_squared
			* maxf(locomotion.jump_rise_metres, 0.0))
	if locomotion.rise_metres_per_second == 0.0 and not locomotion.airborne():
		return
	locomotion.rise_metres_per_second -= \
		locomotion.gravity_metres_per_second_squared * delta
	locomotion.height_above_stance_metres += locomotion.rise_metres_per_second * delta
	if locomotion.height_above_stance_metres <= 0.0:
		locomotion.height_above_stance_metres = 0.0
		locomotion.rise_metres_per_second = 0.0
