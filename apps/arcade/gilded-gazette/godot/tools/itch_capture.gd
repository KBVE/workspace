extends Node

## Renders the two plates tools/gen-itch-art.py prints on the itch.io paper: a header
## plate and a capsule plate, both captured at 2x the final size and downsampled there.
##
## Run windowed. Headless has no rendering device, so the grab comes back black.
## [codeblock]
## godot --path godot res://scenes/tools/itch_capture.tscn
## python3 tools/gen-itch-art.py
## [/codeblock]
##
## It adds the train scene beside itself instead of changing to it, because a scene
## change frees this node and the capture with it. Autoloads are live either way,
## which is the reason this is a scene the player boots into and not a SceneTree tool.

const SCENE := "res://scenes/train/train.scn"
const OUT_DIR := "res://reports/itch"

## Streaming loads, gas lamps and the cast settling all land inside two seconds. Under
## that the plate catches an unlit carriage with no passengers in it.
const SETTLE_FRAMES := 150

## Two frames after a resize: one for the window, one for the 3D viewport behind it.
const RESIZE_FRAMES := 4

## 2x the itch sizes. The engraving pass reads the downsample as press dot gain.
const PLATES := {
	"header": Vector2i(1920, 800),
	"capsule": Vector2i(1260, 1000),
}

## Where the player is stood for the plate, when the plate wants a particular thing in
## frame. A posted notice is a metre of paper on a wall four carriages long, so the
## odds of the spawn pose catching one are what they sound like.
const POSED := {"notice": Vector2i(1280, 960), "props": Vector2i(1280, 960)}
const NOTICE_STANDOFF := 2.2


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	add_sibling.call_deferred(load(SCENE).instantiate())
	await _frames(SETTLE_FRAMES)
	for plate in PLATES:
		await _capture(plate, PLATES[plate])
	for plate in POSED:
		if plate == "props":
			_stand_at_a_prop()
		else:
			_stand_at_a_notice()
		await _frames(RESIZE_FRAMES)
		await _capture(plate, POSED[plate])
	get_tree().quit()


func _capture(plate: String, size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	get_window().size = size
	await _frames(RESIZE_FRAMES)
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, plate]
	var err := image.save_png(path)
	if err != OK:
		push_error("itch_capture: %s failed to write (%d)" % [path, err])
		return
	print("plate %s written: %dx%d" % [path, image.get_width(), image.get_height()])


## Puts the player in the aisle in front of the first posted sheet, looking at it.
func _stand_at_a_notice() -> void:
	var train: Node3D = get_parent().get_node_or_null("Train")
	var consist: Consist = train.find_child("Consist", true, false) if train != null else null
	if consist == null:
		push_error("itch_capture: no consist to find a notice in")
		return
	var posted := consist.notice_anchors()
	if posted.is_empty():
		push_error("itch_capture: nothing posted in the train")
		return
	var sheet: Vector3 = posted[0]["at"]
	var player: Node3D = train.find_child("Player", true, false)
	var camera: Camera3D = player.find_child("Camera3D", true, false) if player != null else null
	if camera == null:
		push_error("itch_capture: no player camera")
		return
	# out into the aisle and back down the car, so the sheet is across the frame
	player.global_position = sheet + Vector3(0.0, -1.3, -signf(sheet.z) * NOTICE_STANDOFF)
	camera.look_at(sheet)


## Puts the player in the aisle looking at the furnished end of the dining car, which
## is where a prop and a baked wall are in frame together.
func _stand_at_a_prop() -> void:
	var train: Node3D = get_parent().get_node_or_null("Train")
	var consist: Consist = train.find_child("Consist", true, false) if train != null else null
	if consist == null:
		return
	var props := consist.prop_anchors()
	if props.is_empty():
		push_error("itch_capture: nothing furnished in the train")
		return
	var prop: Vector3 = props[props.size() / 2]["at"]
	var player: Node3D = train.find_child("Player", true, false)
	var camera: Camera3D = player.find_child("Camera3D", true, false) if player != null else null
	if camera == null:
		return
	# out into the aisle and back along the car: standing where the prop is puts the
	# camera inside the table it was meant to be looking at
	player.global_position = Vector3(prop.x + 3.2, Consist.FLOOR_Y + 1.5, consist.global_position.z)
	camera.look_at(prop + Vector3(0.0, 0.5, 0.0))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
