extends ECSComponent
class_name CLocomotion

var forward_yaw_offset_radians: float = -PI * 0.5

var facing_radians: float = 0.0

## Where the head is aimed. The body never carries this: pitching a
## [CharacterBody3D] would tilt the collision capsule with it.
var pitch_radians: float = 0.0
var eye_height_metres: float = 1.64
var turn_radians_per_unit: float = 2.4

## How fast the view returns to level once the player stops aiming it.
var pitch_recentre_radians_per_second: float = 2.5
var walk_metres_per_unit: float = 4.0

## How high a standing jump carries him. Metres, so it is a number anyone can argue
## with rather than an impulse nobody can picture.
var jump_rise_metres: float = 0.45

var gravity_metres_per_second_squared: float = 9.8

## How far above his stance he currently is, and how fast that is changing. He is
## carried rather than dropped: the walk pins Y to the eye height, because the drawn
## deck is a metre and a quarter above the collision floor and anything that fell would
## fall to the wrong one. A jump is an offset on top of that pin, so it lands him back
## on the deck he can see instead of the one the physics knows about.
var height_above_stance_metres: float = 0.0
var rise_metres_per_second: float = 0.0

func airborne() -> bool:
	return height_above_stance_metres > 0.0


## Signed along the walking direction, so backing up reads negative. Written by
## [SLocomotion] from distance actually covered, which is zero against a wall.
var forward_metres_per_second: float = 0.0

## The same measurement across the walking direction, positive to the character's own
## right. Kept apart from the forward speed rather than folded into one magnitude,
## because the legs do something different sideways.
var strafe_metres_per_second: float = 0.0
