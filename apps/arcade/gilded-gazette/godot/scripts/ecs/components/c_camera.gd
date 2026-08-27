extends ECSComponent
class_name CCamera

## CCamera is the head [SCameraAim] points, and the bounds it may point it within.
##
## [member pivot] is what turns, which is the boom rather than the camera: the camera
## rides wherever the arm's collision leaves room for it. Straight up and straight down
## are both excluded, because at either pole the yaw the body carries stops meaning
## anything on screen.

var pivot: Node3D
var camera: Camera3D

## Where the camera sits on its mount with nothing pushing it, restored every frame
## before the containment runs. Containment moves the camera by writing its transform,
## and that write outlives the look that caused it: shoved in against the roof at full
## pitch, the camera stayed shoved once the view came back level, and every glance
## downward walked it further into the back of the player's head.
var rest_offset := Vector3.ZERO

## A seated body is against the wall and a boom directly behind it is inside the bench,
## so the shot swings a quarter turn to put the camera over the aisle -- the only place
## in a carriage with room to film from. Which way it swings is [CSeating]'s to say.

## Shorter sitting than standing, because the aisle is narrower than the car is long.
var seated_boom_metres: float = 1.25

## The mount rides high behind a standing shoulder. Seated, that same lift puts it above
## his head looking over him, so the shot drops to meet a head that is now at 2.44
## rather than 3.0.
var seated_rest_offset := Vector3(0.12, -0.12, 0.0)
var standing_boom_metres: float = 0.95
var lowest_pitch_radians: float = -1.25
var highest_pitch_radians: float = 0.9

## The box the camera is kept inside, because the carriage it is kept inside of is
## mesh with no collision behind it. Only the floor and the two side walls carry
## bodies, so a spring arm swinging up on a downward look sails through the roof and
## films the run from outside, with the carriage's own exterior cutting the player in
## half. X is unbounded: the aisle runs the length of the train.
var interior_half_z: float = 1.5
var lowest_y: float = 0.5
var highest_y: float = 3.2

func _init(p: Node3D = null, c: Camera3D = null) -> void:
	pivot = p
	camera = c
