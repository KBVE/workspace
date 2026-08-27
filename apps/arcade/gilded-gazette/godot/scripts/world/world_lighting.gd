extends Node3D
class_name WorldLighting

## WorldLighting paints everything daylight touches, driven by [SWorldLighting].
## Sun, environment, sky ground and terrain move together because they are one
## decision: at dusk the lamps come up BECAUSE the sun goes down.

const SUN_NIGHT := Color(0.42, 0.52, 0.78)
const SUN_DAWN := Color(1.0, 0.72, 0.48)
const SUN_NOON := Color(1.0, 0.96, 0.88)
const FOG_NIGHT := Color(0.05, 0.07, 0.12)
const FOG_DAY := Color(0.62, 0.66, 0.71)
const GROUND_HORIZON_NIGHT := Color(0.04, 0.05, 0.08)
const GROUND_HORIZON_DAY := Color(0.36, 0.38, 0.34)
const GROUND_BOTTOM_NIGHT := Color(0.02, 0.02, 0.04)
const GROUND_BOTTOM_DAY := Color(0.17, 0.19, 0.16)

@export var sun_path: NodePath
@export var environment_path: NodePath
@export var terrain_path: NodePath
@export var terrain_uv_scale: float = 12.0

var _sun: DirectionalLight3D
var _environment: Environment
var _sky: ProceduralSkyMaterial
var _terrain: MeshInstance3D
var _terrain_material: StandardMaterial3D


func _ready() -> void:
	_sun = get_node(sun_path)
	_environment = (get_node(environment_path) as WorldEnvironment).environment
	_sky = _environment.sky.sky_material
	_terrain = get_node(terrain_path)
	_terrain_material = _terrain.get_surface_override_material(0)


func apply(daylight: float, terrain_visible: bool, terrain_scroll: float) -> void:
	_sun.rotation = Vector3(lerpf(0.26, -1.05, daylight), deg_to_rad(-24.0), 0.0)
	_sun.light_energy = lerpf(0.0, 1.5, pow(daylight, 1.3))
	_sun.light_color = SUN_NIGHT \
		.lerp(SUN_DAWN, clampf(daylight * 2.2, 0.0, 1.0)) \
		.lerp(SUN_NOON, clampf((daylight - 0.45) * 2.0, 0.0, 1.0))

	_environment.ambient_light_energy = lerpf(0.10, 0.45, daylight)
	_environment.fog_light_color = FOG_NIGHT.lerp(FOG_DAY, daylight)
	_sky.ground_horizon_color = GROUND_HORIZON_NIGHT.lerp(GROUND_HORIZON_DAY, daylight)
	_sky.ground_bottom_color = GROUND_BOTTOM_NIGHT.lerp(GROUND_BOTTOM_DAY, daylight)

	_terrain.visible = terrain_visible
	if terrain_visible:
		_terrain_material.uv1_offset = Vector3(terrain_scroll * terrain_uv_scale, 0.0, 0.0)
