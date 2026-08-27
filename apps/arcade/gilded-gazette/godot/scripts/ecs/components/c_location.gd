extends ECSComponent
class_name CLocation

## CLocation holds one locations id, authored under shared/data/locations. A
## carriage carries the room it stands in for; a passenger or the player carries
## the room they are currently in. Same component, so "who is in here with me"
## is one query rather than a translation.

var location_id: StringName = &""
