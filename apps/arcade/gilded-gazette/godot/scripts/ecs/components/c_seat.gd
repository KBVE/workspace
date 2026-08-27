extends ECSComponent
class_name CSeat

## CSeat is one place on a bench, and whoever is in it.
##
## Seats are entities rather than geometry the sitter raycasts for, because a seat is
## not just a surface: it can be taken. A passenger settling into a carriage and the
## player pressing use are answering the same question -- is this one free -- and the
## answer has to be the same one, held in one place.

## Where the body goes and which way it faces once it is in, in world space.
var at := Vector3.ZERO
var facing_radians: float = 0.0

## Which carriage it belongs to, so a cast body can look for a seat near itself rather
## than the nearest one down the length of the train.
var carriage_index: int = 0

## The [CSeating] of whoever is in it, or null. A reference rather than a flag: standing
## up has to release the seat it took, not the one that happens to be nearest now.
var taken_by: CSeating = null

func free_to_take() -> bool:
	return taken_by == null
