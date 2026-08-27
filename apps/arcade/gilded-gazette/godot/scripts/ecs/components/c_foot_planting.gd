extends ECSComponent
class_name CFootPlanting

## CFootPlanting is how much the feet are being held to the floor.
##
## The correction is only meaningful with weight on the legs. In the air there is no
## floor to plant against and the clip's own legs are the right ones, so the weight
## falls away on takeoff and comes back as he lands. Easing rather than switching,
## because a foot that snaps to the deck on the landing frame reads as a flinch.

var weight: float = 1.0

## Seconds to fade the correction in and out. Short: it is a centimetre or two of
## error, and anything slower than a footfall arrives after it mattered.
var ease_seconds: float = 0.18
