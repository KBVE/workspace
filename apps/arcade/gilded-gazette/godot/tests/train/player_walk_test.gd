# GdUnitTestSuite
extends GdUnitTestSuite

const SCENE := "res://scenes/train/train.scn"


func _locomotion_of(train: Node) -> CLocomotion:
	return train._locomotion


## Walking used to add to world X whatever the player was looking at, so turning
## round and pressing forward walked you backwards. Direction has to come from the
## facing the body carries, and this is the test that says so.
func test_walking_follows_the_way_the_player_faces() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(4)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")

	var start := player.position.x
	runner.simulate_action_press("move_up")
	await runner.simulate_frames(4)
	runner.simulate_action_release("move_up")
	assert_float(player.position.x - start).override_failure_message(
		"facing down the train, walking forward should raise world X"
	).is_greater(0.0)

	_locomotion_of(train).facing_radians = PI
	await runner.simulate_frames(1)
	start = player.position.x
	runner.simulate_action_press("move_up")
	await runner.simulate_frames(4)
	runner.simulate_action_release("move_up")
	assert_float(player.position.x - start).override_failure_message(
		"turned around, the same forward input has to walk the other way"
	).is_less(0.0)


## The shell keeps the player inside the carriage; without it a long enough walk
## leaves the train entirely.
func test_the_player_cannot_walk_out_through_a_wall() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(4)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")

	_locomotion_of(train).facing_radians = PI * 0.5
	runner.simulate_action_press("move_up")
	await runner.simulate_frames(60)
	runner.simulate_action_release("move_up")
	assert_float(absf(player.position.z)).override_failure_message(
		"the player walked out sideways through the carriage wall"
	).is_less(Consist.INTERIOR_HALF_Z)


## The camera is behind him now, so he is looked at rather than looked out of: the
## face is drawn, the head is whole, and he is not walking the aisle bald or naked.
func test_the_body_is_dressed_and_whole_for_the_camera_behind_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(4)
	var body: PlayerBody = runner.scene().get_node("Screen/Frame/World/Player/Rig")

	assert_object(body.skeleton).is_not_null()
	var visible_meshes: Array[StringName] = []
	for child: Node in body.skeleton.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).visible:
			visible_meshes.append(StringName(child.name))

	# the head-only body names its mesh after the file it was cut from, so match the
	# stem rather than a name that moves when the source does
	var wears_skin := false
	for name: StringName in visible_meshes:
		wears_skin = wears_skin or String(name).begins_with("RegularMale")
	assert_bool(wears_skin).override_failure_message(
		"no skin is drawn, so the collar has no neck and the head no face"
	).is_true()
	for face: StringName in [&"Eyes", &"Eyebrows"]:
		assert_array(visible_meshes).override_failure_message(
			"%s is hidden, so the camera behind him is looking at a faceless head" % face
		).contains([face])
	assert_int(visible_meshes.size()).override_failure_message(
		"no outfit or hair was grafted on, so he is bald and undressed"
	).is_greater(4)


## The whole point of the boom: the camera sits behind the player rather than inside
## his eyes, and far enough back to see him.
func test_the_camera_rides_a_boom_behind_the_player() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(6)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")
	var camera: Camera3D = train.get_node("Screen/Frame/World/Player/Boom/Mount/Camera3D")

	var behind := player.global_position - camera.global_position
	assert_float(behind.length()).override_failure_message(
		"the camera is sitting on top of the player, so there is no third person"
	).is_greater(0.5)
	assert_float(SLocomotion.forward_of(_locomotion_of(train)).dot(behind.normalized())) \
		.override_failure_message(
			"the camera drifted round in front of him and is filming his face"
		).is_greater(0.0)


## A and D used to turn. They strafe now, and strafing has to leave the body facing
## the way it already faced or the aisle swings every time you sidestep.
func test_strafing_moves_sideways_without_turning() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(4)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")
	var facing := _locomotion_of(train).facing_radians

	var start := player.position.z
	runner.simulate_action_press("move_right")
	await runner.simulate_frames(10)
	runner.simulate_action_release("move_right")

	assert_float(absf(player.position.z - start)).override_failure_message(
		"strafing right moved the player nowhere across the aisle"
	).is_greater(0.01)
	assert_float(_locomotion_of(train).facing_radians).override_failure_message(
		"strafing turned the body, so the view swung with it"
	).is_equal_approx(facing, 0.001)


## Past straight up or straight down the yaw the body carries stops meaning anything
## on screen, so the head stops before either.
func test_the_head_cannot_pitch_past_its_bounds() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(4)
	var train: Node = runner.scene()
	var boom: SpringArm3D = train.get_node("Screen/Frame/World/Player/Boom")
	var locomotion := _locomotion_of(train)

	locomotion.pitch_radians = -100.0
	await runner.simulate_frames(2)
	assert_float(boom.rotation.x).override_failure_message(
		"the boom swung past straight down"
	).is_greater(-PI * 0.5)

	locomotion.pitch_radians = 100.0
	await runner.simulate_frames(2)
	assert_float(boom.rotation.x).override_failure_message(
		"the boom swung past straight up"
	).is_less(PI * 0.5)


## The evidence in this game is clicked on, so the pointer never gets captured. It
## was, briefly, and there was then no way to click anything at all.
func test_the_pointer_stays_available_for_picking() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)

	assert_int(Input.mouse_mode).override_failure_message(
		"the pointer was captured, so nothing in the carriage can be clicked"
	).is_equal(Input.MOUSE_MODE_VISIBLE)


## Mouse motion never reaches a headless run, so this drives the seam the window
## hands it to instead: pixels in, head turned and pitched.
func test_mouse_motion_turns_and_pitches_the_head() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(4)
	var train: Node = runner.scene()
	var locomotion := _locomotion_of(train)
	var facing := locomotion.facing_radians

	train._control.accumulate_look(Vector2(200.0, 120.0), 720.0)
	await runner.simulate_frames(2)

	assert_float(locomotion.facing_radians).override_failure_message(
		"moving the mouse right did not turn the head right"
	).is_less(facing)
	assert_float(locomotion.pitch_radians).override_failure_message(
		"moving the mouse down did not pitch the head down"
	).is_less(0.0)


## The carriage mesh bottoms out fifteen centimetres above the collision floor, so a
## rig placed on the collider stands buried to the ankles in floorboards.
func test_he_stands_on_the_floor_he_can_see() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(6)
	var train: Node = runner.scene()
	var body: PlayerBody = train.get_node("Screen/Frame/World/Player/Rig")
	var toes := body.skeleton.find_bone(&"LeftToes")
	assert_int(toes).is_greater(-1)

	var at: Vector3 = body.skeleton.global_transform \
		* body.skeleton.get_bone_global_pose(toes).origin
	assert_float(at.y).override_failure_message(
		"his toes are under the floorboards"
	).is_greater(Consist.FLOOR_Y - 0.01)
	# the deck sits above the underframe; anything near zero is the car's underside
	assert_float(Consist.FLOOR_Y).override_failure_message(
		"the drawn floor is back under the carriage, where the underframe is"
	).is_greater(1.0)
	assert_float(at.y).override_failure_message(
		"he is hovering above the floor"
	).is_less(Consist.FLOOR_Y + 0.1)


## Moving the collision floor to match the drawn one lifted the player, because his
## capsule is sized against the collider and depenetration pushed him out of it. The
## drawn floor is a drawing measurement and must stay one.
func test_fixing_the_drawn_floor_did_not_move_the_player() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(6)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")

	assert_float(player.global_position.y).override_failure_message(
		"the player is no longer pinned at eye height, so his collider is fighting the floor"
	).is_equal_approx(_locomotion_of(train).eye_height_metres, 0.02)


## A spring arm only stops at collision, and the carriage roof and bulkheads carry
## none. Looking down swings the arm up, and it used to sail out through the ceiling
## and film the run from outside, with the carriage's own red exterior across the
## frame and the player cut off at the waist behind it.
func test_the_camera_cannot_leave_the_carriage() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(6)
	var train: Node = runner.scene()
	var camera: Camera3D = train.get_node("Screen/Frame/World/Player/Boom/Mount/Camera3D")
	var locomotion := _locomotion_of(train)

	for pitch: float in [-1.25, -0.55, 0.9]:
		locomotion.pitch_radians = pitch
		await runner.simulate_frames(2)
		var at := camera.global_position
		assert_float(at.y).override_failure_message(
			"looking at %f put the camera through the roof" % pitch
		).is_less(Consist.WALL_HEIGHT)
		assert_float(at.y).override_failure_message(
			"looking at %f put the camera under the floor" % pitch
		).is_greater(Consist.FLOOR_Y)
		assert_float(absf(at.z)).override_failure_message(
			"looking at %f put the camera out through a side wall" % pitch
		).is_less(Consist.INTERIOR_HALF_Z)


## He was two metres seventy, because the rig was scaled to a camera height measured
## when there was no body to compare it against. Stature is the input now.
func test_he_is_the_size_of_a_person() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(6)
	var body: PlayerBody = runner.scene().get_node("Screen/Frame/World/Player/Rig")

	var drawn: float = body.rest_stature_metres() * body.get_child(0).scale.y
	assert_float(drawn).override_failure_message(
		"the drawn body is not the height he is supposed to be"
	).is_equal_approx(body.stature_metres, 0.01)
	assert_float(drawn).override_failure_message(
		"nobody is this tall; the rig is being scaled off something other than stature"
	).is_between(1.5, 2.0)

	assert_float(body.eye_height_metres() - Consist.FLOOR_Y).override_failure_message(
		"his eyes are not a person's height above the floor he stands on"
	).is_between(1.5, 1.7)


## The capsule was authored around the old camera height. Left at 2.75 its bottom
## sits under the floor, and depenetration lifts him a metre into the air every frame.
func test_the_capsule_is_the_size_of_the_man_inside_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(6)
	var train: Node = runner.scene()
	var body: PlayerBody = train.get_node("Screen/Frame/World/Player/Rig")
	var shape: CollisionShape3D = train.get_node("Screen/Frame/World/Player/Body")
	var capsule: CapsuleShape3D = shape.shape

	assert_float(capsule.height).override_failure_message(
		"the capsule is not his height, so it will fight the floor"
	).is_equal_approx(body.stature_metres, 0.01)

	var bottom: float = train.get_node("Screen/Frame/World/Player").global_position.y \
		+ shape.position.y - capsule.height * 0.5
	assert_float(bottom).override_failure_message(
		"the bottom of the capsule is below the floor it stands on"
	).is_greater(Consist.FLOOR_Y - 0.05)


## A look is left where the player put it. Easing it back to level the moment they let
## go of the button read as the camera taking the view off them.
func test_the_view_holds_where_the_look_left_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(4)
	var train: Node = runner.scene()
	var locomotion := _locomotion_of(train)

	train._control.accumulate_look(Vector2(0.0, 200.0), 720.0)
	await runner.simulate_frames(2)
	var looked_at := locomotion.pitch_radians
	assert_float(looked_at).override_failure_message(
		"the look never pitched the view down, so there is nothing to hold"
	).is_less(-0.2)

	await runner.simulate_frames(90)
	assert_float(locomotion.pitch_radians).override_failure_message(
		"the view drifted off on its own after the look ended"
	).is_equal_approx(looked_at, 0.01)


## Asking for the view back is the only thing that levels it, and it has to arrive
## rather than easing most of the way and stopping.
func test_asking_for_the_view_back_levels_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(4)
	var train: Node = runner.scene()
	var locomotion := _locomotion_of(train)
	train._control.set_update(false)

	locomotion.pitch_radians = -0.9
	train._intent.pitch_units = 0.0
	train._intent.recentring_view = false
	await runner.simulate_frames(30)
	assert_float(locomotion.pitch_radians).override_failure_message(
		"the view levelled itself without being asked"
	).is_equal_approx(-0.9, 0.01)

	train._intent.recentring_view = true
	await runner.simulate_frames(120)
	assert_float(locomotion.pitch_radians).override_failure_message(
		"asking for the view back did not bring it level"
	).is_equal_approx(0.0, 0.02)


## Strafing used to play the standing clip, because the gait was a single forward axis
## and a sidestep reads as zero on it. He slid sideways on his heels.
func test_sidestepping_puts_the_legs_in_a_sideways_clip() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(6)
	var train: Node = runner.scene()
	var body: PlayerBody = train.get_node("Screen/Frame/World/Player/Rig")
	train._control.set_update(false)

	# the aisle is a foot and a half wide and the benches are solid now, so a sidestep
	# has to be slow enough to still be moving when the gait is read
	train._intent.strafe_units = 0.0015
	await runner.simulate_frames(12)
	var blend: Vector2 = body.animation_tree.get(CharacterRig.BLEND_POSITION_PARAMETER)

	assert_float(blend.x).override_failure_message(
		"stepping right left the gait on the forward axis, so he is standing still and sliding"
	).is_greater(0.2)
	assert_float(absf(blend.y)).override_failure_message(
		"a pure sidestep leaked into the forward axis, so the legs are striding as well"
	).is_less(0.2)


## Containment moves the camera by writing its transform, and that write used to outlive
## the look that needed it. Every glance downward left the camera a little further into
## the back of his head, and levelling the view never brought it back.
func test_a_look_leaves_the_camera_where_it_found_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var train: Node = runner.scene()
	var camera: Camera3D = train.get_node("Screen/Frame/World/Player/Boom/Mount/Camera3D")
	var rested := camera.position

	train._control.accumulate_look(Vector2(0.0, 260.0), 720.0)
	await runner.simulate_frames(10)
	train._control.set_update(false)
	train._intent.pitch_units = 0.0
	train._intent.recentring_view = true
	await runner.simulate_frames(150)

	assert_vector(camera.position).override_failure_message(
		"the camera never came back to its mount, so the shoulder shot is now a haircut"
	).is_equal_approx(rested, Vector3.ONE * 0.001)


## The crosshair used to read the mouse itself, which meant a thumb on a touchscreen
## aimed at nothing. It reads the intent now, and the intent knows a look stick is a
## look whoever is holding it.
func test_the_look_stick_raises_the_look_the_crosshair_watches() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(6)
	var train: Node = runner.scene()

	assert_bool(train._intent.holding_look).override_failure_message(
		"a look was already underway with nothing touching the screen"
	).is_false()

	train._control.look_stick = Vector2(0.6, 0.0)
	await runner.simulate_frames(1)
	assert_bool(train._intent.holding_look).override_failure_message(
		"a thumb on the look stick did not count as looking, so the crosshair stays hidden on touch"
	).is_true()


## He is carried rather than dropped: the walk pins Y to the deck he can see, which sits
## a metre and a quarter above the collision floor. A jump has to be an offset on that
## pin, or landing puts him through the floorboards and onto the underframe.
func test_a_jump_leaves_the_deck_and_comes_back_to_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")
	var locomotion := _locomotion_of(train)
	train._control.set_update(false)
	var stood_at := locomotion.eye_height_metres

	train._intent.jump_requested = true
	await runner.simulate_frames(1)
	train._intent.jump_requested = false
	await runner.simulate_frames(8)

	assert_float(locomotion.height_above_stance_metres).override_failure_message(
		"pressing jump did not take him off the deck"
	).is_greater(0.05)
	assert_bool(locomotion.airborne()).is_true()

	await runner.simulate_frames(90)
	assert_float(locomotion.height_above_stance_metres).override_failure_message(
		"he never came down, so the jump has no gravity on it"
	).is_equal_approx(0.0, 0.001)
	assert_float(player.position.y).override_failure_message(
		"he landed somewhere other than the deck he left"
	).is_equal_approx(stood_at, 0.01)


## Holding the key down is not a request to keep jumping, and a second press in the air
## is not a second jump.
func test_he_cannot_jump_again_while_he_is_still_up() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	var locomotion := _locomotion_of(train)
	train._control.set_update(false)

	train._intent.jump_requested = true
	await runner.simulate_frames(6)
	var rising := locomotion.rise_metres_per_second
	await runner.simulate_frames(2)

	assert_float(locomotion.rise_metres_per_second).override_failure_message(
		"the jump was re-fired in mid air, so holding space floats him"
	).is_less(rising)


## A debug run takes the window focus the moment it launches. Reading devices straight
## away meant the keys meant for the editor behind it went into walking the character
## around instead.
func test_an_inert_run_ignores_the_keyboard_until_it_is_clicked_into() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(6)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")
	train._control.engaged = false

	var stood_at := player.position.x
	runner.simulate_action_press("move_up")
	await runner.simulate_frames(8)
	runner.simulate_action_release("move_up")

	assert_float(player.position.x).override_failure_message(
		"an inert run walked the character anyway, so it is still eating the keyboard"
	).is_equal_approx(stood_at, 0.001)

	train._control.engaged = true
	runner.simulate_action_press("move_up")
	await runner.simulate_frames(8)
	runner.simulate_action_release("move_up")
	assert_float(absf(player.position.x - stood_at)).override_failure_message(
		"clicking into the run did not hand the keyboard back"
	).is_greater(0.01)


## The legs cycle is a question that only makes sense with feet on the floor, so leaving
## it has to change what the whole body is playing, not just how fast.
func test_a_jump_walks_the_body_through_its_postures() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	train._control.set_update(false)
	var posture: CPosture = train._posture
	var seen: Array[StringName] = []

	assert_str(posture.state).override_failure_message(
		"standing on the deck should be afoot"
	).is_equal(CPosture.AFOOT)

	train._intent.jump_requested = true
	await runner.simulate_frames(2)
	train._intent.jump_requested = false

	# polled rather than counted: the flight is six tenths of a second at 0.45m, and a
	# frame count that assumes 60 of them is a test that fails on a slow machine
	for i in 240:
		await runner.simulate_frames(1)
		if seen.is_empty() or seen[-1] != posture.state:
			seen.append(posture.state)
		if seen.size() >= 2 and posture.state == CPosture.AFOOT:
			break

	assert_array(seen).override_failure_message(
		"the jump did not pass through launch, fall and landing in that order: %s" % [seen]
	).is_equal([CPosture.LAUNCHING, CPosture.AIRBORNE, CPosture.LANDING, CPosture.AFOOT])


## Asking a transition for the state it is already in restarts the crossfade, so a
## request every frame is a clip that never gets past its first frame.
func test_a_posture_is_only_requested_when_it_changes() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	var posture: CPosture = train._posture

	posture.requested = &"deliberately wrong"
	await runner.simulate_frames(1)
	assert_str(posture.requested).override_failure_message(
		"a changed state was not passed on to the rig"
	).is_equal(posture.state)

	await runner.simulate_frames(20)
	assert_str(posture.requested).is_equal(posture.state)


## Planting the feet is only meaningful with weight on them. Held on through a jump it
## drags the legs back down to a deck that is no longer under him.
func test_the_feet_stop_being_planted_in_the_air() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	train._control.set_update(false)
	var planting: CFootPlanting = train._foot_planting

	assert_float(planting.weight).override_failure_message(
		"standing on the deck, the feet should be held to it"
	).is_equal_approx(1.0, 0.01)

	train._intent.jump_requested = true
	await runner.simulate_frames(2)
	train._intent.jump_requested = false

	# the lightest it gets over the whole flight, rather than its value at some frame
	# count that assumes sixty of them a second: under load the jump is over by then
	var lightest := 1.0
	for i in 240:
		await runner.simulate_frames(1)
		lightest = minf(lightest, planting.weight)
		if planting.weight > 0.99 and train._posture.state == CPosture.AFOOT and i > 4:
			break
	assert_float(lightest).override_failure_message(
		"the feet were still being pulled to the deck while he was off it"
	).is_less(0.2)
	assert_float(planting.weight).override_failure_message(
		"the feet never went back to being planted after landing"
	).is_equal_approx(1.0, 0.01)


## One key answers whatever is in reach, and a bench answers it by being sat on.
func test_pressing_use_beside_a_bench_sits_him_on_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")
	train._control.set_update(false)
	var seating: CSeating = train._seating
	var stood_eye: float = train._locomotion.eye_height_metres

	train._intent.interact_requested = true
	await runner.simulate_frames(2)
	train._intent.interact_requested = false
	await _fold_over(runner, seating)

	assert_bool(seating.seated).override_failure_message(
		"pressing use beside a bench did not sit him down"
	).is_true()
	assert_object(seating.seat).is_not_null()
	assert_object(seating.seat.taken_by).override_failure_message(
		"he sat down without the seat knowing about it"
	).is_same(seating)
	assert_float(train._locomotion.eye_height_metres).override_failure_message(
		"his eye did not drop, so he is standing at seat height rather than sitting"
	).is_less(stood_eye - 0.2)
	assert_array(CPosture.SEATED_STATES).override_failure_message(
		"sitting down did not put him in any of the sitting clips"
	).contains([train._posture.state])

	train._intent.interact_requested = true
	await runner.simulate_frames(2)
	train._intent.interact_requested = false
	await _fold_over(runner, seating)
	assert_bool(seating.seated).override_failure_message(
		"the same key should have got him up again"
	).is_false()
	assert_float(train._locomotion.eye_height_metres).override_failure_message(
		"standing up left his eye where he had been sitting"
	).is_equal_approx(stood_eye, 0.001)


## Waits out the walk in and the fold that follows it, or the stand-up. Polled rather
## than counted in frames: the clips are a second and a bit of real time, and how many
## frames that is depends on what else the machine is doing.
func _fold_over(runner: GdUnitSceneRunner, seating: CSeating) -> void:
	for _i in 400:
		if not seating.busy():
			return
		await runner.simulate_frames(1)


## Waits for the walk to end and the fold to begin, which is where the old sit started.
func _at_the_bench(runner: GdUnitSceneRunner, seating: CSeating) -> void:
	for _i in 400:
		if not seating.approaching:
			return
		await runner.simulate_frames(1)


## Sitting down is a second of clip, and for that second he is neither in the aisle nor
## on the cushion. Before there was a sit-down clip he was on the bench on the frame he
## asked, which read as a teleport with an animation played after it.
func test_sitting_down_is_carried_rather_than_snapped() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")
	train._control.set_update(false)
	var seating: CSeating = train._seating
	var stood_at: Vector3 = player.global_position

	train._intent.interact_requested = true
	await runner.simulate_frames(2)
	train._intent.interact_requested = false

	assert_bool(seating.approaching).override_failure_message(
		"he should be walking to the bench, not already folding onto it"
	).is_true()
	assert_str(String(train._posture.state)).override_failure_message(
		"the walk in should be walked, on the walking clip"
	).is_equal(String(CPosture.AFOOT))

	await _at_the_bench(runner, seating)
	assert_bool(seating.moving()).override_failure_message(
		"the fold never began once he had walked in"
	).is_true()
	assert_str(String(train._posture.state)).override_failure_message(
		"the sit-down clip should be playing while he folds"
	).is_equal(String(CPosture.SEATING))
	assert_float(player.global_position.distance_to(stood_at)).override_failure_message(
		"he arrived at the seat on the frame he asked for it"
	).is_greater(0.0)

	await _fold_over(runner, seating)
	assert_bool(seating.seated).is_true()
	assert_float(Vector2(player.global_position.x, player.global_position.z).distance_to(
		Vector2(seating.moving_to.x, seating.moving_to.z))
	).override_failure_message(
		"the fold finished somewhere other than the seat it was aimed at"
	).is_less(0.02)


## The sit-down clip is authored for a body already standing in front of a bench. Begun
## from wherever [F] was pressed, it carried him the last metre with his feet planted,
## which is a man being dragged onto a seat rather than taking one. So he walks in first,
## on his own legs, and folds only once he is standing where the clip expects.
func test_he_walks_the_last_step_to_the_bench_before_folding() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")
	train._control.set_update(false)
	var seating: CSeating = train._seating

	# stood in the aisle, a little to one side so which bench is nearest is not a
	# coin toss between the pair facing each other across it
	var bench: CSeat = _nearest_free_seat(player)
	assert_object(bench).is_not_null()
	player.global_position = Vector3(bench.at.x,
		train._locomotion.eye_height_metres, signf(bench.at.z) * 0.2)
	await runner.simulate_frames(2)

	train._intent.interact_requested = true
	await runner.simulate_frames(2)
	train._intent.interact_requested = false

	var strode := 0.0
	for _i in 400:
		if not seating.approaching:
			break
		# both axes: the last step to a bench is as often a sidestep as a stride, and the
		# blend space has clips for either
		strode = maxf(strode, Vector2(train._locomotion.strafe_metres_per_second,
			train._locomotion.forward_metres_per_second).length())
		await runner.simulate_frames(1)
	assert_float(strode).override_failure_message(
		"he crossed the last step without a stride, so the feet skated"
	).is_greater(0.15)

	var stopped := Vector2(player.global_position.x - bench.at.x,
		player.global_position.z - bench.at.z).length()
	assert_float(stopped).override_failure_message(
		"the fold began %.2fm from the cushion rather than the %.2fm the clip wants"
		% [stopped, seating.stand_off_metres]
	).is_equal_approx(seating.stand_off_metres, 0.2)
	assert_float(absf(angle_difference(train._locomotion.facing_radians,
		bench.facing_radians))).override_failure_message(
		"he began folding without being square to the bench"
	).is_less_equal(seating.approach_arrive_radians)

	await _fold_over(runner, seating)
	assert_bool(seating.seated).is_true()
	assert_object(seating.seat).is_same(bench)


## However badly the walk goes, it ends. A bench reached around somebody who will not
## move is still a bench he asked to sit on.
func test_a_walk_that_cannot_arrive_still_ends_in_a_seat() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	train._control.set_update(false)
	var seating: CSeating = train._seating

	train._intent.interact_requested = true
	await runner.simulate_frames(2)
	train._intent.interact_requested = false
	assert_bool(seating.approaching).is_true()
	# walking on the spot: the spot he is walking to is one he can never reach
	seating.approach_at = Vector3(9999.0, 0.0, 9999.0)

	await _fold_over(runner, seating)
	assert_bool(seating.seated).override_failure_message(
		"a walk that never arrived left him on his feet holding a seat"
	).is_true()


func _nearest_free_seat(player: CharacterBody3D) -> CSeat:
	var found: CSeat = null
	var nearest := INF
	for seat: CSeat in Ecs.world.view(&"CSeat"):
		if not seat.free_to_take():
			continue
		var away := Vector2(seat.at.x - player.global_position.x,
			seat.at.z - player.global_position.z).length()
		if away < nearest:
			nearest = away
			found = seat
	return found


## The bench is not free the moment he asks to get up: there is a second of stand-up
## still to play, and a seat handed back at the start of it is one somebody else can
## take while a body is still coming out of it.
func test_the_seat_is_held_until_the_stand_up_finishes() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	train._control.set_update(false)
	var seating: CSeating = train._seating

	train._intent.interact_requested = true
	await runner.simulate_frames(2)
	train._intent.interact_requested = false
	await _fold_over(runner, seating)
	var bench: CSeat = seating.seat
	assert_object(bench).is_not_null()

	train._intent.interact_requested = true
	await runner.simulate_frames(2)
	train._intent.interact_requested = false
	assert_bool(seating.rising_seconds_left > 0.0).override_failure_message(
		"the stand-up clip should be playing before he is up"
	).is_true()
	assert_str(String(train._posture.state)).is_equal(String(CPosture.RISING))
	assert_object(bench.taken_by).override_failure_message(
		"the bench was given away with a body still getting off it"
	).is_same(seating)

	await _fold_over(runner, seating)
	assert_bool(bench.free_to_take()).override_failure_message(
		"the bench was never handed back once he was up"
	).is_true()


## The phone build has no keys. A thumb tapped on the walking half is the same request
## the space bar makes, and it has to arrive as one: the character leaves the floor.
func test_a_tap_on_the_walking_half_gets_him_off_the_floor() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	var thumbs: TouchControls = train._thumbs
	thumbs.visible = true
	thumbs.size = Vector2(1600.0, 720.0)

	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = Vector2(1200.0, 500.0)
	down.pressed = true
	thumbs._input(down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = down.position
	thumbs._input(up)

	var left_the_floor := false
	for _i in 60:
		await runner.simulate_frames(1)
		if train._locomotion.airborne():
			left_the_floor = true
			break
	assert_bool(left_the_floor).override_failure_message(
		"a tap on the walking half never reached the jump").is_true()


## A bench with somebody already on it is not somewhere to sit, however close it is.
func test_a_taken_seat_is_not_offered_twice() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	var player: CharacterBody3D = train.get_node("Screen/Frame/World/Player")
	train._control.set_update(false)

	var somebody_else := CSeating.new()
	var taken := 0
	for seat: CSeat in Ecs.world.view(&"CSeat"):
		if Vector2(player.global_position.x - seat.at.x,
				player.global_position.z - seat.at.z).length() < train._seating.reach_metres:
			seat.taken_by = somebody_else
			taken += 1
	assert_int(taken).override_failure_message(
		"no seat was within reach to begin with, so this proves nothing"
	).is_greater(0)

	train._intent.interact_requested = true
	await runner.simulate_frames(2)
	train._intent.interact_requested = false

	assert_bool(train._seating.seated).override_failure_message(
		"he sat in a seat that somebody else was already in"
	).is_false()


## Sitting still is what most of this cast does for most of the run, and one looping
## clip across a carriage of them reads as a row of clockwork.
func test_a_seated_character_moves_between_the_sitting_clips() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	train._control.set_update(false)

	train._intent.interact_requested = true
	await runner.simulate_frames(2)
	await _fold_over(runner, train._seating)
	assert_bool(train._seating.seated).is_true()

	var idle: CSeatedIdle = train._seated_idle
	idle.shortest_seconds = 0.02
	idle.longest_seconds = 0.05
	# the first interval was rolled from the real bounds when he sat down, so it has to
	# be spent as well or the test waits five seconds for a change it asked to be quick
	idle.seconds_until_change = 0.0
	var seen: Array[StringName] = []
	for i in 200:
		await runner.simulate_frames(1)
		if not seen.has(idle.state):
			seen.append(idle.state)
		if seen.size() >= 3:
			break

	assert_int(seen.size()).override_failure_message(
		"the sitting clip never changed, so a carriage of passengers breathes in time"
	).is_greater(1)
	for state: StringName in seen:
		assert_array(CPosture.SEATED_STATES).override_failure_message(
			"%s is not a sitting clip, so somebody stood up while seated" % state
		).contains([state])
	assert_str(train._posture.state).override_failure_message(
		"the posture did not follow the idle onto the clip it chose"
	).is_equal(idle.state)


## Standing up has to put the idle back, or the next time he sits down it starts
## halfway through a nod.
func test_standing_up_resets_the_sitting_clip() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(10)
	var train: Node = runner.scene()
	train._control.set_update(false)
	var idle: CSeatedIdle = train._seated_idle

	train._intent.interact_requested = true
	await runner.simulate_frames(2)
	await _fold_over(runner, train._seating)
	idle.state = CPosture.SEATED_NODDING
	train._intent.interact_requested = true
	await runner.simulate_frames(4)

	assert_bool(train._seating.seated).is_false()
	assert_str(idle.state).override_failure_message(
		"he stood up still nodding, and will sit back down mid-nod"
	).is_equal(CPosture.SEATED)
