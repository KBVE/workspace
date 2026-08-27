extends ECSComponent
class_name CCharacterRig

## CCharacterRig points at the skinned body an entity is seen as. On the player that
## is what [CLocomotion] is doing; on a passenger it is null until [SCastBody] builds
## one, and null again once their carriage is out of view.
##
## Separate from [ECSViewComponent], which on this entity is already the
## [CharacterBody3D] the physics moves.

var rig: CharacterRig

func _init(r: CharacterRig = null) -> void:
	rig = r


## The rig, or null if the node has gone. Everything that reads one goes through here.
##
## The component outlives the scene: the cast are spawned by [Session] and live across
## a train being torn down and built again, while their rigs are children of the train
## and do not. Between the two the reference is left pointing at a freed node, and a
## typed read of that is an error rather than a null.
## Tested with [method @GlobalScope.is_instance_valid] and nothing else. A freed node
## compares equal to null while the variable still holds an invalid reference, so
## guarding on `rig != null` skips the clearing and hands the invalid one straight back.
func live() -> CharacterRig:
	if not is_instance_valid(rig):
		rig = null
	return rig
