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
