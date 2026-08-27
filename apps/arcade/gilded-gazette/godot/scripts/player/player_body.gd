extends CharacterRig
class_name PlayerBody

## PlayerBody is the one character the player drives, dressed at build time.
##
## Everything about assembling a character lives in the base class. What is left here
## is the kit: his clothes are preloaded rather than rolled from [Wardrobe], and his
## pieces live in res://assets/player rather than the cast library, because the player
## is one fixed character built to his own texture budget. That budget is larger than
## a passenger seen down the length of a carriage needs.
##
## The camera is on a boom behind him, not in his head, so nothing here hides any part
## of him. Whoever is reading this looking for the head that gets collapsed away: that
## was the first person build, and it is gone.

func _init() -> void:
	body_model = preload("res://assets/player/models/Regular_Male_OnlyHead.glb")
	outfit_pieces = [
		preload("res://assets/player/models/hair/Hair_SimpleParted.glb"),
		preload("res://assets/player/models/outfits/Male_Noble_Body.glb"),
		preload("res://assets/player/models/outfits/Male_Noble_Arms.glb"),
		preload("res://assets/player/models/outfits/Male_Noble_Legs.glb"),
		preload("res://assets/player/models/outfits/Male_Noble_Feet.glb"),
	]
