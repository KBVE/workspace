extends ECSSystem
class_name SPointing

## SPointing turns the mouse into whichever entity is under it.
##
## The ray is cast through the world's own viewport rather than the window's: the game
## is drawn into a [SubViewport] that the render budget resizes underneath it, so window
## coordinates and camera coordinates are not the same pixels and drift apart the moment
## the frame rate does.

func _on_update(_delta: float) -> void:
	for entry: Dictionary in multi_view([CCamera, CPointer, ECSViewComponent]):
		var eye: CCamera = entry[&"CCamera"]
		var body: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if eye.camera == null or body == null:
			continue
		_look(eye.camera, entry[&"CPointer"], body)


func _look(camera: Camera3D, pointer: CPointer, body: Node3D) -> void:
	pointer.has_target = false
	pointer.seat = null
	pointer.door = null
	pointer.door_leaf = null
	pointer.notice = null
	pointer.notice_sheet = null

	var viewport := camera.get_viewport()
	var world := camera.get_world_3d()
	if viewport == null or world == null:
		return
	var screen := viewport.get_mouse_position()
	var from := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(from,
		from + camera.project_ray_normal(screen) * pointer.reach_metres * 2.0)
	query.exclude = [body.get_rid()] if body is CollisionObject3D else []
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var at: Vector3 = hit["position"]
	if body.global_position.distance_to(at) > pointer.reach_metres:
		return
	pointer.at = at
	_claim(pointer, at)


## Whichever anchor is nearest where the ray landed. Doors beat seats, because a door in
## the end wall of a carriage is a metre from the last bench and the one being pointed
## at is nearly always the one you cannot walk past. Notices beat both, on the same
## argument and harder: they hang on the wall above the benches, and the ray that
## reaches one has already passed everything else in the carriage.
func _claim(pointer: CPointer, at: Vector3) -> void:
	var nearest := pointer.seat_snap_metres
	for seat: CSeat in view(&"CSeat"):
		# flat, because a ray that struck the seat back lands a good half metre above
		# the cushion and that height is not a reason to miss the seat it belongs to
		var away := Vector2(at.x - seat.at.x, at.z - seat.at.z).length()
		if away < nearest:
			nearest = away
			pointer.seat = seat
			pointer.has_target = true

	nearest = pointer.door_snap_metres
	for entry: Dictionary in multi_view([CDoor, ECSViewComponent]):
		var leaf: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if leaf == null or not leaf.is_visible_in_tree():
			continue
		var away := at.distance_to(leaf.global_position)
		if away < nearest:
			nearest = away
			pointer.door = entry[&"CDoor"]
			pointer.door_leaf = leaf
			pointer.seat = null
			pointer.has_target = true

	nearest = pointer.notice_snap_metres
	for entry: Dictionary in multi_view([CNotice, ECSViewComponent]):
		var sheet: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if sheet == null or not sheet.is_visible_in_tree():
			continue
		var away := at.distance_to(entry[&"CNotice"].at)
		if away < nearest:
			nearest = away
			pointer.notice = entry[&"CNotice"]
			pointer.notice_sheet = sheet
			pointer.seat = null
			pointer.door = null
			pointer.door_leaf = null
			pointer.has_target = true
