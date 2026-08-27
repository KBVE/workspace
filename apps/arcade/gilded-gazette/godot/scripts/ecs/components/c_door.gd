extends ECSComponent
class_name CDoor

## CDoor is one end-wall door: whether it is open, and how far through the swing it
## currently is.
##
## The leaf turns on its hinge edge, which the glTF puts at the origin, so the whole
## animation is one rotation about the up axis and nothing has to correct for the
## door's own width.

## Radians the leaf swings when open. Ninety degrees puts it flat against the end
## wall, which is where it stops being in the doorway.
var open_radians: float = PI * 0.5

## Which way it swings, so a door hinged on the left of one end wall and the right
## of the other both open away from the player rather than into them.
var swing_sign: float = 1.0

## Seconds from shut to fully open. Fast enough not to be a wait, slow enough that
## the swing reads as a door rather than a teleport.
var seconds_to_swing: float = 0.45

var is_open: bool = false

## Zero shut, one fully open. Kept apart from [member is_open] because the leaf is
## somewhere between the two for most of the time anybody is looking at it.
var swing: float = 0.0

## How close the player has to stand for [F] to reach it, in metres.
var reach_metres: float = 2.2

## How many characters are standing close enough to be walking through it. Kept apart
## from [member is_open], which is the player's own doing: a door the conductor is
## holding open should not come back shut because the player pressed [F] as he passed,
## and should not stay open once he has gone through because they did.
##
## Written every tick by [SDoorTraffic]. Nothing accumulates, so a character freed
## mid-stride does not leave a door propped open for the rest of the run.
var held_open_by: int = 0

## Set by whatever authors the run. A locked door still reports the attempt, which
## is what lets a line of dialogue or a journal entry answer it.
var is_locked: bool = false
