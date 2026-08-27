extends SceneTree

## Copies what the player is built from out of the shared Quaternius library into
## [constant KIT_DIR] and bakes the clips it plays. Run headless, then --import.
##
## The copying is [KitBuilder], shared with tools/build_cast_kit.gd. What is here is
## the list: one body, one outfit, and the clips that body walks on.

const LIBRARY_DIR := "res://assets/characters/quaternius_ubc"
const KIT_DIR := "res://assets/player"

## Head and neck only: a full body under a full outfit is two skinned surfaces a
## millimetre apart, and the skin wins often enough to look like a hole in the coat.
## The outfit's Arms piece reaches the fingertips, so nothing is lost with the body.
const BODY := "models/Regular_Male_OnlyHead.glb"

const OUTFIT := [
	"models/hair/Hair_SimpleParted.glb",
	"models/outfits/Male_Noble_Body.glb",
	"models/outfits/Male_Noble_Arms.glb",
	"models/outfits/Male_Noble_Legs.glb",
	"models/outfits/Male_Noble_Feet.glb",
]

## Godot's use_name_suffixes strips the _Loop suffix on import and sets the loop mode
## from it, so these are the glTF names minus that suffix.
const CLIPS_BY_SOURCE := {
	"animations/UAL1.glb": [
		"Idle", "Jump_Start", "Jump", "Jump_Land",
		"Sitting_Idle", "Sitting_Idle02", "Sitting_Idle03", "Sitting_Nodding",
		"Sitting_Talking", "Sitting_Enter", "Sitting_Exit",
	],
	"animations/UAL2.glb": [
		"Walk_Fwd", "Walk_Bwd", "Walk_L", "Walk_R",
		"Walk_Fwd_L", "Walk_Fwd_R", "Walk_Bwd_L", "Walk_Bwd_R",
	],
}

const ANIMATION_LIBRARY := "animations/player_animations.res"

## At 1024 the same build is 8MB larger, for texture no one gets close enough to see.
const TEXTURE_SIZE_LIMIT := 512

func _initialize() -> void:
	var builder := KitBuilder.new(LIBRARY_DIR, KIT_DIR, TEXTURE_SIZE_LIMIT)
	builder.copy_models(PackedStringArray([BODY] + OUTFIT))
	builder.build_animation_library(CLIPS_BY_SOURCE, ANIMATION_LIBRARY)
	print("player kit written to ", KIT_DIR)
	quit()
