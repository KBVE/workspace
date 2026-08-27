# GdUnitTestSuite
extends GdUnitTestSuite

## Placement is authored in shared/data/locations and resolved by Consist, so what
## is worth asserting is not that a crate exists but that it lands somewhere a
## player can live with: inside the carriage, out of the door's swing, clear of the
## aisle, and at the same place in its own carriage no matter how long the train is.

const SCENE := "res://scenes/train/train.scn"
const WORLD := "Screen/Frame/World"

## What a prop has to leave around a hinge on top of the leaf's own width, so a
## door that swings all the way open does not end up resting against a crate.
const SWING_CLEARANCE_METRES := 0.15

## What a person needs to get past something. The player capsule is 0.38 in radius,
## so this is that doubled with enough left over that squeezing through does not
## mean scraping both walls.
const PASSAGE_METRES := 0.85


func _consist(runner: GdUnitSceneRunner) -> Node:
	return runner.scene().get_node(WORLD + "/Consist")


## Every prop the consist actually built, as {instance, carriage}.
func _standing(consist: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(consist.carriage_count):
		var carriage: Node3D = consist.get_node("Carriage_%02d" % i)
		var room := carriage.get_node_or_null("Furnishings")
		if room == null:
			continue
		for prop: Node in room.get_children():
			if prop is MeshInstance3D:
				out.append({"instance": prop, "carriage": i})
	return out


func test_the_guard_van_stands_everything_authored_for_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	var guard_van := GameContent.carriage_locations().find(&"guard_van")
	var authored: Array = GameContent.furnishings_at(guard_van)
	assert_int(authored.size()).override_failure_message(
		"nothing is authored in the guard's van, so this suite is asserting on air"
	).is_greater(0)

	var built := _standing(consist).filter(
		func(p: Dictionary) -> bool: return p["carriage"] == guard_van)
	assert_int(built.size()).override_failure_message(
		"the guard's van has %d furnishings authored but %d standing, so a prop "
		% [authored.size(), built.size()] + "name in the mdx found no mesh in the library"
	).is_equal(authored.size())


## The point of one atlas and one library scene. Three crates that each brought
## their own mesh would be three uploads of the same geometry.
func test_props_of_a_kind_share_one_mesh() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var by_name: Dictionary = {}
	for prop: Dictionary in _standing(_consist(runner)):
		var instance: MeshInstance3D = prop["instance"]
		if by_name.has(instance.name):
			assert_object(instance.mesh).override_failure_message(
				"two %s do not share a mesh, so the library is being copied per prop"
				% instance.name
			).is_same(by_name[instance.name])
		by_name[instance.name] = instance.mesh
	assert_int(by_name.size()).is_greater(0)


## The expansion guarantee, stated as the invariant that delivers it: a prop sits
## at its authored offset from its own carriage's centre, and nothing about that
## reading involves where the carriage happens to be. Add a room anywhere in the
## consist and every world position in the train moves; these do not drift.
func test_a_prop_stands_at_its_authored_offset_from_its_own_carriage() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	for i in range(consist.carriage_count):
		var carriage: Node3D = consist.get_node("Carriage_%02d" % i)
		var room := carriage.get_node_or_null("Furnishings")
		if room == null:
			continue
		var authored: Array = GameContent.furnishings_at(i)
		for at in range(authored.size()):
			var placement: Dictionary = authored[at]
			var local: Vector3 = room.get_child(at).global_position - carriage.global_position
			assert_float(local.x).override_failure_message(
				"%s in carriage %d is %.3f along, authored %.3f"
				% [placement["prop"], i, local.x, placement["along"]]
			).is_equal_approx(float(placement["along"]), 0.001)
			assert_float(local.z).override_failure_message(
				"%s in carriage %d is %.3f across, authored %.3f"
				% [placement["prop"], i, local.z, placement["across"]]
			).is_equal_approx(float(placement["across"]), 0.001)


## prop_anchors is what anything outside the consist reads, so it has to agree with
## what was actually built rather than being a second, parallel answer.
func test_prop_anchors_agree_with_what_is_standing() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	var anchors: Array[Dictionary] = consist.prop_anchors()
	var built := _standing(consist)
	assert_int(anchors.size()).override_failure_message(
		"prop_anchors reports %d props, %d are standing" % [anchors.size(), built.size()]
	).is_equal(built.size())
	for at in range(anchors.size()):
		var instance: MeshInstance3D = built[at]["instance"]
		assert_vector(anchors[at]["at"]).override_failure_message(
			"prop_anchors puts %s at %v, it is standing at %v"
			% [anchors[at]["prop"], anchors[at]["at"], instance.global_position]
		).is_equal_approx(instance.global_position, Vector3.ONE * 0.001)


func test_every_prop_stands_inside_its_carriage() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	for prop: Dictionary in _standing(_consist(runner)):
		var instance: MeshInstance3D = prop["instance"]
		var box: AABB = instance.get_aabb()
		var reach := maxf(absf(box.position.x), absf(box.position.x + box.size.x))
		reach = maxf(reach, maxf(absf(box.position.z), absf(box.position.z + box.size.z)))
		assert_float(absf(instance.position.x) + reach).override_failure_message(
			"%s reaches past the end wall at %.3fm, so it is inside the vestibule"
			% [instance.name, Consist.END_WALL_X]
		).is_less(Consist.END_WALL_X)
		assert_float(absf(instance.position.z) + reach).override_failure_message(
			"%s reaches past the side wall at %.3fm, so it is inside the panelling"
			% [instance.name, Consist.INTERIOR_HALF_Z]
		).is_less(Consist.INTERIOR_HALF_Z)


## A prop parked in front of a door is a door that opens into it and stops. Measured
## against the real leaves rather than a written-down keepout, so a reshaped door
## moves the rule with it.
func test_no_prop_stands_in_a_door_swing() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	var standing := _standing(consist)
	assert_int(standing.size()).is_greater(0)

	for leaf: Node3D in consist.door_leaves():
		var leaf_box: AABB = (leaf as VisualInstance3D).get_aabb()
		var sweep := maxf(absf(leaf_box.position.z), absf(leaf_box.position.z + leaf_box.size.z))
		var hinge := leaf.global_position
		for prop: Dictionary in standing:
			var instance: MeshInstance3D = prop["instance"]
			var box: AABB = instance.get_aabb()
			var reach := maxf(absf(box.position.x), absf(box.position.x + box.size.x))
			reach = maxf(reach, maxf(absf(box.position.z), absf(box.position.z + box.size.z)))
			var flat := Vector2(instance.global_position.x - hinge.x,
				instance.global_position.z - hinge.z).length()
			if flat > sweep + reach + SWING_CLEARANCE_METRES:
				continue
			assert_bool(true).override_failure_message(
				"%s stands %.2fm from a hinge that sweeps %.2fm, so the door opens "
				% [instance.name, flat, sweep] + "into it and stops there"
			).is_false()


## Every carriage has to stay walkable end to end, whatever is standing in it.
##
## Not a rule about the aisle, because a carriage without benches has no aisle --
## the guard's van and the dining car both have the whole floor to play with, and
## the dining car uses it. The rule that holds for all of them is that somewhere
## across the car there is still a lane a person fits down, at every point along
## it. A dining car with the tables against the windows passes. The same tables
## pushed to the centreline does not, and neither does a wall of crates.
func test_a_carriage_stays_walkable_end_to_end() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	for i in range(consist.carriage_count):
		var blocking := _footprints(consist, i)
		if blocking.is_empty():
			continue
		# the narrowest point in the whole carriage, asserted once. Sampling and
		# asserting as it goes reports the same pinch thirty times over, once per
		# step that happens to fall inside it
		var narrowest := INF
		var pinched_at := 0.0
		var at := -Consist.END_WALL_X
		while at <= Consist.END_WALL_X:
			var widest := _widest_lane(blocking, at)
			if widest < narrowest:
				narrowest = widest
				pinched_at = at
			at += 0.1
		assert_float(narrowest).override_failure_message(
			"carriage %d leaves %.2fm to get past at %.2fm along, and a player is "
			% [i, narrowest, pinched_at] + "%.2fm wide, so the train is walled in half"
			% PASSAGE_METRES
		).is_greater_equal(PASSAGE_METRES)


## What stands in the way in carriage [param index], as {from, to, near, far} in
## carriage-local metres: the run it covers along the train and the run it covers
## across it.
##
## Benches count as much as props do. They are why a dressed carriage has an aisle
## in the first place, and a prop that only just clears a table is no use if it is
## standing in a bench.
func _footprints(consist: Node, index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var carriage: Node3D = consist.get_node("Carriage_%02d" % index)
	var room := carriage.get_node_or_null("Furnishings")
	if room != null:
		for prop: Node in room.get_children():
			var instance := prop as MeshInstance3D
			if instance == null:
				continue
			var box: AABB = instance.get_aabb()
			var half_along := box.size.x * 0.5
			var half_across := box.size.z * 0.5
			var turn := absf(sin(instance.rotation.y))
			var lean := absf(cos(instance.rotation.y))
			var along := half_along * lean + half_across * turn
			var across := half_along * turn + half_across * lean
			out.append({
				"from": instance.position.x - along, "to": instance.position.x + along,
				"near": instance.position.z - across, "far": instance.position.z + across,
			})
	if not consist.undressed_carriages.has(index):
		for side: float in [1.0, -1.0]:
			out.append({
				"from": -Consist.END_WALL_X, "to": Consist.END_WALL_X,
				"near": minf(side * Consist.SEAT_EDGE_Z, side * Consist.INTERIOR_HALF_Z),
				"far": maxf(side * Consist.SEAT_EDGE_Z, side * Consist.INTERIOR_HALF_Z),
			})
	return out


## The widest run of clear floor across the car at [param at] metres along it.
func _widest_lane(blocking: Array[Dictionary], at: float) -> float:
	var edges: Array[Vector2] = []
	for shape: Dictionary in blocking:
		if at < shape["from"] or at > shape["to"]:
			continue
		edges.append(Vector2(shape["near"], shape["far"]))
	edges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var widest := 0.0
	var clear_from := -Consist.INTERIOR_HALF_Z
	for edge: Vector2 in edges:
		widest = maxf(widest, edge.x - clear_from)
		clear_from = maxf(clear_from, edge.y)
	return maxf(widest, Consist.INTERIOR_HALF_Z - clear_from)


func test_a_prop_is_solid() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	for prop: Dictionary in _standing(_consist(runner)):
		var instance: MeshInstance3D = prop["instance"]
		var body := instance.get_node_or_null("Collision")
		assert_object(body).override_failure_message(
			"%s carries no collision, so the player walks through it" % instance.name
		).is_not_null()
		var shape := body.get_child(0) as CollisionShape3D
		var size: Vector3 = (shape.shape as BoxShape3D).size
		assert_vector(size).override_failure_message(
			"%s has a collision box of %v against a mesh of %v"
			% [instance.name, size, instance.get_aabb().size]
		).is_equal_approx(instance.get_aabb().size, Vector3.ONE * 0.001)


## A plate on a table has to be on the table. The prop compiler puts every origin
## on the ground under its prop, so a furnishing with no `above` stands on the deck
## and one with an `above` stands that far over it -- which is what lets the dining
## car later carry food without a second placement system for things on surfaces.
func test_a_furnishing_stands_at_the_height_it_was_authored_at() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	for i in range(consist.carriage_count):
		var carriage: Node3D = consist.get_node("Carriage_%02d" % i)
		var room := carriage.get_node_or_null("Furnishings")
		if room == null:
			continue
		var authored: Array = GameContent.furnishings_at(i)
		for at in range(authored.size()):
			var lifted: float = float(authored[at].get("above", 0.0))
			var stood: float = room.get_child(at).position.y - Consist.FLOOR_Y
			assert_float(stood).override_failure_message(
				"%s in carriage %d stands %.3f over the deck, authored %.3f"
				% [authored[at]["prop"], i, stood, lifted]
			).is_equal_approx(lifted, 0.001)


## Undressing the dining car took its benches away, and two passengers are authored
## as living in it. A room with tables and no seats is a room they stand up in.
func test_the_dining_car_has_somewhere_to_sit() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	var dining := GameContent.carriage_locations().find(&"dining")
	assert_int(dining).is_greater_equal(0)

	var chairs: Array = GameContent.furnishings_at(dining).filter(
		func(f: Dictionary) -> bool: return bool(f.get("seats", false)))
	var seats: Array = consist.seat_anchors().filter(
		func(a: Dictionary) -> bool: return a["carriage"] == dining)
	assert_int(seats.size()).override_failure_message(
		"the dining car has %d chairs authored and %d seats to sit in, so somebody "
		% [chairs.size(), seats.size()] + "who lives there has nowhere to go"
	).is_equal(chairs.size())
	assert_int(seats.size()).is_greater(0)


## The quarter turn between a chair's mesh facing and its passenger's is the sort of
## thing that is off by a sign and still looks plausible until somebody sits down
## staring at a window. Asserted by walking a seated body forward and landing on the
## table it is laid at.
##
## Uses SLocomotion.forward_of rather than restating the maths, so the test cannot
## agree with itself while disagreeing with the game.
func test_a_diner_sits_looking_at_the_table() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var consist := _consist(runner)
	var dining := GameContent.carriage_locations().find(&"dining")
	var tables: Array = GameContent.furnishings_at(dining).filter(
		func(f: Dictionary) -> bool: return f["prop"] == "dining_table")
	assert_int(tables.size()).is_greater(0)

	for anchor: Dictionary in consist.seat_anchors():
		if anchor["carriage"] != dining:
			continue
		var seated := CLocomotion.new()
		seated.facing_radians = anchor["facing"]
		var knees: Vector3 = anchor["at"] + SLocomotion.forward_of(seated) * 0.66 \
			- consist.global_position - Vector3(consist._offset(dining), 0.0, 0.0)
		var laid: bool = tables.any(func(table: Dictionary) -> bool:
			return absf(knees.x - float(table["along"])) < 0.4 \
				and absf(knees.z - float(table["across"])) < 0.4)
		assert_bool(laid).override_failure_message(
			"a diner seated at %v looks at %.2f, %.2f, where no table is laid"
			% [anchor["at"], knees.x, knees.z]
		).is_true()

