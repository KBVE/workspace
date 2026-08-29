# GdUnitTestSuite
extends GdUnitTestSuite

## Where in the blend space a body's legs are.
##
## Exercised only through the player's own walk until now, which covers the forward
## half of a space with nine clips in it. Both axes matter: the blend space is the only
## thing that knows the legs are meant to be crossing rather than striding, and fed
## forward speed alone a sidestep played the standing clip and the character slid
## sideways on his heels.

const SCENE := "res://scenes/train/train.scn"


func _animation() -> SCharacterAnimation:
	return Ecs.runner.get_system(&"character_animation")


## Somebody whose rig has actually been built. Most of the cast are components with no
## body: [SCastBody] builds a rig when the carriage comes into view and throws it away
## again when it does not, so the first entity in the view is usually nobody to look at.
func _walker() -> Dictionary:
	for entry: Dictionary in Ecs.world.multi_view([CLocomotion, CGait, CCharacterRig]):
		if entry[&"CCharacterRig"].live() != null:
			return entry
	return {}


## Long enough that the lerp has arrived: the blend chases the wanted position rather
## than jumping to it, so a knocked-back step does not snap the legs between clips.
func _settle(system: SCharacterAnimation, locomotion: CLocomotion, gait: CGait,
		rig: CharacterRig) -> void:
	for _step in range(40):
		system._step(locomotion, gait, rig, 0.05)


func test_walking_forward_puts_the_legs_forward() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var walker := _walker()
	var gait: CGait = walker[&"CGait"]
	var locomotion: CLocomotion = walker[&"CLocomotion"]
	locomotion.forward_metres_per_second = gait.walk_clip_metres_per_second
	locomotion.strafe_metres_per_second = 0.0
	_settle(_animation(), locomotion, gait, walker[&"CCharacterRig"].live())

	assert_float(gait.blend.y).override_failure_message(
		"a body walking forward is standing still in the blend space").is_greater(0.5)
	assert_float(absf(gait.blend.x)).is_less(0.1)


## The one this system carries a comment about. Fed forward speed alone, a sidestep
## played the standing clip and the character slid sideways on his heels.
func test_a_sidestep_is_a_sidestep_and_not_a_stand() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var walker := _walker()
	var gait: CGait = walker[&"CGait"]
	var locomotion: CLocomotion = walker[&"CLocomotion"]
	locomotion.forward_metres_per_second = 0.0
	locomotion.strafe_metres_per_second = gait.walk_clip_metres_per_second
	_settle(_animation(), locomotion, gait, walker[&"CCharacterRig"].live())

	assert_float(gait.blend.x).override_failure_message(
		"a body crossing its legs sideways is at %s in the blend space, which is the "
		% gait.blend + "standing clip").is_greater(0.5)


func test_standing_still_is_the_middle_of_the_space() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var walker := _walker()
	var gait: CGait = walker[&"CGait"]
	var locomotion: CLocomotion = walker[&"CLocomotion"]
	locomotion.forward_metres_per_second = 0.0
	locomotion.strafe_metres_per_second = 0.0
	_settle(_animation(), locomotion, gait, walker[&"CCharacterRig"].live())

	assert_float(gait.blend.length()).override_failure_message(
		"a body standing still has its legs at %s" % gait.blend).is_less(0.05)


## The space is a unit square with the clips on its edges. Running does not put the legs
## outside it -- there is nothing out there, and the blend would read as the corner.
func test_running_does_not_leave_the_blend_space() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var walker := _walker()
	var gait: CGait = walker[&"CGait"]
	var locomotion: CLocomotion = walker[&"CLocomotion"]
	locomotion.forward_metres_per_second = gait.walk_clip_metres_per_second * 40.0
	locomotion.strafe_metres_per_second = gait.walk_clip_metres_per_second * 40.0
	_settle(_animation(), locomotion, gait, walker[&"CCharacterRig"].live())

	assert_float(gait.blend.length()).override_failure_message(
		"the legs are at %s, which is off the edge of the space" % gait.blend
	).is_less_equal(1.001)


## Chased rather than jumped to. A knocked-back step that snapped the legs between
## clips reads as a stumble the body never took.
func test_the_legs_are_chased_rather_than_snapped_to() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var walker := _walker()
	var gait: CGait = walker[&"CGait"]
	var locomotion: CLocomotion = walker[&"CLocomotion"]
	var rig: CharacterRig = walker[&"CCharacterRig"].live()

	locomotion.forward_metres_per_second = 0.0
	locomotion.strafe_metres_per_second = 0.0
	_settle(_animation(), locomotion, gait, rig)

	locomotion.forward_metres_per_second = gait.walk_clip_metres_per_second
	_animation()._step(locomotion, gait, rig, gait.blend_seconds * 0.25)
	assert_float(gait.blend.y).override_failure_message(
		"one quarter of the blend time took the legs all the way to %f" % gait.blend.y
	).is_less(0.9)
	assert_float(gait.blend.y).override_failure_message(
		"the legs did not move at all").is_greater(0.0)


## How fast the clip runs, so a slow walk is not the same footfalls played quietly. It
## is bounded either way: past the top the legs blur, and under the bottom a body
## drifting at a centimetre a second cycles a whole stride.
func test_the_clip_keeps_pace_within_its_bounds() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var walker := _walker()
	var gait: CGait = walker[&"CGait"]
	assert_float(gait.time_scale_limits.x).is_greater(0.0)
	assert_float(gait.time_scale_limits.y).is_greater(gait.time_scale_limits.x)

	var locomotion: CLocomotion = walker[&"CLocomotion"]
	var rig: CharacterRig = walker[&"CCharacterRig"].live()
	locomotion.forward_metres_per_second = gait.walk_clip_metres_per_second * 100.0
	_animation()._step(locomotion, gait, rig, 0.05)
	var raced: float = rig.animation_tree.get(CharacterRig.TIME_SCALE_PARAMETER)
	assert_float(raced).is_between(gait.time_scale_limits.x, gait.time_scale_limits.y)

	locomotion.forward_metres_per_second = 0.001
	_animation()._step(locomotion, gait, rig, 0.05)
	var crawled: float = rig.animation_tree.get(CharacterRig.TIME_SCALE_PARAMETER)
	assert_float(crawled).is_between(gait.time_scale_limits.x, gait.time_scale_limits.y)


## The clips were authored for a body of one size and the rigs are scaled to the
## stature they were given, so how fast the legs cycle has to answer to that scale --
## a tall man and a short one at the same speed do not take the same number of steps.
func test_a_scaled_body_cycles_its_legs_to_its_own_size() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var walker := _walker()
	var rig: CharacterRig = walker[&"CCharacterRig"].live()
	assert_float(rig.model_scale).override_failure_message(
		"the rig reports no scale, so the clips are timed against a body of no size"
	).is_greater(0.0)
