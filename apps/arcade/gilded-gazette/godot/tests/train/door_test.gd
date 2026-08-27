# GdUnitTestSuite
extends GdUnitTestSuite

## Drives the whole path the player does: an [F] edge on CInput, through SDoor,
## into a leaf that has actually turned. Asserting on CDoor alone would pass with
## the mesh nailed shut.

const SCENE := "res://scenes/train/train.scn"
const WORLD := "Screen/Frame/World"


func _train(runner: GdUnitSceneRunner) -> Node:
	return runner.scene()


func _leaves(train: Node) -> Array[Node3D]:
	return train.get_node(WORLD + "/Consist").door_leaves()


## The CDoor behind each leaf, in the same order, so a test can say what the door
## itself thinks as well as where its mesh ended up.
func _doors(train: Node) -> Array[CDoor]:
	var found: Array[CDoor] = []
	for leaf: Node3D in _leaves(train):
		for entry: Dictionary in Ecs.world.multi_view([CDoor, ECSViewComponent]):
			if entry[&"ECSViewComponent"].view == leaf:
				found.append(entry[&"CDoor"])
				break
	return found


## Waits for the leaf to stop moving rather than for a frame count. The swing takes
## CDoor.seconds_to_swing, the runner's frames are not that long, and a fixed count
## was passing or failing on where in the arc it happened to stop.
func _await_still(runner: GdUnitSceneRunner, leaf: Node3D) -> float:
	var last := leaf.rotation.y
	for _i in range(240):
		await runner.simulate_frames(4)
		if is_equal_approx(leaf.rotation.y, last):
			return leaf.rotation.y
		last = leaf.rotation.y
	return leaf.rotation.y


func test_every_carriage_hangs_two_doors() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var train := _train(runner)
	var consist: Node = train.get_node(WORLD + "/Consist")
	assert_int(_leaves(train).size()).override_failure_message(
		"expected two doors per carriage across %d carriages" % consist.carriage_count
	).is_equal(consist.carriage_count * 2)


## The hinge is the whole reason the leaf was given its own origin. If the origin
## drifts back to the mesh centre the door still rotates, it just sweeps through
## the end wall while doing it.
func test_a_leaf_turns_on_its_hinge_not_its_middle() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var leaf := _leaves(_train(runner))[0] as VisualInstance3D
	assert_object(leaf).override_failure_message(
		"the door leaf is not a VisualInstance3D, so nothing draws it").is_not_null()
	var aabb: AABB = leaf.get_aabb()
	# a hinged leaf has one edge on the origin and the rest of its width to one
	# side; a leaf origin-centred would sit half either way
	var nearest_edge := minf(absf(aabb.position.z), absf(aabb.position.z + aabb.size.z))
	assert_float(nearest_edge).override_failure_message(
		"neither edge of the leaf is on its origin, so it would sweep through the "
		+ "end wall rather than swing in the doorway"
	).is_less(0.10)


func test_f_opens_the_door_the_player_is_standing_at() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var train := _train(runner)
	var leaf := _leaves(train)[0]
	var player: Node3D = train.get_node(WORLD + "/Player")

	# SPlayerControl rewrites CInput from real devices every frame, so it has to
	# stand down before the intent below survives to reach SDoor
	train._control.set_update(false)
	# stand at the leaf rather than walk to it: the walk is SLocomotion's to test
	player.global_position = leaf.global_position + Vector3(0.0, 1.2, 0.0)
	var before := leaf.rotation.y
	train._intent.interact_requested = true
	await runner.simulate_frames(1)
	train._intent.interact_requested = false
	await _await_still(runner, leaf)

	assert_float(absf(leaf.rotation.y - before)).override_failure_message(
		"the nearest door did not move when the player asked it to"
	).is_greater(0.5)


func test_a_door_out_of_reach_stays_shut() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var train := _train(runner)
	var leaf := _leaves(train)[0]
	var player: Node3D = train.get_node(WORLD + "/Player")

	train._control.set_update(false)
	# The leaf answers to two systems, and only one of them is the key: [SDoorTraffic]
	# holds a door open for anybody walking through it, so a passenger who happens to
	# be crossing this vestibule swings it with nobody having pressed anything. That
	# is its own suite's to check. What is under test here is the reach, so for the
	# length of it the traffic is not running.
	#
	# Taking the system away freezes the count rather than clearing it, because the
	# recount from nothing every tick is the system's own doing: whatever it last saw
	# stays written, and a door held open at that moment stays held for the rest of
	# the test. So the doors are let go by hand, and the leaf is given the time to
	# finish shutting before anything is measured against it.
	Ecs.remove_system(&"door_traffic")
	for held: CDoor in _doors(train):
		held.held_open_by = 0
	await _await_still(runner, leaf)

	player.global_position = leaf.global_position + Vector3(60.0, 0.0, 0.0)
	var door: CDoor = _doors(train)[0]
	var before := leaf.rotation.y
	train._intent.interact_requested = true
	await runner.simulate_frames(1)
	train._intent.interact_requested = false
	await runner.simulate_frames(20)

	assert_bool(door.is_open).override_failure_message(
		"a door sixty metres away answered the key"
	).is_false()
	assert_float(leaf.rotation.y).override_failure_message(
		"the leaf sixty metres away turned with the door still shut (held by %d)"
		% door.held_open_by
	).is_equal_approx(before, 0.001)


## A collider that does not turn with the leaf is worse than none: the doorway
## stays blocked after the door has visibly swung out of it, and the player is shut
## in by something they can see is open.
func test_the_collider_swings_with_the_leaf() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var train := _train(runner)
	var leaf := _leaves(train)[0]
	var shape := leaf.get_node("Collision").get_child(0) as CollisionShape3D
	assert_object(shape).override_failure_message(
		"the door leaf carries no collision, so it is scenery"
	).is_not_null()

	var shut_at := shape.global_position
	train._control.set_update(false)
	var player: Node3D = train.get_node(WORLD + "/Player")
	player.global_position = leaf.global_position + Vector3(0.0, 1.2, 0.0)
	train._intent.interact_requested = true
	await runner.simulate_frames(1)
	train._intent.interact_requested = false
	await _await_still(runner, leaf)

	assert_float(shape.global_position.distance_to(shut_at)).override_failure_message(
		"the collision stayed put while the leaf swung, so the doorway is still shut"
	).is_greater(0.4)


## The doorway has to be filled when the door is, or the wall is a hole with a
## picture of a door over it.
func test_a_shut_door_fills_its_doorway() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var leaf := _leaves(_train(runner))[0]
	var shape := leaf.get_node("Collision").get_child(0) as CollisionShape3D
	var box := shape.shape as BoxShape3D
	assert_object(box).is_not_null()
	assert_float(box.size.z).override_failure_message(
		"the leaf is narrower than the %.2fm doorway it is meant to fill"
		% (Consist.DOORWAY_HALF_Z * 2.0)
	).is_greater_equal(Consist.DOORWAY_HALF_Z * 2.0 - 0.05)
	assert_float(box.size.y).override_failure_message(
		"the leaf is shorter than its doorway, so the player steps over it"
	).is_greater_equal(Consist.DOORWAY_HEIGHT - 0.05)


## The point of the whole exercise: shut it stops you, open it lets you past.
##
## A shape query rather than a walk, because walking is SLocomotion's and a query
## asks the physics server the same question the capsule would without depending on
## anything else being finished.
func test_the_doorway_is_blocked_shut_and_clear_open() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var train := _train(runner)
	var leaf := _leaves(train)[0]
	var door: CDoor = _doors(train)[0]
	var player: Node3D = train.get_node(WORLD + "/Player")

	# [SDoorTraffic] holds a door open for anybody crossing the vestibule, and it
	# rewrites the leaf's rotation through [SDoor] every tick. Both halves of this
	# test say where the leaf is, so the traffic stands down and the doors are let
	# go by hand for the length of it.
	train._control.set_update(false)
	Ecs.remove_system(&"door_traffic")
	for held: CDoor in _doors(train):
		held.held_open_by = 0
	await _await_still(runner, leaf)

	var centre := leaf.global_position \
		+ leaf.global_transform.basis.z * -(Consist.DOORWAY_HALF_Z) \
		+ Vector3(0.0, 1.2, 0.0)
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.6
	query.shape = capsule
	query.transform = Transform3D(Basis(), centre)
	query.exclude = [player.get_rid()]
	var space := player.get_world_3d().direct_space_state

	assert_int(space.intersect_shape(query, 8).size()).override_failure_message(
		"nothing fills the doorway with the door shut, so the door stops nobody"
	).is_greater(0)

	# Put at full open rather than pressed and waited for. Whether the swing gets
	# there is CDoor's, and tested above; what is in question here is where the leaf
	# ends up. Waiting a fixed number of frames caught it at 61 degrees, still across
	# the doorway, and the test passed or failed on where in the arc it stopped.
	#
	# Driven through CDoor rather than by turning the mesh, because [SDoor] writes
	# the leaf's rotation from the swing every tick and puts a hand-turned leaf
	# straight back where the component says it should be.
	door.is_open = true
	door.swing = 1.0
	leaf.rotation.y = door.open_radians * door.swing_sign
	await runner.simulate_frames(2)

	assert_int(space.intersect_shape(query, 8).size()).override_failure_message(
		"the doorway is still blocked with the leaf fully open, so it is in the way"
	).is_equal(0)


## A door that opens into the player sweeps them down the aisle and wedges them in
## the corner between the end wall and the side wall, where the leaf is still
## overlapping them and depenetration will not let go.
##
## Standing on both sides in turn, because the answer has to be right from either.
func test_the_leaf_never_opens_into_the_player() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var train := _train(runner)
	var player: Node3D = train.get_node(WORLD + "/Player")
	train._control.set_update(false)

	for side: float in [1.0, -1.0]:
		var leaf := _leaves(train)[0]
		leaf.rotation.y = 0.0
		await runner.simulate_frames(1)
		# a stride back from the leaf, on one side of it then the other
		var stand := leaf.global_position + Vector3(side * 1.1, 1.2, -0.5)
		player.global_position = stand
		train._intent.interact_requested = true
		await runner.simulate_frames(1)
		train._intent.interact_requested = false
		await runner.simulate_frames(90)

		var swept := leaf.get_node("Collision").get_child(0) as CollisionShape3D
		var box := (swept.shape as BoxShape3D).size
		var query := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.38
		capsule.height = 1.6
		query.shape = capsule
		query.transform = Transform3D(Basis(), stand)
		query.exclude = [player.get_rid()]
		var hits := player.get_world_3d().direct_space_state.intersect_shape(query, 8)
		var swept_into := hits.any(func(h: Dictionary) -> bool:
			return (h["collider"] as Node).get_parent() == leaf)
		assert_bool(swept_into).override_failure_message(
			"the leaf opened into where the player was standing on side %.0f, "
			% side + "which is what wedges them in the corner (leaf %.2fm wide)"
			% box.z
		).is_false()
