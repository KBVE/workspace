extends SceneTree

## Copies every model [constant Wardrobe.POOL] can roll into [constant Wardrobe.KIT_DIR].
## Run headless after widening the pool, then let the editor import what lands:
## [codeblock]
## godot --headless --script tools/build_cast_kit.gd
## godot --headless --import
## [/codeblock]
##
## The pool is the whole cost. Every model here is a few hundred KB of glb plus its
## share of a texture set in the Web build, paid whether or not anybody rolls it, so
## widening [constant Wardrobe.POOL] is a size decision before it is an art one.

## Half what the player gets. He fills a third of the screen; a passenger is seen down
## the length of a carriage, past two sets of seat backs, under gas lamps.
const TEXTURE_SIZE_LIMIT := 256

func _initialize() -> void:
	var models := Wardrobe.pooled_models()
	var builder := KitBuilder.new(Wardrobe.LIBRARY_DIR, Wardrobe.KIT_DIR, TEXTURE_SIZE_LIMIT)
	builder.copy_models(models)
	print("cast kit written to %s: %d models" % [Wardrobe.KIT_DIR, models.size()])
	quit()
