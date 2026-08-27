extends ECSComponent
class_name CSeating

## CSeating is whether a character is sat down, and what they got up from.
##
## Sitting is not a place the walk can reach: it moves the body onto the cushion, drops
## the eye, turns the shoulders square to the bench and takes the legs away. All of that
## has to be undone exactly on standing, so what was true before is kept here rather
## than recomputed from a carriage that may have moved on.

var seated: bool = false

## Walking in. A bench is reached from the aisle, and the fold is a clip authored for a
## body that is already standing in front of one: started from wherever the player
## happened to press [F], it slid him a metre sideways with his feet planted.
##
## So the walk happens first, on its own legs, and the fold begins only once he is
## standing where the clip expects him to be.
var approaching: bool = false
var approach_at := Vector3.ZERO
var approach_facing: float = 0.0

## How far out from the cushion he stands to begin. An arm's length off the edge, which
## is where somebody about to sit down actually stops.
var stand_off_metres: float = 0.42

## The walk in. Slower than a stride down the aisle: this is the last step before
## sitting, not a way of getting anywhere.
var approach_metres_per_second: float = 1.35
var approach_turn_radians_per_second: float = 7.0

## Near enough, and square enough, to start folding.
var approach_arrive_metres: float = 0.12
var approach_arrive_radians: float = 0.22

## However badly the walk goes, it ends. A bench reached around a passenger who will not
## move is still a bench somebody asked to sit on, and a walk that never arrives is a
## character stuck on their feet with the seat held.
var approach_seconds_left: float = 0.0
var approach_seconds_limit: float = 1.8

## Seconds still owed to the sit-down and the stand-up clips. While either is running
## the body is between the aisle and the cushion: it is being carried along
## [member moving_from] to [member moving_to] rather than standing at either.
##
## Set from the clip's own length, so the fold finishes exactly as the body arrives
## and the last frame of the sit is the first frame of the sitting.
var settling_seconds_left: float = 0.0
var rising_seconds_left: float = 0.0
var moving_from := Vector3.ZERO
var moving_to := Vector3.ZERO
var facing_from: float = 0.0
var facing_to: float = 0.0
var eye_from: float = 0.0
var eye_to: float = 0.0

## What the clip that is carrying them runs for, whole. The seconds left are counted
## against this to get how far along the move is.
var moving_seconds: float = 0.0

## Where the eye sat and which way the body faced before it took a seat.
var stood_eye_height_metres: float = 0.0
var stood_facing_radians: float = 0.0
var stood_at := Vector3.ZERO

## How far away a seat can be and still be sat in. An arm's length: far enough that
## standing beside a bench is enough, near enough that it is unambiguous which one.
var reach_metres: float = 1.4

## How far above the cushion the eye ends up. A seated adult is roughly this much taller
## than what they are sitting on.
var seated_eye_above_cushion_metres: float = 0.72

## How far forward of the anchor to park him. The sitting clip is authored with the
## pelvis a third of a metre behind the rig's own origin, so dropping the root on the
## cushion puts his backside inside the seat back and his thighs come out of the
## upholstery. Measured off the clip: hips at -6.931 for a root at -6.600.
var seated_forward_offset_metres: float = 0.33

## The seat currently occupied, so standing releases the one that was taken rather than
## whichever is nearest by then.
var seat: CSeat = null

## How far the camera swings to get off the bench and over the aisle, set on sitting
## down. Standing it is nothing: the shot rides behind the shoulder. Seated there is a
## wall where behind used to be.
var camera_yaw_radians: float = 0.0


## Between the aisle and the cushion, in either direction. Neither standing nor sitting:
## the walk is off, the seat is held, and nothing may interrupt it.
func moving() -> bool:
	return settling_seconds_left > 0.0 or rising_seconds_left > 0.0


## Taking a seat or leaving one, walk included. What everything outside [SSeating] wants
## to know: the seat is spoken for and the player is not driving.
func busy() -> bool:
	return approaching or moving()


## How far along the sit-down or the stand-up, nought at the aisle and one at the seat.
func moved_fraction() -> float:
	if moving_seconds <= 0.0:
		return 1.0
	var left := maxf(settling_seconds_left, rising_seconds_left)
	return clampf(1.0 - left / moving_seconds, 0.0, 1.0)


## The same, eased. The clip does not fold at a constant rate and neither should the
## body under it: a linear slide onto the cushion arrives while the knees are still
## bending, and the last frames read as the seat pulling him in.
func eased_fraction() -> float:
	var along := moved_fraction()
	return along * along * (3.0 - 2.0 * along)


## How seated the shot is, which is not how seated the body is: the camera swings off
## the bench and the boom draws in across the sit-down rather than on the frame it was
## asked for.
func seated_weight() -> float:
	if settling_seconds_left > 0.0:
		return moved_fraction()
	if rising_seconds_left > 0.0:
		return 1.0 - moved_fraction()
	return 1.0 if seated else 0.0
