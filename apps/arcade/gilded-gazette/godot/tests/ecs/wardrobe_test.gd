# GdUnitTestSuite
extends GdUnitTestSuite


## The catalogue is written by hand and the pool is a separate list, so the way this
## breaks is an authored passenger wearing something the kit never shipped. It would
## show up as an invisible character, at runtime, in a carriage nobody walks into.
func test_every_passenger_wears_something_the_kit_shipped() -> void:
	for passenger: Dictionary in GameContent.passengers():
		var id := StringName(passenger.get("id", ""))
		var appearance := Wardrobe.appearance_of(id)
		assert_bool(ResourceLoader.exists(Wardrobe.kit_path(Wardrobe.body_model_of(appearance)))) \
			.override_failure_message("%s has no body in the cast kit" % id).is_true()
		for piece: Dictionary in Wardrobe.pieces_of(appearance):
			assert_bool(ResourceLoader.exists(Wardrobe.kit_path(piece["model"]))) \
				.override_failure_message("%s wears %s, which the cast kit does not have"
					% [id, piece["model"]]).is_true()


## Filler is rolled off the id, and an id that rolls something unshipped is the same
## invisible character with nobody to blame for it.
func test_a_rolled_passenger_only_wears_shipped_pieces() -> void:
	for i in range(64):
		var appearance := Wardrobe.roll(i)
		assert_bool(ResourceLoader.exists(Wardrobe.kit_path(Wardrobe.body_model_of(appearance)))) \
			.override_failure_message("seed %d rolled a body outside the kit" % i).is_true()
		for piece: Dictionary in Wardrobe.pieces_of(appearance):
			assert_bool(ResourceLoader.exists(Wardrobe.kit_path(piece["model"]))) \
				.override_failure_message("seed %d rolled %s, which is not in the kit"
					% [i, piece["model"]]).is_true()


## An order that has not existed since the crusades is not something to meet twice
## between Paris and Calais.
func test_the_crowd_does_not_roll_a_sworn_knight() -> void:
	for i in range(256):
		assert_str(String(Wardrobe.roll(i).outfit)).not_contains("knight")


## Two people, same seed, same person. This is what lets a passenger be recognised
## rather than merely described.
func test_the_same_seed_is_the_same_person() -> void:
	var once := Wardrobe.roll(4242)
	var twice := Wardrobe.roll(4242)
	assert_array([once.body, once.outfit, once.hair, once.beard, once.accessories,
		once.tints, once.stature_metres]).is_equal(
		[twice.body, twice.outfit, twice.hair, twice.beard, twice.accessories,
		twice.tints, twice.stature_metres])


## A slot holds one thing. Two pauldrons on one shoulder is the kind of nonsense that
## only shows up as a shimmer when the animation moves.
func test_nothing_is_worn_twice_in_one_slot() -> void:
	for i in range(256):
		var appearance := Wardrobe.roll(i)
		var seen := {}
		for piece: Dictionary in Wardrobe.pieces_of(appearance):
			assert_bool(seen.has(piece["slot"])).override_failure_message(
				"seed %d fills the %s slot twice" % [i, piece["slot"]]).is_false()
			seen[piece["slot"]] = true


## A helmet does not have hair growing through the crown of it.
func test_a_covered_head_has_no_hair_under_it() -> void:
	for i in range(256):
		var appearance := Wardrobe.roll(i)
		var head: String = appearance.accessories.get(Wardrobe.SLOT_HEAD, "")
		if head == "":
			continue
		for hidden: StringName in Wardrobe.accessory_of(appearance.outfit, head).get("hides", []):
			if hidden == Wardrobe.SLOT_HAIR:
				assert_str(String(appearance.hair)).override_failure_message(
					"seed %d wears %s over a full head of hair" % [i, head]).is_empty()


## Every accessory a passenger wears comes off the suit they have on, so a peasant
## cannot end up in a knight's pauldrons.
func test_accessories_belong_to_the_outfit_worn() -> void:
	for passenger: Dictionary in GameContent.passengers():
		var appearance := Wardrobe.appearance_of(StringName(passenger.get("id", "")))
		for slot: StringName in appearance.accessories:
			assert_dict(Wardrobe.accessory_of(appearance.outfit, appearance.accessories[slot])) \
				.override_failure_message("%s wears %s, which %s does not offer"
					% [passenger.get("id", ""), appearance.accessories[slot], appearance.outfit]) \
				.is_not_empty()


## Every covering slot filled, every time. A missing one is bare skin in a gap.
func test_an_outfit_covers_the_whole_body() -> void:
	for key: StringName in Wardrobe.OUTFITS:
		for slot: StringName in Wardrobe.COVERING_SLOTS:
			assert_str(Wardrobe.OUTFITS[key]["parts"].get(slot, "")) \
				.override_failure_message("%s has nothing for the %s slot" % [key, slot]) \
				.is_not_empty()


## Garments mix, but only among suits that were made to sit near each other. A noble
## coat over peasant trousers is a costume change at the waist, and reads as one.
func test_a_mixed_outfit_stays_in_one_family() -> void:
	for i in range(256):
		var appearance := Wardrobe.roll(i)
		var group: StringName = Wardrobe.STYLES[Wardrobe.OUTFITS[appearance.outfit]["style"]]["group"]
		for slot: StringName in appearance.parts:
			var from := _suit_of(appearance.parts[slot])
			assert_str(String(Wardrobe.STYLES[Wardrobe.OUTFITS[from]["style"]]["group"])) \
				.override_failure_message("seed %d wears %s from the %s group over a %s coat"
					% [i, slot, Wardrobe.OUTFITS[from]["style"], group]) \
				.is_equal(String(group))


## Plate arrives whole or not at all. A breastplate over a peasant shirt is not a
## knight fallen on hard times, it is a bug with a story attached.
func test_a_whole_set_is_never_half_worn() -> void:
	for i in range(256):
		var appearance := Wardrobe.roll(i)
		var style: Dictionary = Wardrobe.STYLES[Wardrobe.OUTFITS[appearance.outfit]["style"]]
		if not style.get("whole_set", false):
			continue
		for slot: StringName in appearance.parts:
			assert_str(_suit_of(appearance.parts[slot])).override_failure_message(
				"seed %d wears a %s that is not part of the suit" % [i, slot]
			).is_equal(String(appearance.outfit))


## Mixing is the point, so at least some of the crowd has to actually be mixed. A rule
## that quietly stopped mixing would leave every passenger in a matching set and no
## test would notice.
func test_the_crowd_actually_mixes() -> void:
	var mixed := 0
	for i in range(256):
		var appearance := Wardrobe.roll(i)
		for slot: StringName in appearance.parts:
			if _suit_of(appearance.parts[slot]) != appearance.outfit:
				mixed += 1
				break
	assert_int(mixed).override_failure_message(
		"none of 256 rolled passengers wears a piece from another suit"
	).is_greater(32)


func _suit_of(model: String) -> String:
	for key: StringName in Wardrobe.OUTFITS:
		for slot: StringName in Wardrobe.OUTFITS[key]["parts"]:
			if Wardrobe.OUTFITS[key]["parts"][slot] == model:
				return String(key)
	return ""


## An oath is not taken at fifteen. Plate on a teen body is a child in their father's
## armour, and the escort is rolled rather than authored, so nothing else stops it.
func test_plate_is_only_ever_worn_by_an_adult() -> void:
	for i in range(64):
		for suit: StringName in [&"male_knight", &"female_knight"]:
			var appearance := Wardrobe.roll(i, suit)
			assert_bool(Wardrobe.BODIES[appearance.body]["adult"]).override_failure_message(
				"seed %d put %s in %s" % [i, appearance.body, suit]).is_true()


## The catalogue itself, not merely the parts of it somebody is wearing.
##
## The two tests above walk what the cast and the crowd actually put on, which is why
## they never noticed that both wizard outfits named eight meshes this repository has
## never contained. Nothing wore them -- `crowd: false` kept them out of every roll and
## nobody had been written into one -- so an entry describing clothes that do not exist
## sat there waiting for the first character given a long coat.
func test_every_outfit_in_the_catalogue_is_wearable() -> void:
	for outfit: StringName in Wardrobe.OUTFITS:
		var suit: Dictionary = Wardrobe.OUTFITS[outfit]
		for slot: StringName in suit["parts"]:
			assert_bool(ResourceLoader.exists(Wardrobe.kit_path(suit["parts"][slot]))) \
				.override_failure_message("%s names %s for its %s, which is not in the kit"
					% [outfit, suit["parts"][slot], slot]).is_true()
		for accessory: Dictionary in suit.get("accessories", []):
			assert_bool(ResourceLoader.exists(Wardrobe.kit_path(accessory["model"]))) \
				.override_failure_message("%s offers %s, which is not in the kit"
					% [outfit, accessory["model"]]).is_true()


## Everybody the mystery names is dressed on purpose.
##
## A passenger with no written appearance still gets one -- rolled off their id, stable
## and shipped -- which is right for filler and wrong for somebody whose berth is in the
## register. The roll cannot know that a steward wears white or that the guard's collar
## is the company's, so a principal left to it is a principal the player cannot tell
## from a stranger.
func test_everybody_in_the_register_is_dressed_on_purpose() -> void:
	for passenger: Dictionary in GameContent.passengers():
		var id := StringName(passenger.get("id", ""))
		assert_bool(Wardrobe.CAST.has(id)).override_failure_message(
			"%s is in the content and not in the wardrobe, so they are wearing a roll"
			% id
		).is_true()


## And no two of them are the same person from across a carriage.
##
## There are eight outfits and twelve passengers, so sharing a suit is unavoidable and
## sharing a silhouette is not: the wardrobe mixes garments across suits on purpose --
## the steward is a peasant shirt over noble legs, the engineer a good coat over
## working clothes. What has to be unique is the set of pieces, because that is what
## somebody sees at the end of a corridor before they are close enough to read a face.
func test_no_two_passengers_are_wearing_the_same_thing() -> void:
	var worn := {}
	for passenger: Dictionary in GameContent.passengers():
		var id := StringName(passenger.get("id", ""))
		var appearance := Wardrobe.appearance_of(id)
		var pieces: Array[String] = []
		for piece: Dictionary in Wardrobe.pieces_of(appearance):
			pieces.append(String(piece["model"]))
		pieces.sort()
		var silhouette := "|".join(pieces)
		assert_bool(worn.has(silhouette)).override_failure_message(
			"%s is wearing exactly what %s is wearing" % [id, worn.get(silhouette, "")]
		).is_false()
		worn[silhouette] = id


## How somebody walks, which is a thing about the person rather than about where they
## are going. Only the conductor has one: everybody else is a passenger going
## somewhere, and he is the train.
func test_the_conductor_walks_the_train_formally() -> void:
	var appearance := Wardrobe.appearance_of(&"moreau")
	assert_str(appearance.bearing).is_equal(&"formal")
	assert_str(CharacterRig.WALK_CLIP_BY_BEARING[appearance.bearing]).override_failure_message(
		"the conductor's bearing does not name a clip, so he walks like everybody else"
	).is_equal(CharacterRig.WALK_FORMAL_CLIP)


func test_everybody_else_walks_plainly() -> void:
	for passenger: Dictionary in GameContent.passengers():
		var id := StringName(passenger.get("id", ""))
		if id == Session.ROUNDS_OF_THE_TRAIN:
			continue
		assert_str(Wardrobe.appearance_of(id).bearing).override_failure_message(
			"%s carries themselves like the conductor" % id).is_equal(&"plain")


## The bearing has to name a clip the kit actually baked, or the rig quietly builds a
## blend space with a null at the forward point and the legs stop moving.
func test_every_bearing_names_a_clip() -> void:
	var library: AnimationLibrary = load(
		"res://assets/player/animations/player_animations.res")
	for bearing: StringName in CharacterRig.WALK_CLIP_BY_BEARING:
		var clip: String = CharacterRig.WALK_CLIP_BY_BEARING[bearing]
		assert_bool(library.has_animation(clip)).override_failure_message(
			"bearing '%s' names %s, which is not in the kit" % [bearing, clip]).is_true()
