extends ECSComponent
class_name CStandingIdle

## CStandingIdle is what a character on their feet and going nowhere is doing with
## themselves.
##
## [CSeatedIdle] answers the same question for the half of the cast who are sitting
## down, and it had to be answered there first because most of a night on a train is
## spent in a seat. This is the other half: the conductor between legs of his rounds,
## a knight stood over the crate for a two-hour watch, anybody waiting at a door. All
## of them played the blend space's own Idle, all of them in step, for as long as they
## were still.
##
## What they might be doing is handed in rather than rolled, because it is the one
## thing about a standing body that is not interchangeable: a guard on post folds his
## arms and a passenger looks around, and swapping the two reads as both of them being
## somebody else.

## What this one picks from, and where it is now. [constant CPosture.AFOOT] among the
## choices is the plain Idle at the middle of the gait, which is a way of standing
## rather than the absence of one.
var choices: Array[StringName] = CPosture.STANDING_STATES.duplicate()
var state: StringName = CPosture.AFOOT
var seconds_until_change: float = 0.0

## The bounds on how long one goes on for. Longer than the seated ones: a body on its
## feet is usually about to go somewhere, and changing what it does with its hands
## every five seconds reads as fidgeting rather than waiting.
var shortest_seconds: float = 7.0
var longest_seconds: float = 18.0

## Ground speed under which the body counts as stopped, in metres per second. A step
## taken to keep a beat is still walking; this is the threshold under which the legs
## have nothing to say and the rest of the body has to.
var still_metres_per_second: float = 0.05

## How long they have to have been still before any of this starts, so somebody who
## paused to let a door open does not fold their arms about it.
var settling_seconds: float = 1.2
var still_seconds: float = 0.0

## How near another standing character has to be before talking is one of the things
## this one might do, and the same rule as the seated version: near enough to be spoken
## to, or they are gesturing at a corridor.
var talking_reach_metres: float = 2.0

## Rolled per character, so two knights either side of the same crate do not shift
## their weight together.
var rng := RandomNumberGenerator.new()
