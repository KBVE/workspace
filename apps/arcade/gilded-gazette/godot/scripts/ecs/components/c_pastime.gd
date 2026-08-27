extends ECSComponent
class_name CPastime

## CPastime is what a passenger does with the hours their timeline does not account for.
##
## The timeline says which room they are in at a given minute and nothing else, which
## left a carriage of people standing exactly where they were put, facing the seats,
## for as long as the hour lasted. What fills the gap is this: cross the room once or
## twice, find a bench, sit down until the night moves you on.
##
## A behaviour, kept as data like everything else. What it is doing now is a state on a
## component and the deciding is [SPastime]'s, so a passenger who behaves differently is
## a different set of numbers rather than a different kind of thing.

## Standing where they were put, with time left to run before anything happens.
const ARRIVING := &"arriving"

## Crossing the room to somewhere else in it, for no reason anybody watching could name,
## which is what makes it read as a person rather than a schedule.
const MILLING := &"milling"

## Walking at a particular bench, which is held for them from the moment they set off.
const TAKING_A_SEAT := &"taking_a_seat"

## In it.
const SEATED := &"seated"

var state: StringName = ARRIVING

## Seconds still to stand about before doing the next thing.
var seconds_until_restless: float = 0.0

## The bounds on that. Wide, because a carriage where everybody moves at once reads as
## a shift change.
var shortest_wait_seconds: float = 6.0
var longest_wait_seconds: float = 22.0

## How many times they will wander the room before looking for somewhere to sit. Zero
## goes straight for a bench, which is what somebody who has been on their feet since
## Calais does.
var wanders_before_settling: int = 1
var wandered: int = 0

## The room this was all decided in. When the timeline moves them somewhere else, the
## pastime starts again: they are on their feet and walking, whatever they were doing.
var room: StringName = &""

## Rolled per character, so a carriage of passengers do not all get restless together.
var rng := RandomNumberGenerator.new()
