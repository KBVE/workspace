extends ECSComponent
class_name CPrompt

## CPrompt is what pressing the key would do right now, and why it would not.
##
## The interaction is answered by [SNotice], [SSeating] and [SDoor], each of which knows
## its own rules and none of which says anything until it is asked. Between them the
## player has three ways to reach a thing -- stand near it, point at it, click it -- and
## no way at all to know which of them is live. This is the answer written down where a
## label can read it.
##
## Nothing acts on it. It is a report, and if it ever starts deciding anything then the
## rules will be in two places and one of them will be wrong.

## Nothing worth pressing anything at.
const NOTHING := &""

const OPEN_THE_DOOR := &"open_the_door"
const SHUT_THE_DOOR := &"shut_the_door"
const SIT_DOWN := &"sit_down"
const STAND_UP := &"stand_up"
const READ_IT := &"read_it"

## Why the thing under the pointer will not answer. Empty when it will.
const LOCKED := &"locked"
const TAKEN := &"taken"
const IN_THE_DOORWAY := &"in_the_doorway"
const HELD_OPEN := &"held_open"

var action: StringName = NOTHING
var refusal: StringName = NOTHING

## Whether the key would reach it, and whether a click would. Both, usually; a door two
## strides off can be clicked and not pressed, and the label has to say which.
var within_reach: bool = false
var under_the_pointer: bool = false

func offers_anything() -> bool:
	return action != NOTHING
