extends ECSSystem
class_name SWorldLighting

## SWorldLighting turns daylight into every value [WorldLighting] paints.

## Terrain frames scrolled per second. Sells motion while the carriage stays put.
var terrain_scroll_per_second: float = 0.045

func _on_update(delta: float) -> void:
	var clocks: Array = view(&"CTimeOfDay")
	if clocks.is_empty():
		return
	var daylight: float = clocks[0].daylight
	# behind an opaque canopy the terrain is pure overdraw, and so is the
	# material write that scrolls it
	var canopies: Array = view(&"CParallax")
	var canopy_opacity: float = canopies[0].canopy_opacity if not canopies.is_empty() else 0.0

	for entry: Dictionary in multi_view([ECSViewComponent, CWorldLighting]):
		var lighting := entry[&"ECSViewComponent"].view as WorldLighting
		if not is_instance_valid(lighting):
			continue
		var state: CWorldLighting = entry[&"CWorldLighting"]
		state.terrain_visible = canopy_opacity < 0.99
		if state.terrain_visible:
			state.terrain_scroll = fposmod(state.terrain_scroll + terrain_scroll_per_second * delta, 1.0)
		lighting.apply(daylight, state.terrain_visible, state.terrain_scroll)
