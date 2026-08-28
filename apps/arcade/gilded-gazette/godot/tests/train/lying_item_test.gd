# GdUnitTestSuite
extends GdUnitTestSuite

## A thing lying in a room is placed by Consist, and what is worth asserting is what
## a player would notice: that it is in the room it is supposed to be in, at a spot
## inside that carriage, resting on its surface rather than sunk into it or hovering
## over it, and lit like the things beside it rather than like something dropped in
## from another scene.
##
## Where it was put comes from the consist rather than from the content, because most
## of what is lying about is not authored into a room at all: the weapon is drawn per
## run and left where the night says. Asking the consist is the one question that
## answers for the authored and the drawn alike.

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


## The weapon the night drew is in the room the night drew, and it is the thing the
## player can walk up to. Everything else they have to go on is somebody's word.
func test_the_drawn_weapon_is_lying_in_the_drawn_room() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var built := _lying(_consist(runner))
	assert_int(built.size()).override_failure_message(
		"nothing is lying anywhere in the train, so this suite is asserting on air"
	).is_greater(0)

	var night: TheNight = Session.night
	assert_object(night).is_not_null()
	var here := built.filter(func(l: Dictionary) -> bool:
		return StringName(l["instance"].name) == night.weapon_id)
	assert_int(here.size()).override_failure_message(
		"the night was done with %s and it is lying nowhere in the train" % night.weapon_id
	).is_equal(1)

	var room: StringName = GameContent.carriage_locations()[int(here[0]["carriage"])]
	assert_str(String(room)).override_failure_message(
		"%s was left in %s, and the night says %s" % [night.weapon_id, room, night.scene]
	).is_equal(String(night.scene))


## And nothing is left over from the evening before. The night is redrawn on restart,
## so a weapon that stayed put would be the one object in the carriage still describing
## a run nobody is playing.
func test_a_restart_does_not_leave_the_last_weapon_behind() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	assert_int(_lying(consist).size()).is_equal(1)

	Session.begin()
	runner.scene()._begin()
	await runner.simulate_frames(2)

	var built := _lying(consist)
	assert_int(built.size()).override_failure_message(
		"after a restart there are %d weapons lying about, so the last run's is still there"
		% built.size()
	).is_equal(1)
	assert_str(built[0]["instance"].name).is_equal(String(Session.night.weapon_id))


## The same expansion guarantee the furnishings carry. Placement is carriage-local,
## so inserting a room anywhere in the consist moves every world position in the
## train and moves nothing that was authored against its own carriage.
func test_an_item_lies_at_its_own_offset_from_its_own_carriage() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	for lying: Dictionary in _lying(consist):
		var instance: MeshInstance3D = lying["instance"]
		var carriage: Node3D = consist.get_node("Carriage_%02d" % lying["carriage"])
		var placement: Dictionary = consist.placement_of(StringName(instance.name))
		var local: Vector3 = instance.global_position - carriage.global_position
		assert_float(local.x).override_failure_message(
			"%s is %.3f along its carriage, placed at %.3f"
			% [instance.name, local.x, placement["along"]]
		).is_equal_approx(float(placement["along"]), 0.001)
		assert_float(local.z).override_failure_message(
			"%s is %.3f across its carriage, placed at %.3f"
			% [instance.name, local.z, placement["across"]]
		).is_equal_approx(float(placement["across"]), 0.001)


## tools/import-item-model.py puts every model's origin on the ground under it, the
## same convention the prop library follows. That is what lets a placement's `above`
## mean the height of the surface the thing rests on and nothing else, so an item
## authored at above 0 sits on the deck rather than half through it.
func test_an_item_rests_on_the_surface_it_was_placed_on() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	for lying: Dictionary in _lying(consist):
		var instance: MeshInstance3D = lying["instance"]
		var above := float(consist.placement_of(StringName(instance.name)).get("above", 0.0))
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
		var reach := _reach(instance)
		assert_float(absf(instance.position.x) + reach.x).override_failure_message(
			"%s reaches past the end wall at %.3fm" % [instance.name, Consist.END_WALL_X]
		).is_less(Consist.END_WALL_X)
		assert_float(absf(instance.position.z) + reach.y).override_failure_message(
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


## An item ships as its own model, and how it is drawn depends on what the model
## brought. A scanned one carries a texture and is drawn by the prop shader, and
## painting it with the shared prop atlas would give a dagger the crate's woodgrain --
## the failure the per-mesh lookup exists to avoid. A modelled one carries no texture
## at all, only flat colours, and is drawn by an unshaded material holding its own
## colour times the same lamp tint. What both have to be is lit: an override on every
## surface, so nothing in the room is drawn as though the lamps were not there.
func test_an_item_is_drawn_with_its_own_colours() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var lying := _lying(_consist(runner))
	assert_int(lying.size()).is_greater(0)

	for entry: Dictionary in lying:
		var instance: MeshInstance3D = entry["instance"]
		for surface in range(instance.mesh.get_surface_count()):
			var worn := instance.get_surface_override_material(surface)
			assert_object(worn).override_failure_message(
				"%s surface %d is drawn with no override, so it is not lit by the "
				% [instance.name, surface] + "carriage lamps"
			).is_not_null()
			var own := instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if own != null and own.albedo_texture != null:
				assert_object((worn as ShaderMaterial).get_shader_parameter("tex_albedo")) \
					.override_failure_message(
						"%s is drawn with a texture that is not the one its model brought"
						% instance.name
					).is_same(own.albedo_texture)
			else:
				assert_object(worn as StandardMaterial3D).override_failure_message(
					"%s surface %d has no texture, so it wants a flat material rather "
					% [instance.name, surface] + "than the prop shader with nothing to sample"
				).is_not_null()


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
		var above := float(consist.placement_of(StringName(instance.name)).get("above", 0.0))
		for prop: Node in room.get_children():
			if not prop is MeshInstance3D:
				continue
			# The one prop it is allowed to be inside the footprint of is the one it is
			# standing on. A blade put down on a table is over the table by design, and
			# the height it was given is the height of that table's top.
			if above > 0.0 and is_equal_approx(above, _top_of(prop as MeshInstance3D)):
				continue
			var apart := Vector2(instance.position.x - prop.position.x,
				instance.position.z - prop.position.z).length()
			var clearance := _widest(instance) + _widest(prop)
			assert_float(apart).override_failure_message(
				"%s lies %.2fm from the %s beside it and the two of them reach %.2fm, "
				% [instance.name, apart, prop.name, clearance] + "so it is drawn through it"
			).is_greater_equal(clearance)


## How far a mesh gets from its own origin across the floor, in the direction it is
## actually turned.
##
## Turned rather than assumed. Taking the larger of the two axes and using it for both
## is safe for a crate and wrong for a sword: a yard of blade laid down the train is a
## hand's width across it, and calling it a yard in both directions puts it through a
## wall it is nowhere near. The corners are moved by the instance's own rotation, which
## costs four multiplications and describes the shape exactly.
func _reach(instance: MeshInstance3D) -> Vector2:
	var box: AABB = instance.get_aabb()
	var turn := instance.rotation.y
	var out := Vector2.ZERO
	for x in [box.position.x, box.position.x + box.size.x]:
		for z in [box.position.z, box.position.z + box.size.z]:
			var at := Vector2(x, z).rotated(turn)
			out.x = maxf(out.x, absf(at.x))
			out.y = maxf(out.y, absf(at.y))
	return out


## How high the top of a prop stands above the deck.
func _top_of(prop: MeshInstance3D) -> float:
	var box: AABB = prop.get_aabb()
	return box.position.y + box.size.y


## Every weapon, in every room, rather than the one arrangement this run happened to
## draw. The night picks a weapon and a room independently, so a rule that holds for a
## dagger in the guard's van says nothing about a sword in the dining car -- and it was
## exactly that pair which broke the fit rule into existence.
##
## What is asserted is what the single-run tests assert, because these are the same
## guarantees: inside the carriage it was left in, and not standing through anything
## except whatever it was put down on.
func test_no_weapon_in_any_room_is_left_inside_the_furniture() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	var rooms := GameContent.carriage_locations()

	for weapon: StringName in TheNight.weapons():
		var model := str(GameContent.by_id("items", String(weapon)).get("model", ""))
		for index in range(rooms.size()):
			consist.leave_the_weapon(rooms[index], model, weapon)
			await runner.simulate_frames(1)
			var carriage: Node3D = consist.get_node("Carriage_%02d" % index)
			var instance: MeshInstance3D = carriage.get_node("Items").get_node(String(weapon))
			var placement: Dictionary = consist.placement_of(weapon)
			var above := float(placement.get("above", 0.0))
			var reach := _reach(instance)
			var widest := _widest(instance)

			assert_float(absf(instance.position.z) + reach.y).override_failure_message(
				"%s left in %s reaches past the side wall at %.3fm"
				% [weapon, rooms[index], Consist.INTERIOR_HALF_Z]
			).is_less(Consist.INTERIOR_HALF_Z)
			assert_float(absf(instance.position.x) + reach.x).override_failure_message(
				"%s left in %s reaches past the end wall at %.3fm"
				% [weapon, rooms[index], Consist.END_WALL_X]
			).is_less(Consist.END_WALL_X)

			var furniture := carriage.get_node_or_null("Furnishings")
			if furniture == null:
				continue
			for prop: Node in furniture.get_children():
				if not prop is MeshInstance3D:
					continue
				if above > 0.0 and is_equal_approx(above, _top_of(prop as MeshInstance3D)):
					continue
				var apart := Vector2(instance.position.x - prop.position.x,
					instance.position.z - prop.position.z).length()
				assert_float(apart).override_failure_message(
					"%s left in %s lies %.2fm from a %s and the two reach %.2fm"
					% [weapon, rooms[index], apart, prop.name,
						widest + _widest(prop as MeshInstance3D)]
				).is_greater_equal(widest + _widest(prop as MeshInstance3D))


## The reach of a mesh as one number, for comparing two of them as circles about their
## own origins. Circles because both are turned about their own up axis and the compare
## is a distance rather than an overlap.
func _widest(instance: MeshInstance3D) -> float:
	var reach := _reach(instance)
	return maxf(reach.x, reach.y)
