extends ECSComponent
class_name CFootsteps

## CFootsteps is how far a body has walked since it last put a foot down.
##
## Measured in metres covered rather than timed off the animation. The clips are played
## through a blend space at a time scale that answers to speed, so the frame a foot
## actually lands on is not a thing the rig can be asked for -- and a footstep on a
## timer is a footstep that keeps its rhythm while the walk speeds up, which is heard
## immediately even by somebody not listening for it.

## How far apart the feet land. A stride, not a step: the two are alternated, so this
## is the distance between one foot and the same foot again.
var stride_metres: float = 0.78

## Distance covered since the last one, in metres.
var since_metres: float = 0.0

## Which foot is next. The two samples differ by a note or so, because a walk built out
## of one sample is heard as a limp long before it is heard as a footstep.
var other_foot: bool = false

var gain: float = 1.0

## How far away a footstep is worth playing. Tighter than most of the bank: eleven
## characters walking a train would otherwise be eleven sets of feet in the mix, and
## the ones two carriages off are through a wall.
var audible_within_metres: float = 14.0
