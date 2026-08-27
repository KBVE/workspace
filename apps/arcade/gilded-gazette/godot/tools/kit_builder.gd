extends RefCounted
class_name KitBuilder

## Copies models and their textures out of the shared Quaternius library into a kit
## directory the export filter can reach, and bakes animation clips into a library.
##
## Two scripts drive it. tools/build_player_kit.gd ships the one character the player
## drives at a texture budget worth spending on the model filling a third of the
## screen; tools/build_cast_kit.gd ships the pool passengers are rolled out of, which
## is far more models at a fraction of the texture.
##
## It exists because Godot applies the export filter's exclude after its include, so
## the Web preset's exclusion of the 40MB res://assets/characters cannot be named back
## out of. Shipping a body means that body living where the filter does not reach.

const GLTF_HEADER_BYTES := 12
const GLTF_JSON_CHUNK := 0x4E4F534A
const COMPRESS_MODE_VRAM_COMPRESSED := 2
const DETECT_3D_LEAVE_ALONE := 0
const NORMAL_MAP_ENABLED := 1
const NORMAL_MAP_DISABLED := 0
const NORMAL_MAP_SUFFIX := "_Normal"

var library_dir: String
var kit_dir: String
var texture_size_limit: int

func _init(from_library: String, into_kit: String, texture_limit: int) -> void:
	library_dir = from_library
	kit_dir = into_kit
	texture_size_limit = texture_limit


## glTF keeps its textures as sibling files rather than embedding them, so a model is
## only copied once the URIs it names have been.
func copy_models(paths: PackedStringArray) -> void:
	for path: String in paths:
		for texture_path: String in _textures_of("%s/%s" % [library_dir, path]):
			_copy_texture(texture_path)
		_copy(path)


func _textures_of(glb_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var glb := FileAccess.open(glb_path, FileAccess.READ)
	if glb == null:
		push_error("cannot read %s" % glb_path)
		return out
	glb.seek(GLTF_HEADER_BYTES)
	var json := ""
	while glb.get_position() < glb.get_length():
		var length := glb.get_32()
		var kind := glb.get_32()
		if kind == GLTF_JSON_CHUNK:
			json = glb.get_buffer(length).get_string_from_utf8()
			break
		glb.seek(glb.get_position() + length)
	var parsed: Dictionary = JSON.parse_string(json)
	for image: Dictionary in parsed.get("images", []):
		var uri: String = image.get("uri", "")
		if uri != "":
			out.append(glb_path.get_base_dir().path_join(uri).simplify_path()
				.trim_prefix(library_dir + "/"))
	return out


## The import settings are the copy's own, so the shared library keeps whatever else
## needs it and the kit gets what a build needs.
func _copy_texture(path: String) -> void:
	_copy(path)
	var settings := ConfigFile.new()
	settings.load("%s/%s.import" % [library_dir, path])
	settings.set_value("params", "compress/mode", COMPRESS_MODE_VRAM_COMPRESSED)
	settings.set_value("params", "process/size_limit", texture_size_limit)
	settings.set_value("params", "mipmaps/generate", true)
	settings.set_value("params", "detect_3d/compress_to", DETECT_3D_LEAVE_ALONE)
	settings.set_value("params", "compress/normal_map",
		NORMAL_MAP_ENABLED if path.get_file().get_basename().ends_with(NORMAL_MAP_SUFFIX)
		else NORMAL_MAP_DISABLED)
	_write_import(path, settings)


func _copy(path: String) -> void:
	var to := "%s/%s" % [kit_dir, path]
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var copied := DirAccess.copy_absolute("%s/%s" % [library_dir, path], to)
	if copied != OK:
		push_error("could not copy %s: %d" % [path, copied])
		return
	if not FileAccess.file_exists("%s/%s.import" % [library_dir, path]):
		return
	var settings := ConfigFile.new()
	settings.load("%s/%s.import" % [library_dir, path])
	_write_import(path, settings)


## Only [code]params[/code] survives: [code]remap[/code] carries the uid of the file
## this was copied from, and two resources on one uid is a fight Godot settles by
## dropping one. Fresh ones are written on the next import.
func _write_import(path: String, settings: ConfigFile) -> void:
	settings.erase_section("remap")
	settings.erase_section("deps")
	settings.save("%s/%s.import" % [kit_dir, path])


## Bakes the named clips out of the animation glbs into one library resource.
##
## Godot's use_name_suffixes strips the _Loop suffix on import and sets the loop mode
## from it, so the names asked for are the glTF ones minus that suffix.
func build_animation_library(clips_by_source: Dictionary, into: String) -> void:
	var library := AnimationLibrary.new()
	for source: String in clips_by_source:
		var scene: Node = (load("%s/%s" % [library_dir, source]) as PackedScene).instantiate()
		var player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
		for clip_name: String in clips_by_source[source]:
			if not player.has_animation(clip_name):
				push_error("%s has no animation %s" % [source, clip_name])
				continue
			library.add_animation(clip_name, player.get_animation(clip_name).duplicate(true))
		scene.free()
	DirAccess.make_dir_recursive_absolute("%s/%s" % [kit_dir, into.get_base_dir()])
	var saved := ResourceSaver.save(library, "%s/%s" % [kit_dir, into],
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
	if saved != OK:
		push_error("could not save the animation library: %d" % saved)
