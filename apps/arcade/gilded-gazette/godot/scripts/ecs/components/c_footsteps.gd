extends ECSComponent
class_name CFootsteps

## CFootsteps is how far a body has walked since it last put a foot down.
##
## Metres covered, not seconds: the clips run at a time scale that answers to speed, so
## a footstep on a timer keeps its rhythm while the walk speeds up -- heard immediately
## even by somebody not listening for it.

## A stride, not a step: the distance between one foot and the same foot again.
var stride_metres: float = 0.78

## Distance covered since the last one, in metres.
var since_metres: float = 0.0

## Which foot is next. A walk built out of one sample is heard as a limp.
var other_foot: bool = false

var gain: float = 1.0

## Tighter than most of the bank: eleven characters walking a train is eleven sets of
## feet in the mix, and the ones two carriages off are through a wall.
var audible_within_metres: float = 14.0
