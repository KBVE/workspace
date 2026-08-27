extends Control
class_name TouchControls

## TouchControls is the two thumbs and the two buttons a phone plays this with.
##
## Left half of the screen looks, right half walks, and a tap on either is the thing
## that hand would otherwise need a button for: tap the left to use what is in front of
## you, tap the right to jump. The two buttons are the cases a tap cannot cover -- [F]
## when the thumb is nowhere near the left half, and [G] for the second answer when a
## bench and a door are both within reach.
##
## Nothing here decides anything about the world. It writes sticks and taps onto
## [SPlayerControl], which is still the only thing that reads a device, so the character
## cannot tell a thumb from a keyboard.
##
## Landscape is assumed. The sticks still float wherever the thumb lands, but each
## half draws a faint ring at the spot its thumb is expected to sit, so a player who
## has never held this before can see there is a stick there at all. The button
## cluster hangs off the bottom right corner where the hand already is.

## Button radius and where the cluster sits, in pixels off the bottom right corner.
const BUTTON_RADIUS := 44.0
const INTERACT_FROM_CORNER := Vector2(84.0, 196.0)
const SECONDARY_FROM_CORNER := Vector2(184.0, 112.0)

## Where the untouched rings are drawn, as a share of the screen. The walking one sits
## inboard of the button cluster rather than mirroring the looking one, because the
## outboard half of that corner is already buttons.
const LOOKING_HOME_ACROSS := 0.16
const WALKING_HOME_ACROSS := 0.60
const HOME_DOWN := 0.76

const RING := Color(1.0, 1.0, 1.0, 0.22)
const KNOB := Color(1.0, 1.0, 1.0, 0.38)
const RESTING_RING := Color(1.0, 1.0, 1.0, 0.14)
const RESTING_KNOB := Color(1.0, 1.0, 1.0, 0.10)
const LABEL := Color(1.0, 1.0, 1.0, 0.62)
const LABEL_PIXELS := 22

## Written to rather than read from, so a device is still read in exactly one place.
var control: SPlayerControl

## Drawn beside these, and shown and hidden with them: a phone aims with the middle of
## the screen, so the mark for where a look lands has to be up the whole time rather
## than only while a thumb is on the looking stick.
var crosshair: Crosshair

## A touchscreen the engine failed to notice is still a touchscreen once something has
## landed on it, so the first finger reveals the controls whatever [DisplayServer] said.
var _a_finger_has_landed := false

var _looking := TouchStick.new()
var _walking := TouchStick.new()

## Which finger is on which button, or -1. Held by finger rather than by a flag,
## because a second thumb landing on the other button must not release the first.
var _interact_finger := -1
var _secondary_finger := -1

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	visible = _a_finger_has_landed or DisplayServer.is_touchscreen_available()
	if crosshair != null:
		crosshair.always_visible = visible
	if control == null:
		return
	# emulate_mouse_from_touch turns every thumb into a left click at the thumb, which
	# would pick up whatever the stick happens to be sitting over. A phone opens things
	# with the taps and [F] instead.
	control.reading_pointer_clicks = not visible
	if not visible:
		return
	var height := float(size.y)
	_looking.tick(delta)
	_walking.tick(delta)
	control.look_stick = _looking.axis(height)
	control.move_stick = _walking.axis(height)
	queue_redraw()


## _input rather than _gui_input, because this control ignores the mouse so that a tap
## still reaches the evidence behind it, and a control that ignores the mouse is never
## offered gui events either.
func _input(event: InputEvent) -> void:
	if control == null:
		return
	if event is InputEventScreenTouch:
		_a_finger_has_landed = true
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index, touch.position)
		else:
			_release(touch.index)
	elif event is InputEventScreenDrag:
		var moved := event as InputEventScreenDrag
		var height := float(size.y)
		if _looking.finger == moved.index:
			_looking.drag(moved.position, height)
		elif _walking.finger == moved.index:
			_walking.drag(moved.position, height)


func _press(finger: int, at: Vector2) -> void:
	# buttons first: they sit inside a stick's half, and a thumb that came down on one
	# meant the button rather than a stick that happens to be under it
	if _interact_finger < 0 and at.distance_to(_interact_at()) <= BUTTON_RADIUS:
		_interact_finger = finger
		return
	if _secondary_finger < 0 and at.distance_to(_secondary_at()) <= BUTTON_RADIUS:
		_secondary_finger = finger
		return
	var stick := _looking if at.x < size.x * 0.5 else _walking
	if not stick.pressed:
		stick.press(finger, at)


func _release(finger: int) -> void:
	if finger == _interact_finger:
		_interact_finger = -1
		control.tap_interact()
		return
	if finger == _secondary_finger:
		_secondary_finger = -1
		control.tap_secondary()
		return
	if finger == _looking.finger:
		if _looking.release():
			control.tap_interact()
		control.look_stick = Vector2.ZERO
	elif finger == _walking.finger:
		if _walking.release():
			control.tap_jump()
		control.move_stick = Vector2.ZERO


func _interact_at() -> Vector2:
	return size - INTERACT_FROM_CORNER


func _secondary_at() -> Vector2:
	return size - SECONDARY_FROM_CORNER


func _looking_home() -> Vector2:
	return Vector2(size.x * LOOKING_HOME_ACROSS, size.y * HOME_DOWN)


func _walking_home() -> Vector2:
	return Vector2(size.x * WALKING_HOME_ACROSS, size.y * HOME_DOWN)


func _draw() -> void:
	_draw_stick(_looking, _looking_home())
	_draw_stick(_walking, _walking_home())
	_draw_button(_interact_at(), "F", _interact_finger >= 0)
	_draw_button(_secondary_at(), "G", _secondary_finger >= 0)


## Faint at its home while nobody is on it, and solid wherever the thumb actually put
## it. The home ring is a label for the half rather than a promise about where the
## stick appears, which is why it is drawn dimmer than the live one.
func _draw_stick(stick: TouchStick, home: Vector2) -> void:
	var throw := size.y * TouchStick.THROW_SCREENS
	if not stick.pressed:
		draw_arc(home, throw, 0.0, TAU, 48, RESTING_RING, 2.0, true)
		draw_circle(home, throw * 0.36, RESTING_KNOB)
		return
	draw_arc(stick.origin, throw, 0.0, TAU, 48, RING, 2.0, true)
	draw_circle(stick.origin + (stick.at - stick.origin).limit_length(throw),
		throw * 0.36, KNOB)


func _draw_button(at: Vector2, letter: String, held: bool) -> void:
	draw_circle(at, BUTTON_RADIUS, KNOB if held else RING)
	draw_arc(at, BUTTON_RADIUS, 0.0, TAU, 40, LABEL, 2.0, true)
	var font := ThemeDB.fallback_font
	var wide := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_PIXELS)
	draw_string(font, at + Vector2(-wide.x * 0.5, LABEL_PIXELS * 0.36), letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_PIXELS, LABEL)
