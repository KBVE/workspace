extends ECSComponent
class_name CSeatedIdle

## CSeatedIdle is which of the sitting clips a seated character is currently in.
##
## Sitting still is the one thing most of this cast does for most of the run, and one
## looping clip across a carriage of them reads as a row of clockwork. The clips are all
## the same pose doing nothing differently -- a shift of weight, a settle, a nod -- so
## they cut between each other without anybody standing up.

## Where it is now, and how long until it moves on.
var state: StringName = CPosture.SEATED
var seconds_until_change: float = 0.0

## The bounds on how long one goes on for. Long enough that a change is not a twitch,
## short enough that a passenger sat through a whole scene is not a statue.
var shortest_seconds: float = 5.0
var longest_seconds: float = 14.0

## How near another seated character has to be before talking is one of the things this
## one might do. A bench pair faces across a table's width; anything past that is a man
## gesturing at nobody.
var talking_reach_metres: float = 1.8

## Rolled per character so two passengers on the same bench do not shift their weight
## in unison, which is worse than both of them holding still.
var rng := RandomNumberGenerator.new()
