extends ECSComponent
class_name CWatch

## CWatch is a knight's duty on the Order's watch, and how long they have held it.
##
## Four of them and three jobs: two stand over the crate, one walks the train, and one
## is off the watch entirely. The fourth is the whole point. A rota with no slack has
## every guard on duty all night, which is not a watch, it is a tableau.
##
## The duty is written here and read by [SGuardWatch], which turns it into a [CErrand].
## Nothing else knows a knight from a passenger.

## Stood over the cargo. Two of these at any hour.
const POST := &"post"

## Walking the length of the train and back, which is what makes the Order visible to
## anybody aboard who has not been down to the guard's van.
const PATROL := &"patrol"

## Off the watch, in the van, waiting to take the next duty that comes free.
const RELIEF := &"relief"

var duty: StringName = POST

## Which of the posts at the crate this one stands, so two guards on post do not stand
## in the same place. Meaningless on any other duty.
var post_index: int = 0

## The clock reading when this duty was taken, in minutes past midnight. Rotations are
## measured against the world's own clock rather than seconds of play, so a watch is
## the same length however fast the night is running.
var took_duty_at_minutes: int = -1
