# GdUnitTestSuite
extends GdUnitTestSuite

## &generated -> the night is drawn, so the thing worth testing is not one night but
##           the rules every night has to keep. These run the draw over many seeds and
##           assert the invariants the deduction rests on.

const SEEDS := 200

## More than [constant SEEDS], because these count how often each of seven names comes
## up rather than asserting a rule about one night: at 200 the counts are noisy enough
## that an even draw looks uneven.
const FAIRNESS_SEEDS := 700


func _night(seed_value: int) -> TheNight:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return TheNight.draw(rng, Session.DEPARTURE_MINUTES)


func _content() -> Dictionary:
	var cast := {}
	for passenger: Dictionary in GameContent.passengers():
		cast[StringName(passenger.get("id", ""))] = passenger
	return cast


func test_a_night_can_always_be_drawn() -> void:
	for s in SEEDS:
		assert_object(_night(s)).override_failure_message(
			"seed %d produced no night at all" % s
		).is_not_null()


func test_everybody_but_the_culprit_keeps_their_own_word() -> void:
	# The whole deduction rests on this. If anyone else is placed somewhere their claims
	# deny, they contradict themselves for no reason and the culprit stops being the one
	# person whose words fail.
	var cast := _content()
	for s in SEEDS:
		var night := _night(s)
		for id: StringName in cast:
			if id == night.culprit_id:
				continue
			for step in night.steps():
				var where := night.where_is(id, step * TheNight.STEP_MINUTES)
				if where.is_empty():
					continue
				assert_bool(night._allows(cast[id], where, step, Session.DEPARTURE_MINUTES)) \
					.override_failure_message(
						"seed %d: %s was put in %s at step %d, which their own claims deny"
						% [s, id, where, step]
					).is_true()


func test_the_culprit_was_somewhere_their_own_word_denies() -> void:
	var cast := _content()
	for s in SEEDS:
		var night := _night(s)
		var step: int = night._step_of(night.murder_elapsed)
		assert_str(night.where_is(night.culprit_id, night.murder_elapsed)) \
			.override_failure_message("seed %d: the culprit was not at the scene" % s) \
			.is_equal(String(night.scene))
		assert_bool(night._allows(cast[night.culprit_id], night.scene, step,
			Session.DEPARTURE_MINUTES)).override_failure_message(
				"seed %d: being at the scene costs %s nothing, so nothing can catch them"
				% [s, night.culprit_id]
			).is_false()


func test_the_body_stays_where_it_was_left() -> void:
	for s in SEEDS:
		var night := _night(s)
		assert_str(night.where_is(night.victim_id, night.murder_elapsed)) \
			.is_equal(String(night.scene))
		assert_bool(night.is_over(night.victim_id, night.murder_elapsed + 60)).is_true()
		assert_bool(night.is_over(night.culprit_id, night.murder_elapsed + 60)) \
			.override_failure_message("only the victim's evening ends").is_false()


func test_nobody_is_anywhere_before_they_board() -> void:
	var cast := _content()
	for s in SEEDS:
		var night := _night(s)
		for id: StringName in cast:
			assert_str(night.where_is(id, -1)).override_failure_message(
				"seed %d: %s was aboard before the train left Paris" % [s, id]
			).is_equal("")


func test_nobody_goes_back_out_onto_the_platform() -> void:
	var cast := _content()
	for s in SEEDS:
		var night := _night(s)
		for id: StringName in cast:
			# Step 0 is Paris. Anything after it is a moving train.
			for step in range(6, night.steps()):
				assert_str(night.where_is(id, step * TheNight.STEP_MINUTES)) \
					.override_failure_message(
						"seed %d: %s was on the platform at step %d" % [s, id, step]
					).is_not_equal(String(TheNight.BOARDING_ONLY))


func test_every_sighting_is_a_line_somebody_wrote() -> void:
	# The point of the sightings collection: a generated night is drawn from authored
	# prose and never composes any of its own.
	var cast := _content()
	for s in range(20):
		var night := _night(s)
		for id: StringName in cast:
			for step in night.steps():
				var elapsed := step * TheNight.STEP_MINUTES
				var where := night.where_is(id, elapsed)
				if where.is_empty():
					continue
				var written: Array = cast[id].get("sightings", {}).get(String(where), [])
				assert_array(written).override_failure_message(
					"seed %d: %s was put in %s with no line written for it" % [s, id, where]
				).contains([night.note_for(id, elapsed)])


## Every weapon the sheet lists has to be one the run can name, for the same reason
## every suspect does. The rule is the model: a weapon with no model cannot be put in
## a room, so it cannot be found, so naming it would be a guess between things the
## player never saw.
func test_the_weapon_is_drawn_from_what_can_be_found_aboard() -> void:
	var arsenal := TheNight.weapons()
	assert_array(arsenal).override_failure_message(
		"no weapon has a model, so no night can say what it was done with"
	).is_not_empty()
	for id: StringName in arsenal:
		var item := GameContent.by_id("items", String(id))
		assert_str(str(item.get("model", ""))).override_failure_message(
			"%s is drawable but has no model to put in a room" % id
		).is_not_empty()
	for s in SEEDS:
		assert_array(arsenal).override_failure_message(
			"seed %d drew a weapon that is not in the arsenal" % s
		).contains([_night(s).weapon_id])


## And no weapon is a long shot, on the same reasoning as the suspects.
func test_every_weapon_can_be_the_answer() -> void:
	var seen := {}
	for s in FAIRNESS_SEEDS:
		var w := _night(s).weapon_id
		seen[w] = int(seen.get(w, 0)) + 1
	for id: StringName in TheNight.weapons():
		assert_int(int(seen.get(id, 0))).override_failure_message(
			"%s was never drawn in %d nights, so the sheet lists it for nothing"
			% [id, FAIRNESS_SEEDS]
		).is_greater(0)


func test_the_answer_is_not_the_same_every_run() -> void:
	var drawn := {}
	for s in SEEDS:
		drawn[_night(s).culprit_id] = true
	assert_int(drawn.size()).override_failure_message(
		"every seed accused the same person, which is not a draw"
	).is_greater(2)


## Everybody the dossier calls a suspect has to be somebody the answer can actually
## be. A name on that list who can never have done it is a name the player crosses
## off by playing enough runs rather than by deducing anything, and the list stops
## being information the moment one entry on it is decoration.
##
## This is a real failure the content had: the culprit must be catchable in a lie,
## so a passenger whose alibi ends before the murder can happen has nothing to
## contradict and was drawn zero times in two thousand.
func test_every_suspect_can_be_the_answer() -> void:
	var seen := {}
	for s in FAIRNESS_SEEDS:
		seen[_night(s).culprit_id] = int(seen.get(_night(s).culprit_id, 0)) + 1
	for id: StringName in _content():
		if _content()[id].get("victim", false):
			continue
		assert_int(int(seen.get(id, 0))).override_failure_message(
			"%s was never the culprit in %d draws, so the dossier lists them as a "
			% [id, FAIRNESS_SEEDS] + "suspect the run can never make good on"
		).is_greater(0)


## And no suspect is a long shot. Drawn once in two thousand is drawable in the same
## sense a lottery is winnable; what it produces in play is a cast the experienced
## player stops considering, which is the deduction being replaced by a memorised
## bias. The floor is deliberately loose -- the draw is uniform over whoever the
## murder hour leaves catchable, and that set moves with the hour, so this is here
## to catch a suspect falling off it rather than to police the shape.
func test_no_suspect_is_a_long_shot() -> void:
	var seen := {}
	var suspects := 0
	for id: StringName in _content():
		if not _content()[id].get("victim", false):
			suspects += 1
	for s in FAIRNESS_SEEDS:
		var who := _night(s).culprit_id
		seen[who] = int(seen.get(who, 0)) + 1
	var even := float(FAIRNESS_SEEDS) / float(suspects)
	for id: StringName in seen:
		assert_float(float(seen[id])).override_failure_message(
			"%s came up %d times in %d draws against an even share of %.0f, so the "
			% [id, seen[id], FAIRNESS_SEEDS, even] + "answer is one of the others in "
			+ "all but name"
		).is_greater(even * 0.4)
