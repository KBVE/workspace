extends ECSComponent
class_name CNoise

## CNoise is a sound a thing makes for as long as it is there: a carriage rumbles for
## the whole run, the lamps hiss for as long as there is gas in them. The opposite of a
## cue, which is fired and done with.
##
## A key into [SSound]'s bank rather than a stream, for the same reason [CAppearance]
## holds keys: the component outlives the scene and a loaded stream does not.

## Key into [constant SSound.BANK]. Empty makes no sound at all, which is what a
## carriage with its lamps out should be.
var sound: StringName = &""

## Multiplied into the bank's own level: the per-entity say, and where another system
## writes when it wants a thing turned down. [SCarriageLamps] does that with the gas.
var gain: float = 1.0

## The rate the stream is played at. Set a little off one per carriage, or ten
## identical loops phase into a slow sweep down the train that reads as a fault.
var pitch: float = 1.0

## How far it carries. Short: a rumble audible three carriages away is three
## carriages of rumble at once.
var reach_metres: float = 9.0

## Past this it is stopped rather than turned down: a stopped player is a voice given
## back to the pool and a quiet one is not.
var audible_within_metres: float = 26.0
