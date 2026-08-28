# GdUnitTestSuite
extends GdUnitTestSuite

## An item lying in a room is authored in shared/data/items and placed by Consist,
## and what is worth asserting about it is what a player would notice: that it is
## in the carriage the mdx put it in, at the spot in that carriage the mdx gave it,
## on the floor rather than sunk into it or hovering over it, and lit like the
## things beside it rather than like something dropped in from another scene.

const SCENE := "res://scenes/train/train.scn"
const WORLD := "Screen/Frame/World"


func _consist(runner: GdUnitSceneRunner) -> Node:
	return runner.scene().get_node(WORLD + "/Consist")


## Everything the consist actually laid out, as {instance, carriage}.
func _lying(consist: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(consist.carriage_count):
		var carriage: Node3D = consist.get_node("Carriage_%02d" % i)
		var room := carriage.get_node_or_null("Items")
		if room == null:
			continue
		for item: Node in room.get_children():
			if item is MeshInstance3D:
				out.append({"instance": item, "carriage": i})
	return out


func test_every_item_with_a_model_is_lying_in_its_own_room() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var built := _lying(_consist(runner))
	assert_int(built.size()).override_failure_message(
		"nothing is lying anywhere in the train, so this suite is asserting on air"
	).is_greater(0)

	var rooms := GameContent.carriage_locations()
	for i in range(rooms.size()):
		var authored: Array = GameContent.items_in(i)
		var here := built.filter(func(l: Dictionary) -> bool: return l["carriage"] == i)
		assert_int(here.size()).override_failure_message(
			"%s has %d items authored with a model but %d lying in it, so a model "
			% [rooms[i], authored.size(), here.size()]
			+ "named in the mdx found no glb under assets/items"
		).is_equal(authored.size())
		for at in range(authored.size()):
			assert_str(here[at]["instance"].name).is_equal(String(authored[at]["id"]))


## The same expansion guarantee the furnishings carry. Placement is carriage-local,
## so inserting a room anywhere in the consist moves every world position in the
## train and moves nothing that was authored against its own carriage.
func test_an_item_lies_at_its_authored_offset_from_its_own_carriage() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	for lying: Dictionary in _lying(consist):
		var instance: MeshInstance3D = lying["instance"]
		var carriage: Node3D = consist.get_node("Carriage_%02d" % lying["carriage"])
		var placement: Dictionary = GameContent.by_id("items", instance.name)["found"]
		var local: Vector3 = instance.global_position - carriage.global_position
		assert_float(local.x).override_failure_message(
			"%s is %.3f along its carriage, authored %.3f"
			% [instance.name, local.x, placement["along"]]
		).is_equal_approx(float(placement["along"]), 0.001)
		assert_float(local.z).override_failure_message(
			"%s is %.3f across its carriage, authored %.3f"
			% [instance.name, local.z, placement["across"]]
		).is_equal_approx(float(placement["across"]), 0.001)


## tools/import-item-model.py puts every model's origin on the ground under it, the
## same convention the prop library follows. That is what lets a placement's `above`
## mean the height of the surface the thing rests on and nothing else, so an item
## authored at above 0 sits on the deck rather than half through it.
func test_an_item_rests_on_the_surface_it_was_placed_on() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	for lying: Dictionary in _lying(_consist(runner)):
		var instance: MeshInstance3D = lying["instance"]
		var above := float(GameContent.by_id("items", instance.name)["found"].get("above", 0.0))
		var underside: float = instance.position.y + instance.get_aabb().position.y
		assert_float(underside).override_failure_message(
			"%s rests %.3fm off its surface, so its model's origin is not on the "
			% [instance.name, underside - (Consist.FLOOR_Y + above)]
			+ "ground under it"
		).is_equal_approx(Consist.FLOOR_Y + above, 0.005)


func test_every_item_lies_inside_its_carriage() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	for lying: Dictionary in _lying(_consist(runner)):
		var instance: MeshInstance3D = lying["instance"]
		var box: AABB = instance.get_aabb()
		var reach := maxf(absf(box.position.x), absf(box.position.x + box.size.x))
		reach = maxf(reach, maxf(absf(box.position.z), absf(box.position.z + box.size.z)))
		assert_float(absf(instance.position.x) + reach).override_failure_message(
			"%s reaches past the end wall at %.3fm" % [instance.name, Consist.END_WALL_X]
		).is_less(Consist.END_WALL_X)
		assert_float(absf(instance.position.z) + reach).override_failure_message(
			"%s reaches past the side wall at %.3fm" % [instance.name, Consist.INTERIOR_HALF_Z]
		).is_less(Consist.INTERIOR_HALF_Z)


## Deliberate, and worth pinning: a prop gets a box body because walking through a
## crate is wrong, and an item does not because a shin-high body on the floor of a
## corridor is something to trip over on the way past. What there is to do with an
## item is look at it.
func test_an_item_is_not_something_to_walk_into() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	for lying: Dictionary in _lying(_consist(runner)):
		var instance: MeshInstance3D = lying["instance"]
		for child: Node in instance.get_children():
			assert_bool(child is CollisionObject3D).override_failure_message(
				"%s carries a %s, so the floor of that room has something to trip "
				% [instance.name, child.get_class()] + "over standing on it"
			).is_false()


## An item ships as its own model with its own image, and the prop shader takes one
## albedo. Painting it with the shared prop atlas would draw a dagger wearing the
## crate's woodgrain, which is the failure the per-mesh lookup exists to avoid.
func test_an_item_is_drawn_with_its_own_texture() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	var lying := _lying(consist)
	assert_int(lying.size()).is_greater(0)

	for entry: Dictionary in lying:
		var instance: MeshInstance3D = entry["instance"]
		var material := instance.get_surface_override_material(0) as ShaderMaterial
		assert_object(material).override_failure_message(
			"%s is drawn with no override, so it is not lit by the carriage lamps"
			% instance.name
		).is_not_null()
		var worn: Texture2D = material.get_shader_parameter("tex_albedo")
		var own := instance.mesh.surface_get_material(0) as BaseMaterial3D
		assert_object(worn).override_failure_message(
			"%s is drawn with a texture that is not the one its model brought"
			% instance.name
		).is_same(own.albedo_texture)


## An item has no collision, so nothing at runtime stops one being authored inside a
## crate -- it simply draws through it, which reads as a broken model rather than as a
## misplaced one. Compared as circles about each origin rather than as boxes, because
## both are turned about their own up axis and a turned box is the one shape an AABB
## cannot describe. Conservative, so it can complain about a near miss; a near miss
## between a dagger and a crate is worth moving anyway.
func test_an_item_does_not_lie_inside_the_furniture() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	for lying: Dictionary in _lying(consist):
		var instance: MeshInstance3D = lying["instance"]
		var carriage: Node3D = consist.get_node("Carriage_%02d" % lying["carriage"])
		var room := carriage.get_node_or_null("Furnishings")
		if room == null:
			continue
		for prop: Node in room.get_children():
			if not prop is MeshInstance3D:
				continue
			var apart := Vector2(instance.position.x - prop.position.x,
				instance.position.z - prop.position.z).length()
			var clearance := _reach(instance) + _reach(prop)
			assert_float(apart).override_failure_message(
				"%s lies %.2fm from the %s beside it and the two of them reach %.2fm, "
				% [instance.name, apart, prop.name, clearance] + "so it is drawn through it"
			).is_greater_equal(clearance)


## How far a mesh gets from its own origin across the floor, whichever way it is turned.
func _reach(instance: MeshInstance3D) -> float:
	var box: AABB = instance.get_aabb()
	var far := maxf(absf(box.position.x), absf(box.position.x + box.size.x))
	return maxf(far, maxf(absf(box.position.z), absf(box.position.z + box.size.z)))
