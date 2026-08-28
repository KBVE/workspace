# GdUnitTestSuite
extends GdUnitTestSuite

## &generated -> the night is drawn, so the thing worth testing is not one night but
##           the rules every night has to keep. These run the draw over many seeds and
##           assert the invariants the deduction rests on.

const SEEDS := 200


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


func test_the_answer_is_not_the_same_every_run() -> void:
	var drawn := {}
	for s in SEEDS:
		drawn[_night(s).culprit_id] = true
	assert_int(drawn.size()).override_failure_message(
		"every seed accused the same person, which is not a draw"
	).is_greater(2)
