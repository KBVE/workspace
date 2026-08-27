extends Node3D
class_name ParallaxBackdrop

## Scrolling forest backdrop of stacked 16:9 painted layers, driven by [SParallax].
##
## Every layer subtends the same angle and scrolls at [code]1 / depth[/code]. The
## train never moves, so that rate difference is the only parallax cue.

const ART_ASPECT := 1024.0 / 576.0

@export var layers: Array[Texture2D] = []
@export var nearest_layer_depth: float = 20.0
@export var depth_between_layers: float = 7.0
## Not derived from depth: that buried the art's ground line under the terrain.
@export var tree_height_metres: float = 37.0
@export var painted_ground_line_v: float = 0.75
## A side-window sightline runs nearly parallel to the train, so a quad only as
## wide as the view misses entirely.
@export var quad_width_per_metre_of_depth: float = 14.0
@export var recentre_on_viewer: bool = true
@export var metres_per_second: float = 14.5
@export var mirror_onto_both_sides: bool = true
@export var mist_layer_opacity: float = 0.45
## The unshaded art takes no scene light, so this is its moonlight.
@export var night_tint: Color = Color(0.34, 0.40, 0.56)
@export var daylight_at_full_canopy: float = 0.20
@export var daylight_at_bare_canopy: float = 0.55

var _layer_materials: Array[StandardMaterial3D] = []
var _layer_scroll_rates: PackedFloat32Array = []
var _layer_opacity_ceilings: PackedFloat32Array = []
var _canopy_opacity: float = 1.0


func _ready() -> void:
	for side in ([-1, 1] if mirror_onto_both_sides else [-1]):
		for layer_index in range(layers.size()):
			if layers[layer_index] != null:
				_build_layer(layer_index, side)
	apply(global_position.x, 0.0, 0.0)


## One scroll unit is one frame.
func frame_width_metres() -> float:
	return tree_height_metres * ART_ASPECT


func canopy_opacity_for_daylight(daylight: float) -> float:
	return clampf(
		remap(daylight, daylight_at_bare_canopy, daylight_at_full_canopy, 0.0, 1.0), 0.0, 1.0)


func covers_horizon() -> bool:
	return _canopy_opacity >= 0.99


func apply(viewer_world_x: float, scroll_offset: float, canopy_opacity: float) -> void:
	if recentre_on_viewer:
		global_position.x = viewer_world_x
	_canopy_opacity = clampf(canopy_opacity, 0.0, 1.0)
	for layer_index in range(_layer_materials.size()):
		var material := _layer_materials[layer_index]
		material.uv1_offset = Vector3(
			fposmod(scroll_offset * _layer_scroll_rates[layer_index], 1.0), 0.0, 0.0)
		material.albedo_color = Color(night_tint.r, night_tint.g, night_tint.b,
			_canopy_opacity * _layer_opacity_ceilings[layer_index])
	# a fully transparent quad still rasterises
	for quad: Node3D in get_children():
		quad.visible = _canopy_opacity > 0.01


func _build_layer(layer_index: int, side: int) -> void:
	var depth := nearest_layer_depth + layer_index * depth_between_layers
	var quad_height := tree_height_metres
	var quad_width := depth * quad_width_per_metre_of_depth

	var quad := MeshInstance3D.new()
	quad.name = "L%02d_%s" % [layer_index, "far" if side < 0 else "near"]
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(quad_width, quad_height)
	quad.mesh = quad_mesh
	quad.position = Vector3(0.0, quad_height * (painted_ground_line_v - 0.5), depth * side)
	quad.rotation = Vector3(0.0, 0.0 if side < 0 else PI, 0.0)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := StandardMaterial3D.new()
	material.albedo_texture = layers[layer_index]
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.uv1_scale = Vector3(quad_width / frame_width_metres(), 1.0, 1.0)
	# equal-angle quads at different depths flip between frames without this
	material.render_priority = -layer_index
	quad.set_surface_override_material(0, material)
	add_child(quad)

	_layer_materials.append(material)
	_layer_scroll_rates.append(nearest_layer_depth / depth)
	_layer_opacity_ceilings.append(
		mist_layer_opacity if "mist" in layers[layer_index].resource_path else 1.0)
