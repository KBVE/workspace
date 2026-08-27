# GdUnitTestSuite
extends GdUnitTestSuite

## StateBits : gen! <- shared/state.json
##
## &pins   -> layout parity; a hand edit of state_bits.gd fails here, not silently in TS
## &covers -> has_all() | has_any() | describe_player_flags() | run_state_name()

## &note -> escapes res://; source only, tests/* is cut from every export preset
const SPEC_PATH := "res://../shared/state.json"


func _spec() -> Dictionary:
	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	return JSON.parse_string(file.get_as_text())


# ---- &parity : StateBits <-> shared/state.json ----

func test_run_state_matches_the_shared_spec() -> void:
	var values: Dictionary = _spec()["enums"]["RunState"]["values"]
	for key: String in values:
		assert_int(StateBits.RunState[key]).is_equal(int(values[key]))
	assert_int(StateBits.RunState.size()).is_equal(values.size())


func test_player_flags_match_the_shared_spec() -> void:
	var bits: Dictionary = _spec()["flags"]["PlayerFlags"]["bits"]
	for key: String in bits:
		var expected := 1 << int(bits[key])
		assert_int(StateBits[&"PLAYER_%s" % key]).is_equal(expected)


func test_flag_bits_are_distinct_powers_of_two() -> void:
	var seen: Array[int] = []
	for bit: int in [
		StateBits.PLAYER_ALIVE,
		StateBits.PLAYER_MOVING,
		StateBits.PLAYER_ATTACKING,
		StateBits.PLAYER_INVULNERABLE,
	]:
		assert_int(bit & (bit - 1)).is_equal(0)
		assert_array(seen).not_contains([bit])
		seen.append(bit)


# ---- &helpers : bit tests ----

func test_has_all_requires_every_bit() -> void:
	var value := StateBits.PLAYER_ALIVE | StateBits.PLAYER_MOVING
	assert_bool(StateBits.has_all(value, StateBits.PLAYER_ALIVE)).is_true()
	assert_bool(StateBits.has_all(value, value)).is_true()
	assert_bool(StateBits.has_all(value, value | StateBits.PLAYER_ATTACKING)).is_false()


func test_has_any_requires_one_bit() -> void:
	var value := StateBits.PLAYER_ALIVE
	assert_bool(StateBits.has_any(value, StateBits.PLAYER_ALIVE | StateBits.PLAYER_MOVING)).is_true()
	assert_bool(StateBits.has_any(value, StateBits.PLAYER_MOVING)).is_false()
	assert_bool(StateBits.has_any(0, StateBits.PLAYER_ALIVE)).is_false()


# ---- &decoders : packed int -> readable ----

func test_describe_player_flags_lists_every_set_bit() -> void:
	var value := StateBits.PLAYER_ALIVE | StateBits.PLAYER_ATTACKING
	assert_str(StateBits.describe_player_flags(value)).is_equal("ALIVE|ATTACKING")


func test_describe_player_flags_reports_nothing_set() -> void:
	assert_str(StateBits.describe_player_flags(0)).is_equal("NONE")


func test_describe_player_flags_surfaces_bits_it_does_not_know() -> void:
	# &why -> a stale payload would else decode as a plausible subset, hiding the drift
	assert_str(StateBits.describe_player_flags(StateBits.PLAYER_ALIVE | 1 << 20)) \
		.is_equal("ALIVE|UNKNOWN(0x100000)")


func test_run_state_name_round_trips_and_flags_unknown_values() -> void:
	assert_str(StateBits.run_state_name(StateBits.RunState.PLAYING)).is_equal("PLAYING")
	assert_str(StateBits.run_state_name(StateBits.RunState.BOOTING)).is_equal("BOOTING")
	assert_str(StateBits.run_state_name(99)).is_equal("UNKNOWN(99)")
