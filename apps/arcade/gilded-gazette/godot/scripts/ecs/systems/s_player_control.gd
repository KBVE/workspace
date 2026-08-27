extends ECSSystem
class_name SPlayerControl

## SPlayerControl turns keys, sticks, mice and swipes into [CInput].
##
## Nothing here touches a transform. It is the only place that reads [Input], so a
## replay or a test can drive the same entity by writing [CInput] directly and
## calling [method set_update] false.
##
## Pointers and touchscreens do not share a scheme. A mouse is a distance: it moves and
## the head follows by as much. A stick is a rate: it is held over and the head keeps
## turning while it is. Both end up in the same units here, and nothing downstream can
## tell which hand it came from.

## Screen heights a mouse travels for one unit, so a look covers the same arc on any
## display.
var mouse_screens_per_unit: float = 2.6

## Units a second at full deflection. Held rather than swiped, so it scales with frame
## time the way a key does.
var look_stick_units_per_second: float = 2.2

## The two thumbs, from -1 to 1 either way, written by [TouchControls]. Left looks and
## right walks: a phone is held in two hands and the hand that aims is the one that is
## not also deciding where to stand.
var look_stick := Vector2.ZERO
var move_stick := Vector2.ZERO

## Whether devices are being read at all. A debug run steals the window focus the
## moment it launches, and a game that is already driving the character eats the
## keystrokes meant for the editor behind it. So a run with a real window starts inert
## and waits to be clicked into; a headless one never had focus to steal and starts
## live, which is what keeps the tests driving real actions.
var engaged: bool = true

## Cleared by [TouchControls] while the thumbs are up. The web export emulates a mouse
## from touch, so every thumb on a stick would otherwise also be a left click on
## whatever the stick was sitting over.
var reading_pointer_clicks: bool = true

var _was_engaged := false
var _was_clicking := false

var _look_units := Vector2.ZERO

## Set by a tap and spent on the next frame, because a tap is over before the frame it
## happened in is drawn and a flag that outlived it would fire twice.
var _tapped_jump := false
var _tapped_interact := false
var _tapped_secondary := false


## Mouse. Across is turn, up is pitch.
func accumulate_look(relative_pixels: Vector2, window_height: float) -> void:
	if window_height > 0.0:
		_look_units += relative_pixels / window_height * mouse_screens_per_unit


## A thumb asking for something the keyboard has a key for. Spent on the next update.
func tap_jump() -> void:
	_tapped_jump = true


func tap_interact() -> void:
	_tapped_interact = true


func tap_secondary() -> void:
	_tapped_secondary = true


## Tab takes control and gives it back. Read while inert, because it is the only way out
## of it.
##
## Deliberately not the mouse. Clicking used to engage, which sounds right and is not:
## clicking into the window is exactly what you do to look at a debug run, so the run
## took the keyboard on the first click every time and the inert state was worth
## nothing. It has to be a gesture nobody makes by accident.
func _read_engagement() -> void:
	if Input.is_action_just_pressed(&"take_control"):
		engaged = not engaged
	elif Input.is_action_just_pressed(&"ui_cancel"):
		engaged = false


func _on_update(delta: float) -> void:
	_read_engagement()
	if not engaged:
		_look_units = Vector2.ZERO
		_tapped_jump = false
		_tapped_interact = false
		_tapped_secondary = false
		for idle: CInput in view(&"CInput"):
			idle.walk_units = 0.0
			idle.strafe_units = 0.0
			idle.turn_units = 0.0
			idle.pitch_units = 0.0
			idle.jump_requested = false
			idle.interact_requested = false
			idle.secondary_requested = false
			idle.pointer_clicked = false
			idle.holding_look = false
			idle.recentring_view = false
		return

	# a held key is a rate, so it scales with frame time; a gesture is already a
	# distance, so it must not. Swap either sign to invert that axis.
	var walk_units := (Input.get_axis(&"move_down", &"move_up") + move_stick.y) * delta
	var strafe_units := (Input.get_axis(&"move_left", &"move_right") + move_stick.x) * delta
	var stick_look := look_stick * look_stick_units_per_second * delta
	var turn_units := stick_look.x - _look_units.x
	var pitch_units := stick_look.y - _look_units.y
	# a thumb on the look stick is looking, the same as a held right button, so the
	# crosshair comes up on a touchscreen without a second thing to press
	var holding_look := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
		or not look_stick.is_zero_approx()
	# the middle button, because left picks up evidence and right is already the look
	var recentring_view := Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	var jump_requested := Input.is_action_just_pressed(&"jump") or _tapped_jump
	var interact_requested := Input.is_action_just_pressed(&"interact") or _tapped_interact
	var secondary_requested := Input.is_action_just_pressed(&"interact_secondary") \
		or _tapped_secondary
	# a click that woke an inert run is spent doing exactly that, or the first thing the
	# player clicks to take control of the window is also the first thing they open
	var pointer_clicked := reading_pointer_clicks and _was_engaged \
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _was_clicking
	_was_clicking = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_was_engaged = engaged
	_look_units = Vector2.ZERO
	_tapped_jump = false
	_tapped_interact = false
	_tapped_secondary = false
	for intent: CInput in view(&"CInput"):
		intent.walk_units = walk_units
		intent.strafe_units = strafe_units
		intent.turn_units = turn_units
		intent.pitch_units = pitch_units
		intent.holding_look = holding_look
		intent.recentring_view = recentring_view
		intent.jump_requested = jump_requested
		intent.interact_requested = interact_requested
		intent.secondary_requested = secondary_requested
		intent.pointer_clicked = pointer_clicked
