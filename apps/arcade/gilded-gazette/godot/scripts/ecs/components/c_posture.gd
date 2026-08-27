extends ECSComponent
class_name CPosture

## CPosture is what the body is doing, as opposed to where it is going.
##
## [CGait] answers how fast the legs cycle, which is a question that only makes sense
## with feet on the floor. This is the question above it: whether there are feet on the
## floor at all. [SPosture] decides it from [CLocomotion] and hands it to the rig, which
## owns the crossfade but none of the choosing.

const AFOOT := &"afoot"
const LAUNCHING := &"launching"
const AIRBORNE := &"airborne"
const LANDING := &"landing"
const SEATED := &"seated"

## The same body doing the same nothing, differently. A carriage of passengers all
## breathing in time is the thing anybody notices first.
const SEATED_SHIFTING := &"seated_shifting"
const SEATED_SETTLED := &"seated_settled"
const SEATED_NODDING := &"seated_nodding"

## Sat with somebody opposite. Kept out of [constant SEATED_STATES] and asked for only
## when there is company: a man gesturing at an empty bench reads as a bug.
const SEATED_TALKING := &"seated_talking"

## Getting down onto the cushion and back off it. Played once and waited out rather
## than crossfaded into, which is what stops a sit being a teleport.
const SEATING := &"seating"
const RISING := &"rising"

const SEATED_STATES: Array[StringName] = [
	SEATED, SEATED_SHIFTING, SEATED_SETTLED, SEATED_NODDING,
]

var state: StringName = AFOOT

## What the rig was last told, so a state that has not changed is not requested again.
## Asking a transition for the state it is already in restarts the crossfade, and a
## request every frame is a clip that never gets past its first frame.
var requested: StringName = &""

## Seconds of the landing clip still owed. The clip is 1.27s and a footstep is not, so
## the landing reads as a knee bend rather than a stumble.
var landing_seconds_left: float = 0.0
var landing_seconds: float = 0.32

## Whether the last frame had him off the floor, which is how a landing is noticed.
var was_airborne: bool = false
