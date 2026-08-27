extends ECSComponent
class_name CLamp

## 1 is normal, 0 is dark. Kill a single carriage without touching the rest.
var dimming: float = 1.0

## 0 is steady. Anything above starts the lamps stuttering.
var flicker_hz: float = 0.0
var flicker_depth: float = 0.0
var flicker_phase: float = 0.0
var energy: float = 0.0
