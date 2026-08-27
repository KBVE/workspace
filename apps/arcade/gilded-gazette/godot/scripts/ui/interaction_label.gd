extends Control
class_name InteractionLabel

## InteractionLabel says what the key would do, in words, above the middle of the screen.
##
## A sibling of the world's [SubViewportContainer] rather than a child, for the reason
## the [Crosshair] is: [RenderBudget] divides everything inside that container, and text
## is the last thing that should be rendered at half resolution and scaled back up.
##
## It reads [CPrompt] and does no deciding of its own. What is offered, and what is
## refusing to be offered, is [SPrompt]'s to work out; this turns it into English.

const WORDS := {
	CPrompt.OPEN_THE_DOOR: "Open the door",
	CPrompt.SHUT_THE_DOOR: "Close the door",
	CPrompt.SIT_DOWN: "Sit down",
	CPrompt.STAND_UP: "Stand up",
	CPrompt.READ_IT: "Read it",
}

## What is said instead of the verb when the thing will not answer. Written as the
## carriage would put it rather than as an error: the player is being told about a
## door, not about a failed call.
const REFUSALS = {
	CPrompt.LOCKED: "Locked",
	CPrompt.TAKEN: "Taken",
	CPrompt.IN_THE_DOORWAY: "You are standing in the way",
	CPrompt.HELD_OPEN: "Somebody is coming through",
}

## What the key is called on the two devices that have one. Touch has neither, and is
## told to tap instead.
const KEY_NAME := "F"

const INK := Color(0.94, 0.92, 0.86, 0.92)
const REFUSED_INK := Color(0.86, 0.78, 0.72, 0.85)
const SHADOW := Color(0.0, 0.0, 0.0, 0.55)
const FROM_THE_BOTTOM_PIXELS := 96.0
const FONT_PIXELS := 17

## Set by [Train]. Read every frame rather than pushed, because a prompt changes as the
## player turns and a signal per frame is a signal per frame.
var prompt: CPrompt

## True where there is no keyboard to name, so the line reads "Tap to open the door".
var touch_only := false

var _shown := ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var line := _line()
	if line == _shown:
		return
	_shown = line
	queue_redraw()


func _draw() -> void:
	if _shown.is_empty():
		return
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(_shown, HORIZONTAL_ALIGNMENT_LEFT, -1,
		FONT_PIXELS).x
	var at := Vector2((size.x - width) * 0.5, size.y - FROM_THE_BOTTOM_PIXELS)
	var refused := prompt != null and prompt.refusal != CPrompt.NOTHING
	draw_string(font, at + Vector2(1.0, 1.0), _shown, HORIZONTAL_ALIGNMENT_LEFT, -1,
		FONT_PIXELS, SHADOW)
	draw_string(font, at, _shown, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PIXELS,
		REFUSED_INK if refused else INK)


## The whole line, or nothing at all. Nothing is the common case and it has to look like
## nothing: a label that says "Nothing to do here" is a label that is always on screen.
func _line() -> String:
	if prompt == null or not prompt.offers_anything():
		return ""
	if prompt.refusal != CPrompt.NOTHING:
		return REFUSALS.get(prompt.refusal, "")
	var verb: String = WORDS.get(prompt.action, "")
	if verb.is_empty():
		return ""
	if not prompt.within_reach and not prompt.under_the_pointer:
		return ""
	# Which of the two ways of reaching it is live decides the wording. Both, and the
	# key wins: it is the one that works without moving the mouse off what you are
	# looking at.
	if prompt.within_reach:
		return "Tap to %s" % verb.to_lower() if touch_only \
			else "%s  [%s]" % [verb, KEY_NAME]
	return "Tap to %s" % verb.to_lower() if touch_only else "Click to %s" % verb.to_lower()
