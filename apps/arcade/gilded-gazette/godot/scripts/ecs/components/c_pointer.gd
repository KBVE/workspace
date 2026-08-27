extends ECSComponent
class_name CPointer

## CPointer is whatever the mouse is currently over, and whether it was just clicked.
##
## The pointer was never captured -- the evidence in this game is looked at and picked
## up -- so it is the natural way to say which door, out of two at opposite ends of a
## carriage, or which seat, out of a row of them. Standing near a thing answers a
## different question from pointing at it, and both are worth having: [SSeating] takes
## the nearest bench when [F] is pressed, and takes the one under the cursor when it is
## clicked.

## Where the ray last landed, and whether it landed on anything at all.
var at := Vector3.ZERO
var has_target: bool = false

## What the thing under the cursor turned out to be. At most one is set.
var seat: CSeat = null
var door: CDoor = null
var door_leaf: Node3D = null
var notice: CNotice = null
var notice_sheet: Node3D = null

## True on the frame the pointer was pressed. An edge like the rest of the intents, so
## holding the button on a door does not swing it open and shut.
var clicked: bool = false

## How far from the player a click is allowed to reach. Further than [F], because
## pointing at a thing is unambiguous in a way that standing near it is not, but not so
## far that a door two carriages down answers.
var reach_metres: float = 4.5

## How near the ray has to land to count as having hit one. The seats are a single
## trimesh per carriage and the ray knows nothing about which cushion it struck, so the
## nearest anchor within this claims it.
## Generous, because nearest wins: the cushions in a back to back pair are 0.9 apart and
## the gap between pairs is wider than either, so what matters is that a click anywhere
## on a bench finds the seat it is nearest rather than falling through the gaps.
var seat_snap_metres: float = 1.2
var door_snap_metres: float = 1.6

## Tighter than either, because a poster is a sheet on a wall a metre from the seat
## backs and the bench behind it. Pointing at a notice is aiming at it; standing near
## the wall is not, which is why [SNotice] has no reach of its own.
var notice_snap_metres: float = 0.6
