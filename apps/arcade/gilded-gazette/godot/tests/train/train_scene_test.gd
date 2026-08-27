# GdUnitTestSuite
extends GdUnitTestSuite

const SCENE := "res://scenes/train/train.scn"
const TRIS_PER_CARRIAGE := 32274
## The bench seating, split out of the shell so a carriage can be dressed as
## something other than a seating saloon.
const TRIS_IN_SEATING := 2966
## Both end-wall door leaves, glass included, split out so they can swing.
const TRIS_IN_DOORS := 108
## Everything 3D now lives under the SubViewport, so the world renders at its own
## resolution while the HUD stays sharp.
const WORLD := "Screen/Frame/World"
const EXPECTED_CHILDREN := ["Consist", "Player", "WorldEnvironment", "Sun", "Backdrop", "Lighting"]


func test_the_generated_scene_still_has_its_script() -> void:
	var root: Node = auto_free(load(SCENE).instantiate())
	assert_object(root.get_script()).override_failure_message(
		"train.scn has no script, run --import before build_train_scene.gd; could make a cmake?"
		+ "the builder loads train.gd by path and saves anyway if it fails to parse."
	).is_not_null()


func test_the_generated_scene_keeps_every_node_the_code_reaches_for() -> void:
	var root: Node = auto_free(load(SCENE).instantiate())
	for name: String in EXPECTED_CHILDREN:
		assert_object(root.get_node_or_null("%s/%s" % [WORLD, name])).override_failure_message(
			"train.scn is missing %s, which Train reaches for by path" % name
		).is_not_null()
	## Might need a better way to handle this.
	assert_object(root.get_node_or_null(WORLD + "/Backdrop/Terrain")).is_not_null()
	assert_object(root.get_node_or_null(WORLD + "/Backdrop/Forest")).is_not_null()
	assert_object(root.get_node_or_null(WORLD + "/Player/Camera3D")).is_not_null()


## Picking follows the camera, and the camera is inside the SubViewport now. If
## this is ever false the WIN and LOSE plates stop responding to clicks and taps,
## which no other test would catch.
func test_the_world_viewport_owns_picking() -> void:
	var root: Node = auto_free(load(SCENE).instantiate())
	var world := root.get_node_or_null(WORLD) as SubViewport
	assert_object(world).override_failure_message(
		"train.scn has no SubViewport at %s" % WORLD).is_not_null()
	assert_bool(world.physics_object_picking).override_failure_message(
		"the world SubViewport does not pick, so the level plates are dead"
	).is_true()
	assert_object(root.get_node_or_null(WORLD + "/Player/Camera3D") as Camera3D).is_not_null()


## The player is a body with a capsule, even though nothing draws it. If the
## shape goes missing the capsule is silently a point, and no other test notices.
func test_the_player_is_a_capsule_body() -> void:
	var root: Node = auto_free(load(SCENE).instantiate())
	var player := root.get_node_or_null(WORLD + "/Player") as CharacterBody3D
	assert_object(player).override_failure_message(
		"train.scn has no CharacterBody3D at %s/Player" % WORLD).is_not_null()
	var body := player.get_node_or_null("Body") as CollisionShape3D
	assert_object(body).is_not_null()
	assert_object(body.shape as CapsuleShape3D).override_failure_message(
		"the player's collision shape is not a capsule").is_not_null()


## stretch forwards input inward and rescales it; without it the plates would be
## picked at the wrong coordinates.
func test_the_frame_stretches_into_the_world() -> void:
	var root: Node = auto_free(load(SCENE).instantiate())
	var frame := root.get_node_or_null("Screen/Frame") as SubViewportContainer
	assert_object(frame).is_not_null()
	assert_bool(frame.stretch).is_true()
	assert_int(frame.stretch_shrink).is_greater_equal(1)


func test_the_carriage_is_packed_once_not_twice() -> void:
	var root: Node = auto_free(load(SCENE).instantiate())
	var carriage_scene: PackedScene = root.get_node(WORLD + "/Consist").carriage_scene
	assert_object(carriage_scene).override_failure_message(
		"Consist.carriage_scene is unset, so the train would spawn nothing, important for the start of the story."
	).is_not_null()
	var carriage: Node = auto_free(carriage_scene.instantiate())
	assert_int(_triangles(carriage)).override_failure_message(
		"the bare shell should be %d triangles, double that means the builder packed "
		% (TRIS_PER_CARRIAGE - TRIS_IN_SEATING - TRIS_IN_DOORS)
		+ "the glTF instance's children as well as the instance."
	).is_equal(TRIS_PER_CARRIAGE - TRIS_IN_SEATING - TRIS_IN_DOORS)

	var seating_scene: PackedScene = root.get_node(WORLD + "/Consist").seating_scene
	assert_object(seating_scene).override_failure_message(
		"Consist.seating_scene is unset, so every carriage would be a bare box."
	).is_not_null()
	var seating: Node = auto_free(seating_scene.instantiate())
	var doors_scene: PackedScene = root.get_node(WORLD + "/Consist").doors_scene
	assert_object(doors_scene).override_failure_message(
		"Consist.doors_scene is unset, so every doorway would be an open hole."
	).is_not_null()
	var doors: Node = auto_free(doors_scene.instantiate())
	assert_int(_triangles(carriage) + _triangles(seating) + _triangles(doors)) \
		.override_failure_message(
			"the shell, the seating and the doors no longer add up to the carriage "
			+ "they were split from, so the split dropped or duplicated geometry."
		).is_equal(TRIS_PER_CARRIAGE)


func _triangles(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D and node.mesh != null:
		var mesh: Mesh = node.mesh
		for surface in range(mesh.get_surface_count()):
			total += mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size() / 3
	for child: Node in node.get_children():
		total += _triangles(child)
	return total


func test_the_consist_is_as_long_as_the_content_says() -> void:
	var root: Node = auto_free(load(SCENE).instantiate())
	assert_int(root.get_node(WORLD + "/Consist").carriage_count).override_failure_message(
		"the scene spawns a different number of carriages than shared/data/locations "
		+ "authors a carriage index for, so a room would have no carriage or the "
		+ "reverse. Rebuild with build_train_scene.gd."
	).is_equal(GameContent.carriage_locations().size())


## Two rooms carry no bench seating, and both are deliberate. The guard's van is
## described in shared/data/locations as crates and a cold stove and shipped full
## of benches anyway, because the seating was part of the carriage mesh and there
## was no way to leave it out. The dining car is bare because the stock seating is
## back to back, which seats every second diner facing away from the table it is
## meant to be laid on; it gets tables and chairs as props instead.
##
## Anything else turning up bare is a room that has quietly lost its furniture.
func test_only_the_rooms_that_ask_to_be_bare_are_bare() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist: Node = runner.scene().get_node(WORLD + "/Consist")
	var aboard: Array = GameContent.carriage_locations()
	var expected: Array[int] = []
	for room: StringName in [&"guard_van", &"dining"]:
		var at: int = aboard.find(room)
		assert_int(at).override_failure_message(
			"no %s in shared/data/locations" % room).is_greater_equal(0)
		expected.append(at)
	expected.sort()

	var bare: Array[int] = []
	for i in range(consist.carriage_count):
		var carriage := consist.get_node("Carriage_%02d" % i)
		if carriage.get_node_or_null("Seating") == null:
			bare.append(i)
	assert_array(bare).override_failure_message(
		"expected %s to be the bare rooms, found %s" % [expected, bare]
	).is_equal(expected)
