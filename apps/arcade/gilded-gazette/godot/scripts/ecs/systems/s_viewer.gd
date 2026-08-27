extends ECSSystem
class_name SViewer

## SViewer projects the tracked camera's transform onto [CViewer].
## ECSSystem, never ECSParallel, because this is a Node3D global transform, main thread behavior.

func _on_update(_delta: float) -> void:
	for entry: Dictionary in multi_view([ECSViewComponent, CViewer]):
		var tracked: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if tracked == null:
			continue
		var viewer: CViewer = entry[&"CViewer"]
		viewer.world_x = tracked.global_position.x
		viewer.world_yaw = tracked.global_rotation.y
