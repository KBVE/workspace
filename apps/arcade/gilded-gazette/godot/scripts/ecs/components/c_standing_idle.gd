extends ECSComponent
class_name CStandingIdle

## CStandingIdle is what a character on their feet and going nowhere is doing with
## themselves. The mirror of [CSeatedIdle], for the conductor between legs of his
## rounds, a knight on a two-hour watch, anybody waiting at a door -- all of whom
## played the blend space's own Idle, in step with each other, for as long as they
## were still.
##
## What they might be doing is handed in rather than rolled: it is the one thing about
## a standing body that is not interchangeable, and giving the passengers the escort's
## list reads as both of them being somebody else.
var choices: Array[StringName] = CPosture.STANDING_STATES.duplicate()
var state: StringName = CPosture.AFOOT
var seconds_until_change: float = 0.0

## Longer than the seated bounds: a body on its feet is usually about to go somewhere,
## and changing what it does with its hands every five seconds reads as fidgeting.
var shortest_seconds: float = 7.0
var longest_seconds: float = 18.0

## Ground speed under which the body counts as stopped: the threshold below which the
## legs have nothing to say and the rest of the body has to.
var still_metres_per_second: float = 0.05

## How long they have to have been still before any of this starts, so somebody who
## paused to let a door open does not fold their arms about it.
var settling_seconds: float = 1.2
var still_seconds: float = 0.0

## Near enough to be spoken to, or they are gesturing at a corridor.
var talking_reach_metres: float = 2.0

## Rolled per character, so two knights either side of the same crate do not shift
## their weight together.
var rng := RandomNumberGenerator.new()
