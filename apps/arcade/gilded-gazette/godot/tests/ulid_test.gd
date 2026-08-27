# GdUnitTestSuite
extends GdUnitTestSuite


func test_an_id_is_26_crockford_characters() -> void:
	var id := Ulid.generate()
	assert_int(id.length()).is_equal(26)
	assert_bool(Ulid.is_valid(id)).is_true()
	for c: String in id:
		assert_int(Ulid.ALPHABET.find(c)).override_failure_message(
			"%s is not in the Crockford alphabet" % c
		).is_greater_equal(0)


func test_the_alphabet_excludes_the_letters_that_misread() -> void:
	for c: String in ["I", "L", "O", "U"]:
		assert_int(Ulid.ALPHABET.find(c)).override_failure_message(
			"%s is in the alphabet; Crockford drops it so ids cannot be misread" % c
		).is_equal(-1)


func test_ids_from_the_same_millisecond_still_sort_in_creation_order() -> void:
	var ids: Array[String] = []
	for i in range(500):
		ids.append(Ulid.generate(1_700_000_000_000))
	var sorted := ids.duplicate()
	sorted.sort()
	assert_array(ids).override_failure_message(
		"ids minted inside one millisecond must increase, or the journal loses its order"
	).is_equal(sorted)


func test_later_milliseconds_sort_after_earlier_ones() -> void:
	var early := Ulid.generate(1_700_000_000_000)
	var late := Ulid.generate(1_700_000_000_001)
	assert_bool(late > early).is_true()


func test_ids_are_unique_across_many_calls() -> void:
	var seen := {}
	for i in range(2000):
		seen[Ulid.generate(1_700_000_000_000)] = true
	assert_int(seen.size()).is_equal(2000)


func test_the_random_half_is_actually_random() -> void:
	# &regression -> randi_range over 40 bits returned its own bounds, so every
	#                id in a millisecond shared one random half
	var halves := {}
	for i in range(200):
		halves[Ulid.generate(1_700_000_000_000 + i).substr(10, 8)] = true
	assert_int(halves.size()).override_failure_message(
		"random halves repeat; ids are predictable"
	).is_greater(150)


func test_the_timestamp_survives_the_round_trip() -> void:
	var ms := 1_700_000_123_456
	assert_int(Ulid.timestamp_of(Ulid.generate(ms))).is_equal(ms)


func test_a_malformed_id_is_rejected_rather_than_decoded() -> void:
	assert_bool(Ulid.is_valid("")).is_false()
	assert_bool(Ulid.is_valid("TOO-SHORT")).is_false()
	assert_bool(Ulid.is_valid("I".repeat(26))).is_false()
	assert_int(Ulid.timestamp_of("nonsense")).is_equal(-1)
