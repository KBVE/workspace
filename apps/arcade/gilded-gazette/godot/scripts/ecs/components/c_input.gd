extends ECSComponent
class_name CInput

## CInput is one frame of movement and aim intent, already in movement units.
##
## A held key is a rate and a mouse or a drag is a distance, so [SPlayerControl]
## resolves both into the same unit before anything downstream sees them.

var walk_units: float = 0.0
var strafe_units: float = 0.0
var turn_units: float = 0.0
var pitch_units: float = 0.0


## True while the player is actively aiming the view, by whatever means: the right
## button on a pointer, a drag or a look stick on a touchscreen. Kept apart from the
## button that raises it so the [Crosshair] and anything else that wants to know a look
## is underway does not have to care which device asked.
var holding_look: bool = false

## True while the player is asking for the view back. A look holds where it was left,
## because taking it away the moment they let go of the button reads as the camera
## fighting them; this is the way back, and it is theirs to ask for.
var recentring_view: bool = false


## True on the frame the player asked to leave the ground. An edge rather than a level,
## because holding the key down is not a request to keep jumping.
var jump_requested: bool = false


## True on the frame the player asked to use whatever they are standing next to.
## An edge for the same reason the jump is: holding [F] against a door is one
## request, not a door that flaps while the key is down.
var interact_requested: bool = false


## True on the frame the player asked for the other thing. Reach is crowded in a
## carriage -- the last bench in a row stands within arm's length of the end door -- and
## with one key the nearer answer always wins and the further one is unreachable. This
## is how you say "not that one".
var secondary_requested: bool = false

## True on the frame the pointer was clicked on something. Pointing is the unambiguous
## way to choose between things standing close together, so it carries no primary or
## secondary: what was clicked is what was meant.
var pointer_clicked: bool = false
