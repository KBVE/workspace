# GdUnitTestSuite
extends GdUnitTestSuite

## &claims -> systems ask the journal instead of tracking their own flags, so
##            these queries are the contract the rest of the game leans on

func before_test() -> void:
	Journal.clear()


func after_test() -> void:
	Journal.clear()


func test_recording_returns_a_ulid_and_keeps_the_entry() -> void:
	var id := Journal.record(StateBits.JournalKind.TALKED, "player", "beaumont", "corridor")
	assert_bool(Ulid.is_valid(id)).is_true()
	assert_int(Journal.entries().size()).is_equal(1)
	assert_str(Journal.last()["target"]).is_equal("beaumont")


func test_entries_sort_by_id_in_the_order_they_happened() -> void:
	var ids: Array[String] = []
	for i in range(50):
		ids.append(Journal.record(StateBits.JournalKind.ENTERED, "player", "", "cabin"))
	var sorted := ids.duplicate()
	sorted.sort()
	assert_array(ids).override_failure_message(
		"journal ids must sort into creation order, that is why they are ULIDs"
	).is_equal(sorted)


func test_queries_narrow_by_kind_actor_and_target() -> void:
	Journal.record(StateBits.JournalKind.TALKED, "player", "beaumont")
	Journal.record(StateBits.JournalKind.TALKED, "player", "weiss")
	Journal.record(StateBits.JournalKind.SHOWED, "player", "beaumont")

	assert_int(Journal.find_entries(StateBits.JournalKind.TALKED).size()).is_equal(2)
	assert_int(Journal.find_entries(-1, "player", "beaumont").size()).is_equal(2)
	assert_int(Journal.find_entries(StateBits.JournalKind.SHOWED, "", "beaumont").size()).is_equal(1)


func test_has_happened_answers_the_question_systems_actually_ask() -> void:
	assert_bool(Journal.has_happened(StateBits.JournalKind.SHOWED, "player", "weiss")).is_false()
	Journal.record(StateBits.JournalKind.SHOWED, "player", "weiss")
	assert_bool(Journal.has_happened(StateBits.JournalKind.SHOWED, "player", "weiss")).is_true()


func test_the_journal_is_capped_and_drops_the_oldest_first() -> void:
	for i in range(Journal.LIMIT + 20):
		Journal.record(StateBits.JournalKind.ENTERED, "player", "", "corridor")
	assert_int(Journal.entries().size()).override_failure_message(
		"an uncapped journal grows without bound inside wasm"
	).is_equal(Journal.LIMIT)


func test_an_empty_journal_reports_nothing_rather_than_failing() -> void:
	assert_dict(Journal.last()).is_empty()
	assert_array(Journal.find_entries()).is_empty()
