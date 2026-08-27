extends ECSSystem
class_name SCarriageLamps

## SCarriageLamps lights each carriage separately, so one carriage can go dark or
## start stuttering while the rest of the train stays lit.

## Lamp energy at midnight and at noon.
var energy_at_night: float = 4.0
var energy_at_noon: float = 1.1
## The lamp glass shares one material across every carriage, so its glow cannot be
## per-carriage. It follows the base level.
var lamp_glass: StandardMaterial3D

func _on_update(delta: float) -> void:
	var clocks: Array = view(&"CTimeOfDay")
	if clocks.is_empty():
		return
	var daylight: float = clocks[0].daylight
	var base_energy := lerpf(energy_at_night, energy_at_noon, clampf((daylight - 0.2) * 2.2, 0.0, 1.0))
	if lamp_glass != null:
		lamp_glass.emission_energy_multiplier = base_energy * 0.6

	for entry: Dictionary in multi_view([ECSViewComponent, CLamp]):
		var holder := entry[&"ECSViewComponent"].view as Node3D
		var lamp: CLamp = entry[&"CLamp"]
		lamp.energy = base_energy * lamp.dimming * _flicker(lamp, delta)
		if not is_instance_valid(holder) or not holder.visible:
			continue
		for light: OmniLight3D in holder.get_children():
			light.light_energy = lamp.energy


## A plain sine reads as a pulse, not a fault. Beating two frequencies that do
## not divide evenly keeps it irregular without a RNG.
func _flicker(lamp: CLamp, delta: float) -> float:
	if lamp.flicker_hz <= 0.0 or lamp.flicker_depth <= 0.0:
		return 1.0
	lamp.flicker_phase = fposmod(lamp.flicker_phase + delta * lamp.flicker_hz, 1.0)
	var beat := sin(lamp.flicker_phase * TAU) * sin(lamp.flicker_phase * TAU * 2.7)
	return clampf(1.0 - lamp.flicker_depth * (0.5 - 0.5 * beat), 0.0, 1.0)
