extends SceneTree

## &gen -> builds res://scenes/train/train.scn around the real carriage.
##         run: godot --headless --path godot -s res://tools/build_train_scene.gd
## &bin -> .scn, not .tscn. The text form parses in 212ms against 15ms binary,
##         and that parse runs on the main thread inside wasm

const OUT := "res://scenes/train/train.scn"

## Kept in step with Train.AISLE_EYE by hand. Referencing the constant instead
## would compile train.gd in here, and it needs autoloads this tool never has.
const PLAYER_EYE := 2.60
const PLAYER_HEIGHT := 2.75
const PLAYER_RADIUS := 0.38

## Where the world's resolution starts. [RenderBudget] owns it from the first
## frame onward, so this is only what a scene opened in the editor shows.
##
## An earlier version of this comment argued for 1 on the strength of a 2560x1440
## desktop measurement, where 1 cost 1.68ms and 3 cost 1.55ms. That number is real
## and it is irrelevant: a desktop GPU is not fill-rate bound at 3.7M fragments
## and a phone at three device pixels per CSS pixel very much is. Measure on the
## device you are arguing about.
const RENDER_SHRINK := 1

## &instance -> never set owner inside an instanced scene. doing so packs the
##              instance's own children into THIS scene, and because the node
##              keeps scene_file_path, loading then produces both copies.
func _own(n: Node, root: Node) -> void:
	if n != root:
		n.owner = root
	if n != root and n.scene_file_path != "":
		return
	for c: Node in n.get_children():
		_own(c, root)

## Detail-shader materials, built ONCE and shared by every carriage in the consist.
## Keyed by source material so N cars cost N transforms, not N material sets.
var _shared: Dictionary = {}

func _material_for(src: StandardMaterial3D) -> ShaderMaterial:
	var key := src.resource_name
	if _shared.has(key):
		return _shared[key]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/carriage_2sided.gdshader") \
		if src.cull_mode == BaseMaterial3D.CULL_DISABLED \
		else load("res://shaders/carriage.gdshader")
	sm.set_shader_parameter("tex_albedo", src.albedo_texture)
	sm.set_shader_parameter("tex_detail", load("res://assets/train/detail_normal.png"))
	_shared[key] = sm
	return sm

func _apply_detail_shader(node: Node) -> int:
	var count := 0
	for mi: Node in _mesh_instances(node):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for i in range(m.get_surface_count()):
			var src := m.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			# &glass -> the window panes stay a normal transparent material
			if src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			(mi as MeshInstance3D).set_surface_override_material(i, _material_for(src))
			count += 1
	# &glow -> one shared emissive material so night lighting is a single write
	var em := node.get_node_or_null("emissive") as MeshInstance3D
	if em != null and em.mesh.surface_get_material(0) != null:
		if not _shared.has("@glow"):
			var g: StandardMaterial3D = em.mesh.surface_get_material(0).duplicate()
			g.emission_enabled = true
			g.emission = Color(1.0, 0.82, 0.55)
			_shared["@glow"] = g
		em.set_surface_override_material(0, _shared["@glow"])
	return count

func _mesh_instances(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	if n is MeshInstance3D:
		out.append(n)
	for c: Node in n.get_children():
		out.append_array(_mesh_instances(c))
	return out


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "Train"
	root.set_script(load("res://scripts/train/train.gd"))

	# The world renders into a SubViewport so its resolution is independent of
	# the HUD's. stretch_shrink divides the container size, so 2 is a quarter of
	# the fragments and the upscale stays a whole number of pixels.
	var screen := CanvasLayer.new(); screen.name = "Screen"
	screen.layer = -1
	root.add_child(screen)

	var frame := SubViewportContainer.new(); frame.name = "Frame"
	frame.stretch = true
	frame.stretch_shrink = RENDER_SHRINK
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(frame)

	var world := SubViewport.new(); world.name = "World"
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# picking belongs to whichever viewport owns the camera, and that is no
	# longer the window
	world.physics_object_picking = true
	world.msaa_3d = Viewport.MSAA_4X
	world.handle_input_locally = false
	frame.add_child(world)

	# &consist -> ONE node. carriages are spawned at runtime by Consist, so none
	#             geometry is baked into this scene: the .scn stays small and the
	#             duplicated-instance bug cannot recur by construction.
	var consist := Node3D.new()
	consist.name = "Consist"
	consist.set_script(load("res://scripts/train/consist.gd"))
	consist.set("carriage_scene", load("res://assets/train/carriage_empty.gltf"))
	consist.set("seating_scene", load("res://assets/train/carriage_seating.gltf"))
	consist.set("doors_scene", load("res://assets/train/carriage_doors.gltf"))
	consist.set("props_scene", load("res://assets/props/props.glb"))
	# shared/data/locations furnishes the guard's van with crates and a cold stove,
	# so the bench seating in there was always contradicting its own description.
	# The dining car loses its benches for a different reason: the stock seating is
	# back to back, which seats every second diner facing away from the table, and
	# the tables and chairs it gets instead are props that food can later stand on.
	var bare: Array[StringName] = [&"guard_van", &"dining"]
	var undressed: Array[int] = []
	for room: StringName in bare:
		var at := GameContent.carriage_locations().find(room)
		assert(at >= 0, "no %s in shared/data/locations" % room)
		# typed, because set() drops an untyped Array on an Array[int] property and
		# leaves the default behind without saying so
		undressed.append(at)
	consist.set("undressed_carriages", undressed)
	consist.set("detail_normal", load("res://assets/train/detail_normal.png"))
	# &count -> the consist is as long as the content says. A location authored
	#           with a carriage index is a carriage that has to exist.
	consist.set("carriage_count", GameContent.carriage_locations().size())
	consist.set("pitch", 21.0)
	world.add_child(consist)
	print("consist node placed (cars spawn at runtime)")

	# The player is a body, not a floating camera. Nothing draws it: a
	# CollisionShape3D is invisible at runtime, and the capsule is what movement
	# will push around once the carriage carries colliders of its own.
	var player := CharacterBody3D.new(); player.name = "Player"
	world.add_child(player)

	var body := CollisionShape3D.new(); body.name = "Body"
	var capsule := CapsuleShape3D.new()
	capsule.height = PLAYER_HEIGHT
	capsule.radius = PLAYER_RADIUS
	body.shape = capsule
	# the node origin sits at the eye, so the capsule hangs below it and its feet
	# land on the carriage floor
	body.position = Vector3(0.0, PLAYER_HEIGHT * 0.5 - PLAYER_EYE, 0.0)
	player.add_child(body)

	var cam := Camera3D.new(); cam.name = "Camera3D"
	cam.fov = 62.0
	cam.far = 1500.0
	player.add_child(cam)

	var we := WorldEnvironment.new(); we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_horizon_color = Color(0.66, 0.68, 0.72)
	psm.ground_horizon_color = Color(0.36, 0.38, 0.34)
	psm.ground_bottom_color = Color(0.17, 0.19, 0.16)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.26
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	# &fog -> hides the terrain plane's far edge and does the mood work a murder
	#         mystery wants. cheaper than any geometry that would hide it
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.66, 0.71)
	env.fog_density = 0.005
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.4
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new(); sun.name = "Sun"
	sun.light_energy = 1.3
	# a shadow map is a second depth pass over every visible carriage, and PSX
	# never had one
	sun.shadow_enabled = false
	world.add_child(sun)


	var backdrop := Node3D.new(); backdrop.name = "Backdrop"; world.add_child(backdrop)

	# &ground -> scrolls along X to sell motion while the carriage stays put
	var terrain := MeshInstance3D.new(); terrain.name = "Terrain"
	var pm := PlaneMesh.new(); pm.size = Vector2(2400.0, 2400.0)
	terrain.mesh = pm
	terrain.position = Vector3(0.0, -0.69, 0.0)
	var tm := StandardMaterial3D.new()
	tm.albedo_texture = load("res://assets/train/terrain.png")
	tm.uv1_scale = Vector3(240.0, 240.0, 1.0)
	tm.roughness = 1.0
	tm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	terrain.set_surface_override_material(0, tm)
	backdrop.add_child(terrain)

	# &night -> painted parallax forest, faded in by the day cycle. mirrored so
	#           both window rows have something sweeping past.
	var forest := Node3D.new()
	forest.name = "Forest"
	forest.set_script(load("res://scripts/world/parallax_backdrop.gd"))
	var tex: Array[Texture2D] = []
	for n: String in ["01_mist", "02_bushes", "03_particles", "04_forest", "05_particles",
			"06_forest", "07_forest", "08_forest", "09_forest"]:
		# &sky -> 10_sky dropped; the ProceduralSky already tracks the sun and the
		#         painted one would need depth-proportional size to cover the view
		tex.append(load("res://assets/backdrop/%s.png" % n))
	forest.set("layers", tex)
	backdrop.add_child(forest)


	var lighting := Node3D.new()
	lighting.name = "Lighting"
	lighting.set_script(load("res://scripts/world/world_lighting.gd"))
	world.add_child(lighting)
	lighting.set("sun_path", NodePath("../Sun"))
	lighting.set("environment_path", NodePath("../WorldEnvironment"))
	lighting.set("terrain_path", NodePath("../Backdrop/Terrain"))

	_own(root, root)
	var packed := PackedScene.new()
	assert(packed.pack(root) == OK, "pack failed")
	# &guard -> this file is hand-edited in the editor. refuse to clobber it
	#           unless the caller explicitly opts in with OVERWRITE=1, and write
	#           somewhere harmless otherwise. a silent overwrite already cost a
	#           scene once.
	var target := OUT
	if FileAccess.file_exists(ProjectSettings.globalize_path(OUT)) \
			and not OS.has_environment("OVERWRITE"):
		target = OUT.get_basename() + "_generated." + OUT.get_extension()
		push_warning("%s exists; wrote %s instead. set OVERWRITE=1 to replace it." % [OUT, target])
		print("REFUSED to overwrite ", OUT)
	assert(ResourceSaver.save(packed, target) == OK, "save failed")
	print("SAVED ", target)
	root.free()
	quit()
