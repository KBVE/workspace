extends ECSComponent
class_name CNoise

## CNoise is a sound a thing makes for as long as it is there.
##
## The opposite of a cue. A door bangs once and is done with; a carriage rumbles for
## the whole run, and the lamps hiss for as long as there is gas in them. Those cannot
## be fired -- they have to be started, kept, moved with the thing making them, and
## stopped when it goes out of view.
##
## What it is, is a key into [SSound]'s bank rather than a stream, for the same reason
## [CAppearance] holds keys rather than resources: the component outlives the scene and
## a loaded stream does not.

## Key into [constant SSound.BANK]. Empty makes no sound at all, which is what a
## carriage with its lamps out should be.
var sound: StringName = &""

## Multiplied into the bank's own level. This is the per-entity say -- a saloon is
## quieter than the guard's van over the same bogies -- and the place another system
## writes when it wants a thing turned down. [SCarriageLamps] does exactly that with
## the gas.
var gain: float = 1.0

## Semitone-free: the rate the stream is played at. Set a little off one per carriage
## so ten identical loops do not phase against each other, which is heard as a slow
## sweep down the train and reads as a fault in the audio rather than as ten carriages.
var pitch: float = 1.0

## How far it carries. Short by default: everything here is a thing in a room, and a
## rumble audible three carriages away is three carriages of rumble at once.
var reach_metres: float = 9.0

## Where the player has to be for this to be worth playing at all. Everything past it
## is stopped rather than turned down, because a stopped player is a voice given back
## to the pool and a quiet one is not.
var audible_within_metres: float = 26.0
