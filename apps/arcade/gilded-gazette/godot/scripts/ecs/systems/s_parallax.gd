extends ECSSystem
class_name SParallax

## SParallax controls the [ParallaxBackdrop] from the viewer and the world clock.

func _on_update(delta: float) -> void:
	var viewers: Array = view(&"CViewer")
	var clocks: Array = view(&"CTimeOfDay")
	if viewers.is_empty() or clocks.is_empty():
		return
	var viewer: CViewer = viewers[0]
	var daylight: float = clocks[0].daylight

	for entry: Dictionary in multi_view([ECSViewComponent, CParallax]):
		var backdrop := entry[&"ECSViewComponent"].view as ParallaxBackdrop
		if not is_instance_valid(backdrop):
			continue
		var parallax: CParallax = entry[&"CParallax"]
		parallax.scroll_offset += backdrop.metres_per_second * delta / backdrop.frame_width_metres()
		parallax.canopy_opacity = backdrop.canopy_opacity_for_daylight(daylight)
		backdrop.apply(viewer.world_x, parallax.scroll_offset, parallax.canopy_opacity)
