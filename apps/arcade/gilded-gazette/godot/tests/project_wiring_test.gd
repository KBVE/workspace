# GdUnitTestSuite
extends GdUnitTestSuite

## &regression -> scripts have moved between folders several times (autoload/,
##                core/, ecs/core/, world/). Every move is a silent break until
##                something runs the scene: project.godot stores autoloads by
##                path, and the train scene stores its scripts by path too.

func test_every_autoload_script_still_exists() -> void:
	for setting: String in ProjectSettings.get_property_list().map(
			func(p: Dictionary) -> String: return p["name"]):
		if not setting.begins_with("autoload/"):
			continue
		var path := str(ProjectSettings.get_setting(setting)).trim_prefix("*")
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"%s points at %s, which no longer exists" % [setting, path]
		).is_true()


func test_the_main_scene_and_the_train_scene_both_load() -> void:
	for path: String in [
		str(ProjectSettings.get_setting("application/run/main_scene")),
		"res://scenes/train/train.scn",
	]:
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"%s is missing" % path
		).is_true()


func test_tools_and_tests_are_excluded_from_every_export_preset() -> void:
	var presets := ConfigFile.new()
	assert_int(presets.load("res://export_presets.cfg")).is_equal(OK)
	for section: String in presets.get_sections():
		if not presets.has_section_key(section, "exclude_filter"):
			continue
		var filter := str(presets.get_value(section, "exclude_filter"))
		for excluded: String in ["tools/*", "tests/*"]:
			assert_str(filter).override_failure_message(
				"[%s] would ship %s" % [section, excluded]
			).contains(excluded)


## The character art is 260MB of source that imports to 272MB, and the web export
## ships every resource in the project rather than only the reachable ones. Left
## in, it takes index.pck from 22MB to 278MB, which is not a download anyone on a
## phone completes.
##
## So the web preset excludes it while nothing references it. The moment a scene
## does, that exclusion stops being free and starts being a scene that loads in
## the editor and breaks in the browser -- which is exactly the failure nobody
## finds until it is on itch. This is the test that finds it instead.
##
## Fixing it means shipping a subset, not deleting the filter: pick the models the
## run actually needs and narrow the pattern to the rest.
func test_the_web_preset_only_drops_characters_while_nothing_uses_them() -> void:
	var referenced := _scenes_referencing("res://assets/characters/")
	if referenced.is_empty():
		return
	var presets := ConfigFile.new()
	assert_int(presets.load("res://export_presets.cfg")).is_equal(OK)
	for section: String in presets.get_sections():
		if not presets.has_section_key(section, "exclude_filter"):
			continue
		if str(presets.get_value(section, "name")) != "Web":
			continue
		assert_str(str(presets.get_value(section, "exclude_filter"))) \
			.override_failure_message(
				"%s reference character art the Web preset excludes, so they load in "
				% ", ".join(referenced)
				+ "the editor and come up missing in the browser. Narrow "
				+ "assets/characters/* to the models the run does not use."
			).not_contains("assets/characters/*")


## Text scan rather than loading each scene: a .scn that references a stripped
## resource is precisely what we are hunting, and loading it here would either
## fail or quietly succeed on the editor's copy.
func _scenes_referencing(prefix: String) -> Array[String]:
	var hits: Array[String] = []
	for path: String in _files_under("res://scenes", [".tscn", ".scn"]):
		var body := FileAccess.get_file_as_string(path)
		if body.contains(prefix):
			hits.append(path)
	return hits


func _files_under(root: String, suffixes: Array) -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_directories_at(root):
		out.append_array(_files_under(root.path_join(name), suffixes))
	for name: String in DirAccess.get_files_at(root):
		for suffix: String in suffixes:
			if name.ends_with(suffix):
				out.append(root.path_join(name))
	return out
