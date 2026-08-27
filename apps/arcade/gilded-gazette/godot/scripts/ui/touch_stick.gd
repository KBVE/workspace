extends RefCounted
class_name TouchStick

## TouchStick is one thumb: where it went down, where it is now, and whether letting go
## counted as a tap.
##
## Floating rather than fixed. The stick appears wherever the thumb lands inside its
## half of the screen, because a pad drawn at a fixed spot is a pad the player has to
## look down at to find, and the whole point of a stick on a phone is that the thumb
## is already there.
##
## No node, no drawing and no [Input]: this is the arithmetic on its own so it can be
## driven a frame at a time by a test on a machine with no screen.

## Longest a touch can last and still be a tap. A deliberate press is longer than this
## and a stick is held for much longer still.
const TAP_SECONDS := 0.28

## How far the thumb may travel, as a share of screen height, before the touch stops
## being a tap and becomes a stick. Small: a tap on glass always slides a little.
const TAP_SLOP_SCREENS := 0.025

## Thumb travel for full deflection, as a share of screen height. A stick this size sits
## under the thumb without the hand moving off the edge of the phone.
const THROW_SCREENS := 0.11

var pressed: bool = false

## Which finger this stick belongs to, so two thumbs on one screen do not swap sticks
## when one of them lifts. -1 while nobody is on it.
var finger: int = -1

## Where the thumb landed and where it is now, in screen pixels.
var origin := Vector2.ZERO
var at := Vector2.ZERO

var _held_seconds: float = 0.0
var _travelled_screens: float = 0.0


func press(which_finger: int, position: Vector2) -> void:
	pressed = true
	finger = which_finger
	origin = position
	at = position
	_held_seconds = 0.0
	_travelled_screens = 0.0


func drag(position: Vector2, screen_height: float) -> void:
	if not pressed or screen_height <= 0.0:
		return
	_travelled_screens = maxf(_travelled_screens,
		position.distance_to(origin) / screen_height)
	at = position


func tick(delta: float) -> void:
	if pressed:
		_held_seconds += delta


## Lets go, and says whether that was a tap. Quick and still: anything else was the
## player steering, and a stick released at full deflection must not also fire the
## button the tap is wired to.
func release() -> bool:
	var tapped := pressed and _held_seconds <= TAP_SECONDS \
		and _travelled_screens <= TAP_SLOP_SCREENS
	pressed = false
	finger = -1
	_held_seconds = 0.0
	_travelled_screens = 0.0
	return tapped


## Deflection, from -1 to 1 either way, with y up. Clamped to the throw rather than
## scaled by it, so pushing the thumb further than the stick reaches keeps it pinned at
## full rather than running away.
func axis(screen_height: float) -> Vector2:
	if not pressed or screen_height <= 0.0:
		return Vector2.ZERO
	var travel := (at - origin) / (screen_height * THROW_SCREENS)
	travel.y = -travel.y
	return travel if travel.length() <= 1.0 else travel.normalized()
