# GdUnitTestSuite
extends GdUnitTestSuite

## The train's voice.
##
## Nothing here listens to anything: a headless run has no audio driver and [SSound] is
## switched off in one, which is deliberate. What is checked is the deciding -- that the
## bank is complete, that a door is heard on the crossing rather than while it is across,
## that feet go down by distance covered rather than on a timer, and that a loop is
## stopped rather than merely quietened when it goes out of earshot.

const SCENE := "res://scenes/train/train.scn"


func _sound() -> SSound:
	return Ecs.runner.get_system(&"sound")


func test_every_sound_in_the_bank_is_a_file_that_exists() -> void:
	for key: StringName in SSound.BANK:
		var path := "%s/%s.wav" % [SSound.BANK_DIR, SSound.BANK[key]["file"]]
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"'%s' names %s, which is not there -- run tools/gen-sounds.py" % [key, path]
		).is_true()


## A bed that stops after two seconds is heard as the engine cutting out, and the loop
## flag is not in the import: it is set on load, because that is the only place that
## knows which of these is a bed and which is a bang.
func test_the_beds_loop_and_the_bangs_do_not() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var sound := _sound()
	for key: StringName in SSound.BANK:
		var stream: AudioStreamWAV = sound._streams[key]
		assert_object(stream).override_failure_message(
			"'%s' did not load" % key).is_not_null()
		if SSound.BANK[key]["loops"]:
			assert_int(stream.loop_mode).override_failure_message(
				"'%s' is a bed and stops dead at the end of the file" % key
			).is_equal(AudioStreamWAV.LOOP_FORWARD)
		else:
			assert_int(stream.loop_mode).override_failure_message(
				"'%s' is a one-shot and repeats forever" % key
			).is_equal(AudioStreamWAV.LOOP_DISABLED)


func test_a_headless_run_makes_no_sound() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	assert_bool(_sound().enabled).override_failure_message(
		"the tests asked an audio driver that is not there for a voice"
	).is_false()


## Every carriage rumbles and every carriage hisses, or the train has quiet cars in it
## for no reason anybody can hear.
func test_every_carriage_has_a_voice() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var heard := {}
	for entry: Dictionary in Ecs.world.multi_view([CNoise, ECSViewComponent]):
		var sound: StringName = entry[&"CNoise"].sound
		heard[sound] = int(heard.get(sound, 0)) + 1
	var carriages := GameContent.carriage_locations().size()
	for bed: StringName in [&"carriage_rumble", &"gas_hiss", &"rail_joints"]:
		assert_int(int(heard.get(bed, 0))).override_failure_message(
			"'%s' is heard in %d of %d carriages" % [bed, int(heard.get(bed, 0)), carriages]
		).is_equal(carriages)


## Ten identical loops phase against each other, and the beat is heard as a fault in
## the audio rather than as ten carriages of train.
func test_no_two_carriages_rumble_at_the_same_pitch() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var pitches := {}
	for entry: Dictionary in Ecs.world.multi_view([CNoise, ECSViewComponent]):
		var noise: CNoise = entry[&"CNoise"]
		if noise.sound != &"carriage_rumble":
			continue
		pitches[noise.pitch] = true
	assert_int(pitches.size()).is_equal(GameContent.carriage_locations().size())


## The gas is on the carriage entity beside its lamp, so putting a carriage out puts
## its hiss out with it. A dark carriage that goes on hissing is the sound of a bug.
func test_lamps_out_is_gas_off() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var lit: Dictionary = Ecs.world.multi_view([CLamp, CNoise])[0]
	var lamp: CLamp = lit[&"CLamp"]
	var gas: CNoise = lit[&"CNoise"]
	assert_str(gas.sound).override_failure_message(
		"the sound tied to a carriage's lamp is '%s', which is not the gas" % gas.sound
	).is_equal(&"gas_hiss")

	lamp.dimming = 0.0
	await runner.simulate_frames(3)
	assert_float(gas.gain).override_failure_message(
		"a carriage with its lamps out went on hissing").is_equal(0.0)


## Heard through whatever is standing on the floor: a saloon is carpet, curtains and
## eight people, and a service car is a wooden box, and the joints come through it.
func test_a_bare_carriage_rides_louder_than_a_furnished_one() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var consist: Consist = runner.scene().get_node("Screen/Frame/World/Consist")

	var bare := -1.0
	var furnished := -1.0
	for entry: Dictionary in Ecs.world.multi_view([CNoise, ECSViewComponent]):
		var noise: CNoise = entry[&"CNoise"]
		if noise.sound != &"rail_joints":
			continue
		var at: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if at == null:
			continue
		var carriage := consist.carriage_index_at(at.global_position.x)
		if GameContent.furnishings_at(carriage).is_empty():
			bare = maxf(bare, noise.gain)
		else:
			furnished = maxf(furnished, noise.gain)

	assert_float(bare).override_failure_message(
		"no bare carriage was found to compare, so the train is furnished end to end"
	).is_greater(0.0)
	assert_float(furnished).override_failure_message(
		"no furnished carriage was found to compare").is_greater(0.0)
	assert_float(bare).override_failure_message(
		"a bare carriage rides at %f and a furnished one at %f" % [bare, furnished]
	).is_greater(furnished)


func test_everything_in_the_bank_goes_somewhere_a_slider_reaches() -> void:
	assert_int(AudioServer.get_bus_index(SSound.BUS)).override_failure_message(
		"'%s' is not a bus, so the options menu's slider moves nothing" % SSound.BUS
	).is_greater_equal(0)


## Distance, not time. The walk clips play at a time scale that answers to speed, so a
## footstep on a timer keeps its rhythm while the legs speed up -- which is heard
## immediately by somebody not even listening for it.
func test_a_foot_goes_down_every_stride_covered() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var sound := _sound()
	var walker: Dictionary = Ecs.world.multi_view(
		[CLocomotion, CFootsteps, CPosture, CCharacterRig])[0]
	var feet: CFootsteps = walker[&"CFootsteps"]
	var locomotion: CLocomotion = walker[&"CLocomotion"]
	var posture: CPosture = walker[&"CPosture"]

	posture.state = CPosture.AFOOT
	feet.since_metres = 0.0
	locomotion.forward_metres_per_second = 1.0
	sound._walk(feet.stride_metres * 0.5, Vector3.INF)
	assert_float(feet.since_metres).is_equal_approx(feet.stride_metres * 0.5, 0.001)

	var was := feet.other_foot
	sound._walk(feet.stride_metres * 0.6, Vector3.INF)
	assert_float(feet.since_metres).override_failure_message(
		"a stride was covered and no foot went down").is_less(feet.stride_metres * 0.5)
	assert_bool(feet.other_foot).override_failure_message(
		"the same foot went down twice, which is a limp").is_not_equal(was)


func test_a_body_off_its_feet_puts_none_of_them_down() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var sound := _sound()
	var walker: Dictionary = Ecs.world.multi_view(
		[CLocomotion, CFootsteps, CPosture, CCharacterRig])[0]
	var feet: CFootsteps = walker[&"CFootsteps"]
	walker[&"CLocomotion"].forward_metres_per_second = 3.0
	feet.since_metres = 0.0

	for state: StringName in [CPosture.SEATED, CPosture.AIRBORNE, CPosture.DEAD]:
		walker[&"CPosture"].state = state
		sound._walk(1.0, Vector3.INF)
		assert_float(feet.since_metres).override_failure_message(
			"a body in state '%s' was walking on the floor" % state).is_equal(0.0)


## A door is heard when the leaf crosses, not while it is across. One threshold each
## way, so a leaf resting near the middle does not bang open and shut every frame.
func test_a_door_is_heard_once_on_the_way_open() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var sound := _sound()
	var door: CDoor = Ecs.world.multi_view([CDoor, ECSViewComponent])[0][&"CDoor"]

	# Nothing is written down until something crosses: a train of shut doors that have
	# always been shut has never been heard, and recording them as shut would be a
	# frame's worth of state saying nothing happened.
	door.swing = 0.0
	sound._swing(Vector3.ZERO)
	assert_int(sound._door_was_open.size()).override_failure_message(
		"a door that has not moved was recorded as having done something").is_equal(0)

	door.swing = 1.0
	sound._swing(Vector3.ZERO)
	var opened := 0
	for was_open: bool in sound._door_was_open.values():
		if was_open:
			opened += 1
	assert_int(opened).override_failure_message(
		"the leaf swung wide and the door was never heard to open").is_equal(1)

	# Held open is not opening again. The crossing is the sound, not the state.
	var before := sound._door_was_open.duplicate()
	sound._swing(Vector3.ZERO)
	assert_dict(sound._door_was_open).override_failure_message(
		"a door standing open was heard to open a second time").is_equal(before)

	door.swing = 0.0
	sound._swing(Vector3.ZERO)
	for was_open: bool in sound._door_was_open.values():
		assert_bool(was_open).override_failure_message(
			"the leaf came back to the jamb and the door was never heard to shut"
		).is_false()


## Between the two thresholds is neither, so a leaf that wobbles is silent rather than
## banging open and shut with it.
func test_a_leaf_between_the_thresholds_says_nothing() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var sound := _sound()
	var door: CDoor = Ecs.world.multi_view([CDoor, ECSViewComponent])[0][&"CDoor"]

	door.swing = 0.0
	sound._swing(Vector3.ZERO)
	var shut := sound._door_was_open.duplicate()

	door.swing = (SSound.SWUNG_SHUT + SSound.SWUNG_OPEN) * 0.5
	sound._swing(Vector3.ZERO)
	assert_dict(sound._door_was_open).override_failure_message(
		"a door halfway through its swing was reported as having crossed"
	).is_equal(shut)


## Stopped, not turned down. A silent player is a voice held for something nobody can
## hear, and ten carriages of held voices is the pool gone before the player has walked
## anywhere.
func test_a_loop_out_of_earshot_is_stopped_rather_than_quietened() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var sound := _sound()
	sound.enabled = true
	var noise: CNoise = Ecs.world.multi_view([CNoise, ECSViewComponent])[0][&"CNoise"]
	var at: Node3D = Ecs.world.multi_view([CNoise, ECSViewComponent])[0][&"ECSViewComponent"].view

	sound._keep_the_loops(at.global_position)
	assert_int(sound._looping.size()).override_failure_message(
		"nothing was playing with the ear inside every carriage").is_greater(0)

	sound._keep_the_loops(at.global_position + Vector3.RIGHT * (noise.audible_within_metres * 10.0))
	assert_int(sound._looping.size()).override_failure_message(
		"%d loops were left running with nobody near enough to hear any of them"
			% sound._looping.size()).is_equal(0)
	sound.enabled = false


## Nobody there is not the same as somebody standing far away, and both are silent.
func test_nothing_plays_with_nobody_aboard() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var sound := _sound()
	sound.enabled = true
	sound._keep_the_loops(Vector3.INF)
	assert_int(sound._looping.size()).is_equal(0)
	sound.enabled = false
