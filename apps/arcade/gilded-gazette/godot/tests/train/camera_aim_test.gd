# GdUnitTestSuite
extends GdUnitTestSuite

## Where the game is looked at from.
##
## Untested until now, which is a strange thing to be able to say about the one system
## that decides what is on screen. Everything here has a comment on [CCamera] saying
## what went wrong before it was written -- a camera shoved into the back of the
## player's head, a boom that sailed through the roof and filmed the run from outside --
## and none of those had anything to stop them coming back.

const SCENE := "res://scenes/train/train.scn"


func _eye() -> Dictionary:
	return Ecs.world.multi_view([CLocomotion, CCamera, CSeating])[0]


func _aim() -> SCameraAim:
	return Ecs.runner.get_system(&"camera_aim")


func test_the_head_cannot_look_past_straight_up_or_straight_down() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var eye: Dictionary = _eye()
	var camera: CCamera = eye[&"CCamera"]
	var locomotion: CLocomotion = eye[&"CLocomotion"]

	locomotion.pitch_radians = camera.highest_pitch_radians + 5.0
	await runner.simulate_frames(2)
	assert_float(locomotion.pitch_radians).override_failure_message(
		"the head looked past the top of its own range, where the body's yaw stops "
		+ "meaning anything on screen").is_equal_approx(camera.highest_pitch_radians, 0.001)

	locomotion.pitch_radians = camera.lowest_pitch_radians - 5.0
	await runner.simulate_frames(2)
	assert_float(locomotion.pitch_radians).is_equal_approx(
		camera.lowest_pitch_radians, 0.001)


## Yaw rides the body, so what the pivot carries is the pitch and the fixed quarter
## turn that makes the camera look down the train rather than across it.
func test_the_pivot_carries_the_pitch_and_the_quarter_turn() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var eye: Dictionary = _eye()
	var camera: CCamera = eye[&"CCamera"]
	var locomotion: CLocomotion = eye[&"CLocomotion"]

	locomotion.pitch_radians = -0.4
	await runner.simulate_frames(2)
	assert_float(camera.pivot.rotation.x).is_equal_approx(-0.4, 0.001)
	assert_float(camera.pivot.rotation.y).override_failure_message(
		"the shot stopped looking down the train").is_equal_approx(
			locomotion.forward_yaw_offset_radians, 0.001)


## The carriage is mesh with no collision behind it: only the floor and the two side
## walls carry bodies, so a boom swinging up on a downward look sails through the roof
## and films the run from outside, with the exterior cutting the player in half.
##
## The box is brought in to meet the camera rather than the camera pushed out of the
## box, because the rest offset is written back every frame before the containment
## runs -- so a camera moved by a test is a camera moved back before anything looks at
## where it is.
func test_the_camera_is_kept_under_the_roof() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var camera: CCamera = _eye()[&"CCamera"]

	camera.highest_y = camera.camera.global_position.y - 1.0
	await runner.simulate_frames(2)
	# &millimetres -> the arm places its child again after the system has run, so the
	#             containment is accurate to a couple of millimetres rather than to
	#             the float. What it is for is a camera a metre through the roof, and
	#             two millimetres of it is not a shot anybody can tell from the right one.
	assert_float(camera.camera.global_position.y).override_failure_message(
		"the camera was left above the roof at %f, which is over %f"
			% [camera.camera.global_position.y, camera.highest_y]
	).is_less_equal(camera.highest_y + 0.02)


func test_the_camera_is_kept_inside_the_side_walls() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var camera: CCamera = _eye()[&"CCamera"]

	camera.interior_half_z = maxf(absf(camera.camera.global_position.z) - 0.5, 0.05)
	await runner.simulate_frames(2)
	assert_float(absf(camera.camera.global_position.z)).override_failure_message(
		"the camera was left outside the side wall at %f"
			% camera.camera.global_position.z
	).is_less_equal(camera.interior_half_z + 0.02)


## X is deliberately unbounded: the aisle runs the length of the train, and clamping it
## would stop the camera following the player up the carriages.
func test_the_camera_may_run_the_length_of_the_train() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var camera: CCamera = _eye()[&"CCamera"]
	var was := camera.camera.global_position.x

	# Moved by the thing the camera actually hangs off, so the rest offset written back
	# every frame does not simply undo it.
	camera.pivot.global_position.x += 40.0
	await runner.simulate_frames(2)
	assert_float(camera.camera.global_position.x).override_failure_message(
		"the camera was pulled back down the train it is meant to follow the player up"
	).is_greater(was + 20.0)


## The one this was written for. Containment moves the camera by writing its transform,
## and that write outlives the look that caused it: shoved in against the roof at full
## pitch, the camera stayed shoved once the view came level, and every glance downward
## walked it further into the back of the player's head.
##
## Asserted as coming back rather than as sitting at the rest offset, because the offset
## is not where the camera ends up: the arm places its own child along the boom after
## the system has run. What must hold is that a look which is over leaves nothing behind.
func test_a_look_that_is_over_leaves_nothing_behind() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var eye: Dictionary = _eye()
	var locomotion: CLocomotion = eye[&"CLocomotion"]

	locomotion.pitch_radians = 0.0
	await runner.simulate_frames(6)
	var level: Vector3 = eye[&"CCamera"].camera.position

	for look: float in [eye[&"CCamera"].lowest_pitch_radians,
			eye[&"CCamera"].highest_pitch_radians, eye[&"CCamera"].lowest_pitch_radians]:
		locomotion.pitch_radians = look
		await runner.simulate_frames(6)
	locomotion.pitch_radians = 0.0
	await runner.simulate_frames(6)

	assert_vector(eye[&"CCamera"].camera.position).override_failure_message(
		"three looks left the camera at %s, and level is %s -- it is walking into the "
		% [eye[&"CCamera"].camera.position, level] + "back of his head"
	).is_equal_approx(level, Vector3.ONE * 0.01)


## A seated body is against the wall and a boom directly behind it is inside the bench,
## so the shot swings a quarter turn to put the camera over the aisle -- which is the
## only place in a carriage with room to film from, and is narrower than the car is long.
##
## The boom has to fit in that room. An arm longer than the containment box is a camera
## clamped on every frame the player is sitting down: a fight nothing on screen shows
## and nothing in the code reports, and the two numbers live in different files.
func test_the_seated_boom_fits_inside_the_carriage() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var camera: CCamera = _eye()[&"CCamera"]
	assert_float(camera.seated_boom_metres).override_failure_message(
		"the seated boom is %fm and the carriage gives it %fm, so the shot is in the wall"
			% [camera.seated_boom_metres, camera.interior_half_z]
	).is_less_equal(camera.interior_half_z)


## Sitting swings the shot and lengthens it; standing lays it back down the train, where
## there is a carriage of room and no need to reach past anybody.
func test_the_boom_changes_length_when_he_sits() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var camera: CCamera = _eye()[&"CCamera"]
	assert_float(camera.seated_boom_metres).override_failure_message(
		"sitting down does not move the camera at all").is_not_equal(
			camera.standing_boom_metres)

	var arm := camera.pivot as SpringArm3D
	if arm == null:
		return
	assert_float(arm.spring_length).override_failure_message(
		"standing, the boom is %fm rather than the %fm it is built with"
			% [arm.spring_length, camera.standing_boom_metres]
	).is_equal_approx(camera.standing_boom_metres, 0.01)
