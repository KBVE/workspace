extends ECSComponent
class_name CHighlight

## CHighlight points at the one outline in the scene.
##
## The node belongs to the carriage, not to the entity: what is selected changes every
## time the mouse moves, and building a marker per candidate would mean building one for
## every seat in the train on the chance it gets looked at.

var view: SelectionHighlight = null
