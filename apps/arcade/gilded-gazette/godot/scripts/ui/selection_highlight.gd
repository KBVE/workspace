extends Node3D
class_name SelectionHighlight

## SelectionHighlight draws the outline around whatever the pointer is on.
##
## One node, moved and reshaped, rather than a shader on every seat and door in the
## consist: only one thing is ever selected, and a material on five carriages worth of
## bench is five carriages worth of extra draw for the one frame it might be wanted.
##
## A door hands over its own mesh, so the outline is the shape of the door. A seat has
## no mesh of its own -- the benches are one trimesh a carriage and the ray cannot say
## which cushion it struck -- so it gets a box the size of a seat instead.

## One seat, not one bench: 0.45 of cushion along the car between the back and the gap,
## and 0.9 of it across. A box the width of the pair outlines both of them at once.
const CUSHION := Vector3(0.52, 0.5, 0.88)

## The hull outline and the wire box want different materials: one is a shell around a
## mesh that is drawn over the top of it, the other has nothing drawn over it at all and
## would read as a solid block if it were filled.
## One hull per mesh the target is made of. A door leaf is a glb, and a glb is as many
## meshes as whoever exported it felt like: outlining only the first leaves the panel
## drawn and the frame bare.
var _hulls: Array[MeshInstance3D] = []
var _shell: ShaderMaterial
var _wire: MeshInstance3D

func _ready() -> void:
	_shell = ShaderMaterial.new()
	_shell.shader = preload("res://shaders/selection_outline.gdshader")

	_wire = MeshInstance3D.new()
	_wire.mesh = _box_edges()
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color(1.0, 0.86, 0.55)
	ink.no_depth_test = true
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wire.material_override = ink
	_quieten(_wire)
	add_child(_wire)
	hide()


## A marker that lights the ceiling or casts a shadow is a bug somebody spends an
## afternoon on.
func _quieten(what: MeshInstance3D) -> void:
	what.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	what.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## Outlines every mesh in [param parts], each where it stands. The meshes are shared
## rather than copied, so a door mid-swing is outlined mid-swing.
func show_meshes(parts: Array[MeshInstance3D]) -> void:
	while _hulls.size() < parts.size():
		var hull := MeshInstance3D.new()
		hull.material_override = _shell
		_quieten(hull)
		add_child(hull)
		_hulls.append(hull)
	for i in _hulls.size():
		var hull := _hulls[i]
		if i >= parts.size():
			hull.hide()
			continue
		hull.mesh = parts[i].mesh
		hull.global_transform = parts[i].global_transform
		hull.show()
	_wire.hide()
	show()


## A box round the seat, drawn as twelve lines. The inverted hull cannot do this one:
## it is a shell meant to be seen around a mesh drawn over the top of it, and a seat has
## no mesh of its own to draw, so the shell arrives as a solid cream block.
func show_seat(at: Vector3) -> void:
	_wire.global_transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * CUSHION.y * 0.5)
	_wire.show()
	for hull: MeshInstance3D in _hulls:
		hull.hide()
	show()


func show_nothing() -> void:
	hide()


func _box_edges() -> ImmediateMesh:
	var half := CUSHION * 0.5
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for along in 3:
		var across := (along + 1) % 3
		var up := (along + 2) % 3
		for a in [-1.0, 1.0]:
			for b in [-1.0, 1.0]:
				var from := Vector3.ZERO
				from[across] = a * half[across]
				from[up] = b * half[up]
				var to := from
				from[along] = -half[along]
				to[along] = half[along]
				mesh.surface_add_vertex(from)
				mesh.surface_add_vertex(to)
	mesh.surface_end()
	return mesh
