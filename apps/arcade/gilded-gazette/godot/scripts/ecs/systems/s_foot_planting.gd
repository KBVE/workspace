extends ECSSystem
class_name SFootPlanting

## SFootPlanting turns [CPosture] into how hard the feet are held down.
##
## The rig owns the solving and knows nothing about jumping; this owns the when, and
## knows nothing about knees.

func _on_update(delta: float) -> void:
	for entry: Dictionary in multi_view([CPosture, CFootPlanting, CCharacterRig]):
		var rig: CharacterRig = entry[&"CCharacterRig"].rig
		if rig == null:
			continue
		var planting: CFootPlanting = entry[&"CFootPlanting"]
		var posture: CPosture = entry[&"CPosture"]
		var wanted := 0.0 if posture.state in [CPosture.LAUNCHING, CPosture.AIRBORNE] \
			else 1.0
		planting.weight = move_toward(planting.weight, wanted,
			delta / maxf(planting.ease_seconds, 0.0001))
		rig.set_foot_planting(planting.weight)
