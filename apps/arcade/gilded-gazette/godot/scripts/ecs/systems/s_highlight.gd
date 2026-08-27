extends ECSSystem
class_name SHighlight

## SHighlight puts the outline on whatever [SPointing] resolved, and takes it off when
## the pointer is over nothing.
##
## Separate from [SPointing] because deciding what is under the cursor and drawing a
## line around it are different jobs: the first is wanted by the seating and the doors
## whether or not anything is drawn, and a headless run does the first and not the
## second.

func _on_update(_delta: float) -> void:
	for entry: Dictionary in multi_view([CPointer, CHighlight]):
		var marker: SelectionHighlight = entry[&"CHighlight"].view
		if marker == null:
			continue
		_mark(entry[&"CPointer"], marker)


func _mark(pointer: CPointer, marker: SelectionHighlight) -> void:
	if pointer.notice_sheet != null:
		var sheet := _meshes_of(pointer.notice_sheet)
		if not sheet.is_empty():
			marker.show_meshes(sheet)
			return
	if pointer.seat != null:
		marker.show_seat(pointer.seat.at)
		return
	if pointer.door_leaf != null:
		var parts := _meshes_of(pointer.door_leaf)
		if not parts.is_empty():
			marker.show_meshes(parts)
			return
	marker.show_nothing()


## The leaf is a glb instance, so its meshes are somewhere under it rather than on it,
## and there is rarely only one of them.
func _meshes_of(leaf: Node3D) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if leaf is MeshInstance3D and (leaf as MeshInstance3D).mesh != null \
			and not _is_glazing(leaf as MeshInstance3D):
		found.append(leaf as MeshInstance3D)
	for child: Node in leaf.get_children():
		if child is Node3D:
			found.append_array(_meshes_of(child as Node3D))
	return found


## Whether this part is the window rather than the door. A hull around glass is a hull
## filled with glass: the pane is transparent, so nothing is drawn over the shell to
## hide its middle and the whole thing comes back as a tinted sheet.
func _is_glazing(part: MeshInstance3D) -> bool:
	for surface in range(part.mesh.get_surface_count()):
		var material := part.mesh.surface_get_material(surface) as BaseMaterial3D
		if material != null \
				and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return false
