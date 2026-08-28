extends Node3D
class_name Consist

## Consist : Node3D
## Cars share meshes, materials and textures, so length costs transforms and draw
## calls only. VRAM does not move with [member carriage_count].
## Looking down the aisle points the camera along the train, so every carriage
## ahead sits in the frustum and frustum culling saves nothing. Web has no
## occlusion culling either, so cull by carriage index, explicitly.
## Measured (tools/bench_consist.gd, native, 1080p, vsync off): 21 cars drawn
## 1.14ms, windowed 0.64ms, O(1) in length. Lights dominate: 0.85 -> 0.46ms by
## hiding lamps at equal geometry.

@export var carriage_scene: PackedScene
## The bench seating, added per carriage rather than modelled into the shell.
## tools/build_carriage_variants.sh splits the original into the two, so a car
## can be dressed as something other than a seating saloon.
@export var seating_scene: PackedScene
## Carriages that stay bare, by index. Everything else gets the seating back, so
## adding a room here is what changes, not the look of the rest of the train.
@export var undressed_carriages: Array[int] = []
## The two end-wall door leaves, hinged at their own origins. Split out of the shell
## so they can swing; every carriage gets them.
@export var doors_scene: PackedScene
## The prop library: one scene of loose meshes sharing one atlas material, built
## by the prop compiler. Nothing instances the scene itself; carriages take the
## meshes out of it and share them, so a hundred crates cost one mesh and one
## material bind between them.
@export var props_scene: PackedScene
@export var detail_normal: Texture2D
@export_range(1, 32) var carriage_count: int = 5
## Car centre spacing. Mesh bounds are 20.88m, so 21.0 butts the end platforms.
@export var pitch: float = 21.0
## Cars either side of the viewer that draw. Lamps use the tighter window.
@export_range(0, 8) var mesh_window: int = 2
@export_range(0, 8) var lamp_window: int = 1
@export var lamps_per_car: int = 6

## The walkable interior, as a box. The carriage mesh is 32k triangles and a
## trimesh of it would be that much physics geometry per car, for a corridor
## that is in the end a box. Z is inside the 1.69 shell, leaving the panelling
## thickness the player never reaches through.
## The deck, found by casting a ray down the aisle against a trimesh of the carriage.
## It is not the model's lowest vertex, which is a bogie a metre under the rails, and
## it is not the busiest run of vertices either: the car body has an underside at 0.04
## and an underframe between, and both look like floors to anything counting them.
##
## Collision and drawing were two numbers until the seating was split out of the shell.
## They are one now, so a ray cast at the floor hits the floor the player can see, and
## the capsule stands on the deck rather than a plane a metre and a quarter beneath it.
const FLOOR_Y := 1.2735
## Where the cushions are, found by dropping rays every 15cm down the length of a bench
## and reading the profile: floor at 0.00, cushions at 0.52, seat backs at 1.33.
##
## The seats are back to back in pairs. A back stands every 2.35m and carries a cushion
## on either side of it, so the anchors are not on the pitch -- they straddle it. Putting
## them on the round numbers puts every one of them either inside a seat back or in the
## gap between two pairs, which is the empty floor a passenger would be sitting on.
const CUSHION_ABOVE_FLOOR := 0.52
const SEAT_CENTRE_Z := 0.95

## Where the bench starts, measured across the car: the cushions run from here out to
## the wall. What the aisle has left over is what anybody can walk down.
const SEAT_EDGE_Z := 0.55

## Between the pitch and the pair: a back every 2.35m, a cushion 0.45 either side of it.
const SEAT_ROW_PITCH := 2.35
const SEAT_PAIR_REACH := 0.45
const SEAT_ROWS_EITHER_SIDE := 3

## The last back stands at 7.05 and has floor beyond it rather than a second cushion, so
## anchors past this are seats nobody built.
const SEAT_FURTHEST_X := 7.0

const INTERIOR_HALF_Z := 1.5

## The gas lamps: how many, where the first one hangs, how far apart, how high, and
## what colour they burn.
##
## tools/bake_carriage_light.py stands Blender lamps on these same numbers, so a lamp
## moved here is a lamp that has to be baked again. It is also what [method _lamplight]
## reads, which is how a prop ends up wearing the light of the wall behind it.
const LAMP_FIRST_X := -6.2
const LAMP_PITCH := 2.48
const LAMP_HEIGHT := 4.05
const LAMP_COLOUR := Color(1.0, 0.84, 0.6)
const LAMP_RANGE := 7.0
const LAMP_ENERGY := 4.0

## What [method _lamplight] multiplies its falloff by, and what it never falls below.
## Kept in step by eye with EXPOSURE and AMBIENT in tools/bake_carriage_light.py: the
## walls are lit by Cycles and the props by this, and the only thing that matters is
## that a crate does not look like it is standing in a different carriage.
const PROP_EXPOSURE := 2.6
const PROP_AMBIENT := Color(0.16, 0.14, 0.11)

## How far off the panelling a posted sheet sits. Enough that it does not fight the
## wall for the same pixels, little enough that it is stuck on rather than floating.
const NOTICE_WALL_GAP := 0.02

## The end wall and the hole in it. Without this a shut door is decoration: the
## player simply walks through the wall beside it, because the shell is a floor and
## two sides and has never had ends.
##
## Taken from the door leaf: the opening is exactly as wide and as tall as the thing
## that fills it, so a reshaped door does not leave a gap around its frame.
const END_WALL_X := 8.615
const END_WALL_THICKNESS := 0.1
const DOORWAY_HALF_Z := 0.52
const DOORWAY_HEIGHT := 2.44
const WALL_HEIGHT := 3.5
const SHELL_THICKNESS := 0.4

## Across the carriage, for a thing left on the floor of a room with nothing to put it
## on. Off the centreline, because the middle of the floor is the aisle and a weapon
## lying in the aisle is a weapon everybody steps over without seeing.
const FLOOR_RESTING_ACROSS := 0.95

## A quarter turn, which lays a model's long axis down the train rather than across it.
## The carriage is three metres wide and twenty long: everything loose aboard is left
## pointing the way the train goes, because there is no room to leave it any other way.
const LYING_ALONG_THE_TRAIN := PI * 0.5

var _carriages: Array[Node3D] = []
var _lampsets: Array[Node3D] = []
var _shared: Dictionary = {}
var _prop_meshes: Dictionary = {}
var _item_meshes: Dictionary = {}
var _placements: Dictionary = {}
var _left: Dictionary = {}

func _ready() -> void:
	if carriage_scene == null:
		push_error("Consist: carriage_scene not set")
		return
	for i in range(carriage_count):
		var carriage: Node3D = carriage_scene.instantiate()
		carriage.name = "Carriage_%02d" % i
		carriage.position = Vector3(_offset(i), 0.0, 0.0)
		_dress(carriage, i)
		_hang_doors(carriage)
		# after the seating goes in, so its surfaces take the same shared materials
		# as the shell instead of keeping the ones the glb shipped with
		_reskin(carriage)
		# and after the reskin, because props carry the atlas material the prop
		# compiler gave them and the carriage shader would paint over it
		_furnish(carriage, i)
		_scatter_items(carriage, i)
		_post_notices(carriage, i)
		var lamps := Node3D.new()
		lamps.name = "Lamps"
		for j in range(lamps_per_car):
			var lamp := OmniLight3D.new()
			lamp.position = _lamp_at(j)
			lamp.omni_range = LAMP_RANGE
			lamp.omni_attenuation = 1.4
			lamp.light_color = LAMP_COLOUR
			lamp.light_energy = LAMP_ENERGY
			lamps.add_child(lamp)
		carriage.add_child(lamps)
		_add_shell(carriage)
		add_child(carriage)
		_carriages.append(carriage)
		_lampsets.append(lamps)
	_add_end_caps()

## Puts the bench seating back into carriage [param index], unless it is meant to
## be a bare room. The seating is a child rather than part of the shell, so it is
## hidden and culled with the carriage and costs nothing when it is not there.
func _dress(carriage: Node3D, index: int) -> void:
	if seating_scene == null or undressed_carriages.has(index):
		return
	var seating := seating_scene.instantiate()
	seating.name = "Seating"
	carriage.add_child(seating)
	_add_seat_collision(seating)


## Collision for the benches, which the shell box cannot describe: it is a room, and a
## room with seats in it is not a box. Trimesh rather than a box per bench because the
## seating is its own mesh now and small enough to afford -- roughly two thousand
## triangles a car against the thirty-two thousand the whole shell would have cost,
## which is the reason the shell is still a box.
##
## What it buys is a floor a ray can find: the foot planting and anything that asks
## what is underfoot now get the seat top rather than the deck under it.
func _add_seat_collision(seating: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "SeatingCollision"
	for mesh: MeshInstance3D in _mesh_instances(seating):
		if mesh.mesh == null:
			continue
		var shape := CollisionShape3D.new()
		shape.shape = mesh.mesh.create_trimesh_shape()
		shape.transform = mesh.transform
		body.add_child(shape)
	if body.get_child_count() > 0:
		seating.add_child(body)
	else:
		body.free()


## Hangs both end doors. They keep the transform the glTF gave them, so each leaf
## already stands in its own doorway with its origin on the hinge; nothing here has
## to know where the ends of a carriage are.
func _hang_doors(carriage: Node3D) -> void:
	if doors_scene == null:
		return
	var doors := doors_scene.instantiate()
	doors.name = "Doors"
	carriage.add_child(doors)
	for leaf: Node in doors.get_children():
		if leaf is VisualInstance3D:
			_fit_box_collision(leaf)


## A box the shape of the mesh, parented to it. Being a child is the whole trick:
## the collider moves with whatever it is on, so a shut leaf blocks the doorway,
## an open one has taken its collision out of the way along with its geometry, and
## a prop turned by its authored facing is solid where it is drawn rather than
## where it was modelled.
##
## Measured off the mesh rather than written down, so a door or a prop reshaped in
## Blender does not need a number changed here to match.
func _fit_box_collision(visual: VisualInstance3D) -> void:
	var box := visual.get_aabb()
	var body := StaticBody3D.new()
	body.name = "Collision"
	_add_box(body, box.size, box.position + box.size * 0.5)
	visual.add_child(body)


## Every door leaf in the consist, in the order the carriages were built.
func door_leaves() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for carriage: Node3D in _carriages:
		var doors := carriage.get_node_or_null("Doors")
		if doors == null:
			continue
		for leaf: Node in doors.get_children():
			if leaf is Node3D:
				out.append(leaf)
	return out


## Stands the room's props on the floor of carriage [param index].
##
## Placement is authored in shared/data/locations as carriage-local metres, never
## world ones. Consist centres itself on its own origin, so inserting a carriage
## anywhere moves every world X in the train by half a pitch; a prop placed in
## world space would slide half a car the first time the consist changed length,
## and a prop placed locally does not notice. That is what makes the train
## expandable without every room being re-measured.
##
## Children of the carriage, like the seating and the lamps, so they cull and hide
## with it and cost nothing while the player is elsewhere.
func _furnish(carriage: Node3D, index: int) -> void:
	var placements: Array = GameContent.furnishings_at(index)
	if placements.is_empty():
		return
	var library := _prop_library()
	var room := Node3D.new()
	room.name = "Furnishings"
	carriage.add_child(room)
	for placement: Dictionary in placements:
		var prop := StringName(placement.get("prop", ""))
		var mesh: Mesh = library.get(prop)
		if mesh == null:
			push_error("Consist: props_scene has no mesh named %s" % prop)
			continue
		var instance := MeshInstance3D.new()
		instance.name = String(prop)
		instance.mesh = mesh
		instance.position = _furnishing_offset(placement)
		instance.rotation.y = float(placement.get("facing", 0.0))
		_light_the_prop(instance)
		room.add_child(instance)
		_fit_box_collision(instance)


## Lays out what was left lying in carriage [param index].
##
## An item is not a prop. A prop is furniture, drawn out of one atlased library because
## a train holds a hundred crates and one crate mesh; an item is one thing in one place
## and ships as its own model, so this loads by name the way [method _post_notices]
## loads a sheet by id. What they do share is the lighting: a dagger on the floor of the
## van is lit by the same lamps the crates beside it are, and looking lit differently is
## exactly how a thing reads as not belonging to the scene.
##
## No collision. These are small and on the floor, and a body around one is something to
## trip over on the way past -- the thing to do with an item is to look at it.
func _scatter_items(carriage: Node3D, index: int) -> void:
	var lying: Array = GameContent.items_in(index)
	if lying.is_empty():
		return
	var room := Node3D.new()
	room.name = "Items"
	carriage.add_child(room)
	for item: Dictionary in lying:
		_lay(room, StringName(item.get("id", "item")), String(item.get("model", "")),
			item.get("found", {}))


## Puts one thing on the floor of [param room], or on whatever [param placement] says
## it is standing on. Shared by the items the content authors and the weapon the night
## draws, so both are subject to the same guarantees about where they end up.
func _lay(room: Node3D, id: StringName, model: String, placement: Dictionary) -> void:
	var mesh := _item_mesh(model)
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = String(id)
	instance.mesh = mesh
	instance.position = _furnishing_offset(placement)
	instance.rotation.y = float(placement.get("facing", 0.0))
	_light_the_prop(instance)
	room.add_child(instance)
	_placements[id] = placement


## Leaves the weapon the night drew in the room the night drew it in.
##
## Called by [Train] on every begin rather than once as the consist is built. The night
## is drawn per run and redrawn on restart, and a weapon still lying where the last one
## left it would be the only object in the carriage describing the previous evening.
##
## Anything already left is taken away first, so restarting does not accumulate a pile
## of weapons in the rooms of nights nobody is playing any more.
func leave_the_weapon(room: StringName, model: String, id: StringName) -> void:
	take_the_weapon_away()
	if room.is_empty() or model.is_empty():
		return
	var index := GameContent.carriage_locations().find(room)
	if index < 0:
		push_error("Consist: the night left the weapon in %s, which is not a room in the consist" % room)
		return
	var mesh := _item_mesh(model)
	if mesh == null:
		return
	var items := _items_node(_carriages[index])
	_lay(items, id, model, _resting_spot(index, _longest(mesh)))
	_left = {"id": id, "carriage": index}


func take_the_weapon_away() -> void:
	if _left.is_empty():
		return
	var items: Node = _carriages[int(_left["carriage"])].get_node_or_null("Items")
	if items != null:
		var was: Node = items.get_node_or_null(String(_left["id"]))
		if was != null:
			items.remove_child(was)
			was.queue_free()
	_placements.erase(_left["id"])
	_left = {}


## Where a thing left in carriage [param index] ends up.
##
## On the first surface in the room it actually fits on, and on the floor otherwise. A
## blade on the floor of the dining car reads as dropped; the same blade on the table
## reads as put down, and put down is what happened -- somebody walked away from it.
##
## The fit is the whole of the rule, and it is not fussiness. A yard of sword on a
## dining table for two overhangs it at both ends, which puts the point through the
## chair beside it and the pommel through the carriage wall. Something that long was
## left on the floor, because there is nowhere else in a wagon-lit to put it.
##
## Which props are surfaces is stamped onto the placement by gen-content out of the
## library manifest, so a chair is never chosen -- it is somewhere to sit rather than
## somewhere to leave a weapon -- and a table remodelled taller moves what stands on it.
func _resting_spot(index: int, longest: float) -> Dictionary:
	for placement: Dictionary in GameContent.furnishings_at(index):
		if not placement.has("surfaceHeight"):
			continue
		var prop: Mesh = _prop_library().get(StringName(placement.get("prop", "")))
		if prop == null or _span(prop) < longest:
			continue
		return {
			"along": placement.get("along", 0.0),
			"across": placement.get("across", 0.0),
			"above": placement["surfaceHeight"],
			"facing": LYING_ALONG_THE_TRAIN,
		}
	return {
		"along": 0.0,
		"across": FLOOR_RESTING_ACROSS,
		"above": 0.0,
		"facing": LYING_ALONG_THE_TRAIN,
	}


## How much room a surface has to offer, which is its shorter side: a thing laid across
## the short side of a table overhangs it whichever way round the table is turned.
func _span(mesh: Mesh) -> float:
	var box: AABB = mesh.get_aabb()
	return minf(box.size.x, box.size.z)


## How much room a thing needs, which is its longer side. The pair matters -- comparing
## a sword's width against a table's width says a yard of steel fits on a table for two,
## and what that produces is a sword through the chair at one end and the wall at the
## other.
func _longest(mesh: Mesh) -> float:
	var box: AABB = mesh.get_aabb()
	return maxf(box.size.x, box.size.z)


## The node a carriage's loose things hang off, made on demand: a room with nothing
## authored in it still gets a weapon when the night leaves one there.
func _items_node(carriage: Node3D) -> Node3D:
	var items: Node3D = carriage.get_node_or_null("Items")
	if items == null:
		items = Node3D.new()
		items.name = "Items"
		carriage.add_child(items)
	return items


## Where each thing the consist laid out was put, by id. The authored ones come out of
## the content and the drawn one does not, so this is the one place that answers for
## both -- a test asking where something ended up asks here rather than assuming.
func placement_of(id: StringName) -> Dictionary:
	return _placements.get(id, {})


## The mesh inside res://assets/items/[param model].glb, loaded once.
##
## Cached across carriages for the same reason the prop library is: the same model in
## two rooms is two placements of one mesh, and loading the scene twice would be two
## copies of it resident for nothing.
func _item_mesh(model: String) -> Mesh:
	if model.is_empty():
		return null
	if _item_meshes.has(model):
		return _item_meshes[model]
	var path := "res://assets/items/%s.glb" % model
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("Consist: no item model at %s" % path)
		_item_meshes[model] = null
		return null
	var built := scene.instantiate()
	var found: Mesh = null
	for instance: MeshInstance3D in _mesh_instances(built):
		if instance.mesh != null:
			found = instance.mesh
			break
	built.free()
	if found == null:
		push_error("Consist: %s holds no mesh" % path)
	_item_meshes[model] = found
	return found


## Hangs the sheets posted in carriage [param index] on its wall.
##
## A quad rather than a prop: a notice is printed matter, and what a poster is in this
## world is an image at a size, which is exactly what a quad wearing a texture is. The
## width is authored and the height follows the image's own aspect, so a strip and a
## framed notice hang as themselves rather than both being squared off.
##
## Unshaded on purpose. The carriage lamps swing with the sway and a lit poster reads
## as a lamp rather than as paper; ink on paper under gaslight is closer to flat.
func _post_notices(carriage: Node3D, index: int) -> void:
	var posted: Array = GameContent.notices_in(index)
	if posted.is_empty():
		return
	var wall := Node3D.new()
	wall.name = "Notices"
	carriage.add_child(wall)
	for notice: Dictionary in posted:
		var texture: Texture2D = load("res://assets/notices/%s.png" % notice.get("id", ""))
		if texture == null:
			push_error("Consist: no sheet at res://assets/notices/%s.png" % notice.get("id", ""))
			continue
		var width := float(notice.get("width", 0.8))
		var quad := QuadMesh.new()
		quad.size = Vector2(width, width * texture.get_height() / texture.get_width())
		var paper := StandardMaterial3D.new()
		paper.albedo_texture = texture
		paper.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# the sheet is one-sided, and from the far wall you would be reading its back
		paper.cull_mode = BaseMaterial3D.CULL_BACK
		quad.material = paper
		var sheet := MeshInstance3D.new()
		sheet.name = String(notice.get("id", "notice"))
		sheet.mesh = quad
		sheet.position = _notice_offset(notice)
		# a quad faces +Z unturned, so the sheet on the far wall is turned about
		sheet.rotation.y = 0.0 if float(notice.get("side", 1)) < 0.0 else PI
		wall.add_child(sheet)


## Where a sheet hangs in its own carriage. [code]along[/code] runs down the train the
## way a furnishing's does; the wall it is stuck to is [code]side[/code] and not a free
## number, because a notice on the aisle centreline is a notice hanging in mid air.
func _notice_offset(notice: Dictionary) -> Vector3:
	return Vector3(float(notice.get("along", 0.0)),
		FLOOR_Y + float(notice.get("above", 1.95)),
		float(notice.get("side", 1)) * (INTERIOR_HALF_Z - NOTICE_WALL_GAP))


## Every posted sheet in the consist, in world space, with the node wearing it.
##
## The mirror of [method seat_anchors] and [method prop_anchors]: authored locally,
## resolved through the same [method _offset].
func notice_anchors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(carriage_count):
		var wall := _carriages[i].get_node_or_null("Notices")
		if wall == null:
			continue
		for notice: Dictionary in GameContent.notices_in(i):
			var sheet := wall.get_node_or_null(String(notice.get("id", "")))
			if sheet == null:
				continue
			out.append({
				"at": global_position + Vector3(_offset(i), 0.0, 0.0)
					+ _notice_offset(notice),
				"id": StringName(notice.get("id", "")),
				"sheet": sheet,
				"carriage": i,
			})
	return out


## Where lamp [param index] hangs in a carriage, in carriage-local metres.
func _lamp_at(index: int) -> Vector3:
	return Vector3(LAMP_FIRST_X + index * LAMP_PITCH, LAMP_HEIGHT, 0.0)


## What the lamps add up to at [param at], as the colour a prop standing there wears.
##
## Inverse square, the same falloff Blender baked the walls with, so a crate under a
## lamp and the panelling behind it agree about how lit that end of the car is. Not the
## same arithmetic -- Cycles bounced light off the roof and this does not -- which is
## what [constant PROP_AMBIENT] stands in for.
func _lamplight(at: Vector3) -> Color:
	var gathered := 0.0
	for j in range(lamps_per_car):
		var away: float = maxf(_lamp_at(j).distance_to(at), 0.35)
		gathered += LAMP_ENERGY / (away * away)
	var lit: float = minf(gathered * PROP_EXPOSURE / float(maxi(lamps_per_car, 1)), 1.0)
	return Color(
		minf(PROP_AMBIENT.r + LAMP_COLOUR.r * lit, 1.0),
		minf(PROP_AMBIENT.g + LAMP_COLOUR.g * lit, 1.0),
		minf(PROP_AMBIENT.b + LAMP_COLOUR.b * lit, 1.0))


## Where a placement stands in its own carriage. The prop compiler puts every
## prop's origin on the ground under it, so the deck is the default height and
## nothing needs a fudge factor per prop. Anything standing on a surface rather
## than on the floor -- a plate on a table, a book on a shelf -- carries the
## height of that surface as its own [code]above[/code].
func _furnishing_offset(placement: Dictionary) -> Vector3:
	return Vector3(float(placement.get("along", 0.0)),
		FLOOR_Y + float(placement.get("above", 0.0)),
		float(placement.get("across", 0.0)))


## Dresses one prop in the light of where it stands.
##
## An override per instance rather than a shared material, because the tint is the one
## thing about a prop that is not shared. The mesh and its texture still are, so this
## costs a material bind and not a copy of the crate.
func _light_the_prop(instance: MeshInstance3D) -> void:
	var tint := _lamplight(instance.position)
	var shared: ShaderMaterial = null
	for surface in range(instance.mesh.get_surface_count()):
		var texture := _albedo_of(instance.mesh, surface)
		if texture == null:
			instance.set_surface_override_material(surface,
				_flat_lit(instance.mesh, surface, tint))
			continue
		if shared == null:
			shared = ShaderMaterial.new()
			shared.shader = load("res://shaders/prop.gdshader")
			shared.set_shader_parameter("tex_albedo", texture)
			shared.set_shader_parameter("baked_tint", tint)
		instance.set_surface_override_material(surface, shared)


## An untextured surface, lit the way a textured one is.
##
## Low-poly packs carry no textures and no UV map at all: a weapon is five or six
## materials, each a flat colour. There is nothing to sample, so the multiply
## [code]prop.gdshader[/code] does between an albedo and the lamp tint is done here
## between a colour and the same tint, and the result is unshaded for the same reason
## the shader is -- the walls are baked and a prop that answered to the real lamps
## would be the one thing in the carriage lit twice.
##
## Per surface, because the colours are what tell the steel from the grip. Collapsing
## them into one would be collapsing the model.
func _flat_lit(mesh: Mesh, surface: int, tint: Color) -> StandardMaterial3D:
	var source := mesh.surface_get_material(surface) as BaseMaterial3D
	var colour := Color.WHITE if source == null else source.albedo_color
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.albedo_color = Color(colour.r * tint.r, colour.g * tint.g, colour.b * tint.b)
	return flat


## The texture a mesh is drawn with, taken off the material it arrived wearing.
##
## Every prop the compiler builds shares one atlas, which is the whole point of an
## atlas, so for the library this returns the same texture every time and the bind is
## shared. An item is its own model with its own image and answers with that instead,
## which is why this asks the mesh rather than caching one atlas for the whole train.
func _albedo_of(mesh: Mesh, surface: int = 0) -> Texture2D:
	if mesh == null or surface >= mesh.get_surface_count():
		return null
	var src := mesh.surface_get_material(surface) as BaseMaterial3D
	return null if src == null else src.albedo_texture


## Prop name to mesh, harvested once out of [member props_scene].
##
## The library scene is instanced and thrown away rather than kept: what is wanted
## out of it is the meshes, and holding the scene as well would keep a second copy
## of every one of them alive for nothing.
func _prop_library() -> Dictionary:
	if not _prop_meshes.is_empty() or props_scene == null:
		return _prop_meshes
	var library := props_scene.instantiate()
	for mesh: MeshInstance3D in _mesh_instances(library):
		if mesh.mesh != null:
			_prop_meshes[StringName(mesh.name)] = mesh.mesh
	library.free()
	return _prop_meshes


## Floor and side walls, so the player is inside something rather than beside it.
## Culling hides a carriage but leaves its bodies live, which is what stops the
## player walking out through a car they cannot currently see.
func _add_shell(carriage: Node3D) -> void:
	var shell := StaticBody3D.new()
	shell.name = "Shell"
	_add_box(shell, Vector3(pitch, SHELL_THICKNESS, INTERIOR_HALF_Z * 2.0),
		Vector3(0.0, FLOOR_Y - SHELL_THICKNESS * 0.5, 0.0))
	for side: float in [1.0, -1.0]:
		_add_box(shell, Vector3(pitch, WALL_HEIGHT, SHELL_THICKNESS),
			Vector3(0.0, WALL_HEIGHT * 0.5, side * (INTERIOR_HALF_Z + SHELL_THICKNESS * 0.5)))
	for end: float in [1.0, -1.0]:
		_add_end_wall(shell, end)
	carriage.add_child(shell)


## One end wall as three boxes around the doorway: a panel either side and a lintel
## over the top. Three boxes rather than a hole in one, because a BoxShape3D has no
## hole and a trimesh of the end wall would cost more than the whole shell does.
func _add_end_wall(shell: StaticBody3D, end: float) -> void:
	var x := end * END_WALL_X
	var panel_z := (INTERIOR_HALF_Z - DOORWAY_HALF_Z) * 0.5
	for side: float in [1.0, -1.0]:
		_add_box(shell,
			Vector3(END_WALL_THICKNESS, DOORWAY_HEIGHT, INTERIOR_HALF_Z - DOORWAY_HALF_Z),
			Vector3(x, FLOOR_Y + DOORWAY_HEIGHT * 0.5, side * (DOORWAY_HALF_Z + panel_z)))
	var lintel := WALL_HEIGHT - DOORWAY_HEIGHT
	_add_box(shell,
		Vector3(END_WALL_THICKNESS, lintel, INTERIOR_HALF_Z * 2.0),
		Vector3(x, FLOOR_Y + DOORWAY_HEIGHT + lintel * 0.5, 0.0))


func _add_box(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)


## Caps the open ends of the consist, so the corridor stops where the train does.
func _add_end_caps() -> void:
	var caps := StaticBody3D.new()
	caps.name = "EndCaps"
	var reach := carriage_count * pitch * 0.5
	for side: float in [1.0, -1.0]:
		_add_box(caps, Vector3(SHELL_THICKNESS, WALL_HEIGHT, INTERIOR_HALF_Z * 2.0),
			Vector3(side * (reach + SHELL_THICKNESS * 0.5), WALL_HEIGHT * 0.5, 0.0))
	add_child(caps)


## Centre of carriage [param i] in local X. Consist is centred on its own origin.
func _offset(i: int) -> float:
	return (i - (carriage_count - 1) / 2.0) * pitch

## Index of the carriage containing local X [param x], clamped to the consist.
func carriage_index_at(x: float) -> int:
	return clampi(int(round(x / pitch + (carriage_count - 1) / 2.0)), 0, carriage_count - 1)

## Show only the carriages near [param x]; hiding one hides its lamps with it.
func cull_around(x: float) -> void:
	for i in range(_carriages.size()):
		var d: float = absf(_carriages[i].position.x - x) / pitch
		_carriages[i].visible = d <= float(mesh_window)
		_lampsets[i].visible = d <= float(lamp_window)

## The lamp holder for carriage [param index]. Hidden while it is culled.
func lamps_for(index: int) -> Node3D:
	return _lampsets[index] if index >= 0 and index < _lampsets.size() else null

## The shared emissive material, or null. Drive its energy for the lamp glass.
func glow_material() -> StandardMaterial3D:
	return _shared.get("@glow")

func tune_detail(tiling: float, strength: float, albedo: float) -> void:
	for key: String in _shared:
		var sm := _shared[key] as ShaderMaterial
		if sm == null:
			continue
		sm.set_shader_parameter("detail_tiling", tiling)
		sm.set_shader_parameter("detail_strength", strength)
		sm.set_shader_parameter("detail_albedo", albedo)

func _reskin(carriage: Node3D) -> void:
	for mi: MeshInstance3D in _mesh_instances(carriage):
		var m: Mesh = mi.mesh
		for i in range(m.get_surface_count()):
			var src := m.surface_get_material(i) as StandardMaterial3D
			if src == null or src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue # window panes keep their own material
			mi.set_surface_override_material(i, _material_for(src))
	var em := carriage.get_node_or_null("emissive") as MeshInstance3D
	if em != null and em.mesh.surface_get_material(0) != null:
		if not _shared.has("@glow"):
			var g: StandardMaterial3D = em.mesh.surface_get_material(0).duplicate()
			g.emission_enabled = true
			g.emission = Color(1.0, 0.82, 0.55)
			_shared["@glow"] = g
		em.set_surface_override_material(0, _shared["@glow"])

func _material_for(src: StandardMaterial3D) -> ShaderMaterial:
	var key := src.resource_name
	if _shared.has(key):
		return _shared[key]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/carriage_2sided.gdshader") \
		if src.cull_mode == BaseMaterial3D.CULL_DISABLED \
		else load("res://shaders/carriage.gdshader")
	sm.set_shader_parameter("tex_albedo", src.albedo_texture)
	sm.set_shader_parameter("tex_detail", detail_normal)
	_shared[key] = sm
	return sm

func _mesh_instances(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c: Node in n.get_children():
		out.append_array(_mesh_instances(c))
	return out


## Every seat in the consist, in world space. Undressed carriages have no benches in
## them and so contribute none, which is what keeps a bare room bare.
func seat_anchors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(carriage_count):
		# before the bench guard below, not after it: a room with no benches is
		# exactly the room whose chairs are the only seats in it
		out.append_array(_prop_seats(i))
		if seating_scene == null or undressed_carriages.has(i):
			continue
		for row in range(-SEAT_ROWS_EITHER_SIDE, SEAT_ROWS_EITHER_SIDE + 1):
			for facing_pair: float in [-1.0, 1.0]:
				var bay := row * SEAT_ROW_PITCH + facing_pair * SEAT_PAIR_REACH
				if absf(bay) > SEAT_FURTHEST_X:
					continue
				for side: float in [1.0, -1.0]:
					out.append({
						"at": global_position + Vector3(_offset(i) + bay,
							FLOOR_Y + CUSHION_ABOVE_FLOOR, side * SEAT_CENTRE_Z),
						# back to back means facing apart: the cushion before the back
						# looks one way down the car and the one behind it looks the
						# other. One rule for the whole bench sits every second
						# passenger staring into the upholstery.
						"facing": 0.0 if facing_pair > 0.0 else PI,
						"carriage": i,
					})
	return out


## The chairs in a carriage, as seats, in the same shape the benches use.
##
## A room furnished with tables and chairs has no benches at all, so without this
## the dining car is a room nobody can sit down in. Which props are seats is a fact
## about the prop, stamped onto the placement by gen-content out of the library
## manifest, so a new chair is a spec that says [code]seats = true[/code] and
## nothing here changes.
##
## [CLocomotion] carries a forward offset of -PI/2, so a facing of zero walks a body
## along +X while a mesh rotation of zero points it at -Z. The quarter turn between
## them is why a chair's own facing is not its passenger's.
func _prop_seats(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for placement: Dictionary in GameContent.furnishings_at(index):
		if not bool(placement.get("seats", false)):
			continue
		var stands := _furnishing_offset(placement)
		out.append({
			"at": global_position + Vector3(_offset(index), 0.0, 0.0) + stands
				+ Vector3(0.0, float(placement.get("cushionHeight", 0.0)), 0.0),
			"facing": float(placement.get("facing", 0.0)) + PI * 0.5,
			"carriage": index,
		})
	return out


## Every prop in the consist, in world space, in the order the carriages were built.
##
## The mirror of [method seat_anchors]: authored locally, resolved through the same
## [method _offset], so both survive the train changing length for the same reason.
func prop_anchors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(carriage_count):
		for placement: Dictionary in GameContent.furnishings_at(i):
			out.append({
				"at": global_position + Vector3(_offset(i), 0.0, 0.0)
					+ _furnishing_offset(placement),
				"facing": float(placement.get("facing", 0.0)),
				"prop": StringName(placement.get("prop", "")),
				"carriage": i,
			})
	return out
