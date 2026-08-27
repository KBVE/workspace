extends ECSComponent
class_name CGait

## CGait is how a character's legs answer the speed [CLocomotion] reports.
##
## The rig is a view: it owns a skeleton, a blend space and nine clips, and it can be
## told where in that space to stand. Deciding where that is belongs here, so a
## passenger who walks differently is a different component rather than a different
## node, and so the smoothing survives a rig being thrown away and rebuilt when its
## carriage comes back into view.

## Ground speed the walk clips were animated at, before the rig is scaled up. Sets how
## fast the legs cycle for a given speed.
var walk_clip_metres_per_second: float = 1.4

## Seconds for the blend to catch up, so a knocked-back step does not snap the legs
## between clips.
var blend_seconds: float = 0.12

var time_scale_limits := Vector2(0.6, 1.8)

## Where in the blend space the legs currently are, forward in y and to the character's
## own right in x. Carried between frames because it chases the wanted position rather
## than jumping to it.
var blend := Vector2.ZERO
