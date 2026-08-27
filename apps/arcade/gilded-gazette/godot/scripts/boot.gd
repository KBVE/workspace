extends Node

@export_file("*.scn", "*.tscn") var first_scene: String = "res://scenes/train/train.scn"

func _ready() -> void:
	if first_scene.is_empty():
		push_error("Boot: first_scene is not set.")
		return
	GameBridge.load_scene_async_streaming(first_scene)
