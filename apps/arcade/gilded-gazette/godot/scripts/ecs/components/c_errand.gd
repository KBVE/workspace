extends ECSComponent
class_name CErrand

## CErrand is where a character is going, and where they are on the way there.
##
## [member at] is the truth, not the rig's transform. A passenger three carriages away
## has no rig at all, and still has to arrive at the time their timeline says they did:
## the walk happens whether or not anybody is there to watch it, and [SCastBody] places
## a rebuilt rig at whatever [member at] has reached.
##
## The player does not have one of these. He has [CInput], and what moves him is the
## keyboard through [SLocomotion]; this is the same job for everyone whose destination
## is decided rather than pressed.

## Where they are, in world space, at the height their eyes sit. The rig hangs its
## model below this, so the feet come out on the floor.
var at := Vector3.ZERO

## Where they are going. The same as [member station] for anyone standing still.
var target := Vector3.ZERO

## The spot in the room they belong to, written by [SCastBody] out of the room their
## [CLocation] names. A patrol paces about it; everybody else stands on it.
var station := Vector3.ZERO

## Which way they are turned, in the same measure [CLocomotion] uses: the rig's own
## yaw offset is applied on top, so this reads the same as the player's facing.
var facing_radians: float = 0.0

## Which way they turn when they have arrived and have nothing to walk towards. Facing
## across the aisle rather than along it, so a standing character reads as somebody at
## a window rather than somebody about to set off.
var resting_facing_radians: float = 0.0

## Down the aisle at a walk. Slower than the player, who is in a hurry and is also the
## only one aboard who knows the night is going to end badly.
var walk_metres_per_second: float = 1.05

## How fast they turn to face where they are going. A body that snapped round would
## read as a mistake in a corridor this narrow.
var turn_radians_per_second: float = 4.0

## Close enough to have arrived. Smaller than a stride, or they shuffle on the spot.
var arrive_metres: float = 0.2

## The rooms this character walks, in order, over and over. The conductor's rounds are
## the length of the train and back; an empty beat is somebody who stays where their
## timeline puts them, which is everybody else.
##
## A beat and a timeline are two different claims about where somebody is, so whoever
## has one of these owns their own [CLocation] and [SPassengerPlace] leaves them alone.
var beat: Array[StringName] = []

## Which room of the beat they are walking to now.
var beat_index: int = 0

## Seconds spent in each room before setting off for the next. A guard who arrived and
## turned straight round would read as a man who had forgotten something.
var beat_pause_seconds: float = 6.0

## Metres along the carriage the station is shifted from wherever it would otherwise
## fall. Written by whatever has an opinion about where in a room somebody belongs:
## [SGuardWatch] uses it to put the two knights on post either side of the crate rather
## than both on the seeded spot their appearance would give them.
var station_offset_metres: float = 0.0

## A place somebody else has decided this character belongs, which overrides the spot in
## the room they would otherwise be given. [SPastime] writes a bench into it; the seeded
## station is where a passenger stands when nobody has an opinion.
##
## Not folded into [member station] directly, because [SCastBody] rewrites that every
## tick out of the room they are in, and would have the last word.
var assigned: bool = false
var assigned_station := Vector3.ZERO
var assigned_facing: float = 0.0

## How far either side of [member station] a patrol walks. Zero stands still, which is
## what a passenger in a seat does between the hours their timeline moves them.
var patrol_metres: float = 0.0

## Seconds spent at each end of a patrol before turning back, so a guard on watch looks
## like one rather than a pendulum.
var patrol_pause_seconds: float = 2.5

## Counting down at the end of a patrol leg.
var pausing_seconds: float = 0.0

## Which end of the patrol is currently the target.
var patrol_outbound: bool = true

## False until [SCastBody] has worked out where in the room they stand. Nothing moves
## before then: a character walking from the origin would cross the whole train.
var stationed: bool = false
