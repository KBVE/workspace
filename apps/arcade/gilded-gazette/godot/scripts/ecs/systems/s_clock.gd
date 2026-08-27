extends ECSSystem
class_name SClock

## SClock advances in-world time and derives everything time-shaped from it.

const MINUTES_PER_DAY := 1440

var world_minutes_per_second: float = 1.0

func _on_update(delta: float) -> void:
	for clock: CTimeOfDay in view(&"CTimeOfDay"):
		if clock.running:
			clock.phase = fposmod(
				clock.phase + delta * world_minutes_per_second / MINUTES_PER_DAY, 1.0)
		_derive(clock)


func _derive(clock: CTimeOfDay) -> void:
	clock.daylight = clampf(cos(clock.phase * TAU) * 0.5 + 0.5, 0.0, 1.0)
	# phase 0 is noon, so the hour hand starts half a day round
	clock.minutes_past_midnight = int(fposmod(clock.phase * 24.0 + 12.0, 24.0) * 60.0)
	if clock.minutes_past_midnight == clock.last_published_minute:
		return
	clock.last_published_minute = clock.minutes_past_midnight
	notify(GameEvents.WORLD_CLOCK, {
		"hour": clock.minutes_past_midnight / 60,
		"minute": clock.minutes_past_midnight % 60,
	})


## Republishes immediately rather than waiting for the next frame.
func set_phase(clock: CTimeOfDay, value: float) -> void:
	clock.phase = fposmod(value, 1.0)
	_derive(clock)


## Aims at the middle of the minute: _derive truncates, so landing on its edge
## round-trips to the minute before.
func set_minutes(clock: CTimeOfDay, minutes: int) -> void:
	set_phase(clock, ((float(minutes) + 0.5) / 60.0 - 12.0) / 24.0)
