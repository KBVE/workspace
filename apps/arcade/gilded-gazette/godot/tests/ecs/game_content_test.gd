# GdUnitTestSuite
extends GdUnitTestSuite

## The query layer both runtimes read the world through.
##
## Nothing here is clever, which is the point: every one of these is a filter over the
## compiled content, and a filter that quietly returns nothing does not fail -- the
## carriage is simply built empty, the passenger simply never appears, and the run goes
## on being wrong without saying so.

func test_the_train_is_the_rooms_that_have_a_carriage() -> void:
	var aboard := GameContent.carriage_locations()
	assert_int(aboard.size()).is_greater(0)
	assert_bool(aboard.has(&"platform")).override_failure_message(
		"the platform was built into the consist, and nobody is killed before they board"
	).is_false()


## Position along the train, in order, with no gaps. [Consist] builds by index and
## [SOccupancy] resolves a world position into one, so a hole here is a carriage that
## stands for nowhere.
func test_the_rooms_run_down_the_train_in_order() -> void:
	var aboard := GameContent.carriage_locations()
	for i in range(aboard.size()):
		var room := GameContent.by_id("locations", String(aboard[i]))
		assert_int(int(room.get("carriage", -1))).override_failure_message(
			"'%s' is the %dth room down the train and says it is the %dth"
				% [aboard[i], i, int(room.get("carriage", -1))]).is_equal(i)


func test_every_carriage_is_asked_about_by_position() -> void:
	var aboard := GameContent.carriage_locations()
	for i in range(aboard.size()):
		# Empty is a fine answer -- several carriages are deliberately bare -- but the
		# lookup has to find the room, and a room it cannot find returns empty as well.
		assert_object(GameContent.furnishings_at(i)).is_not_null()
		assert_object(GameContent.notices_in(i)).is_not_null()
		assert_object(GameContent.items_in(i)).is_not_null()


func test_a_carriage_that_is_not_there_furnishes_nothing() -> void:
	var past_the_end := GameContent.carriage_locations().size()
	assert_int(GameContent.furnishings_at(past_the_end).size()).is_equal(0)
	assert_int(GameContent.notices_in(past_the_end).size()).is_equal(0)
	assert_int(GameContent.items_in(past_the_end).size()).is_equal(0)


## Only items with somewhere to be. An item with no model is real without being
## anywhere, which is most of them, and one drawn into a carriage would be a thing the
## player can walk up to and never see.
func test_only_things_that_can_be_seen_are_left_lying_about() -> void:
	for i in range(GameContent.carriage_locations().size()):
		for item: Dictionary in GameContent.items_in(i):
			assert_str(str(item.get("model", ""))).override_failure_message(
				"'%s' lies in carriage %d with no model to draw" % [item.get("id", ""), i]
			).is_not_empty()
			assert_bool(item.has("found")).override_failure_message(
				"'%s' lies in carriage %d with nowhere to lie" % [item.get("id", ""), i]
			).is_true()


func test_an_item_lies_in_the_room_it_is_asked_for() -> void:
	var aboard := GameContent.carriage_locations()
	for i in range(aboard.size()):
		for item: Dictionary in GameContent.items_in(i):
			assert_str(str(item.get("location", ""))).is_equal(String(aboard[i]))


func test_nothing_answers_to_a_name_that_is_not_there() -> void:
	assert_bool(GameContent.by_id("passengers", "nobody_by_that_name").is_empty()).is_true()
	assert_bool(GameContent.by_id("items", "a_harsh_word").is_empty()).is_true()
	assert_bool(GameContent.by_id("locations", "the_footplate").is_empty()).is_true()
	# A collection that does not exist answers the same way rather than erroring: the
	# caller asked for something that is not there either way.
	assert_bool(GameContent.by_id("rumours", "anything").is_empty()).is_true()


func test_every_passenger_starts_somewhere_that_exists() -> void:
	for passenger: Dictionary in GameContent.passengers():
		var where := str(passenger.get("location", ""))
		assert_bool(GameContent.by_id("locations", where).is_empty()) \
			.override_failure_message("%s starts in '%s', which is nowhere"
				% [passenger.get("id", ""), where]).is_false()


func test_a_passenger_is_found_where_they_are_looked_for() -> void:
	for passenger: Dictionary in GameContent.passengers():
		var where := str(passenger.get("location", ""))
		var found := GameContent.passengers_at(where).map(
			func(p: Dictionary) -> String: return p.get("id", ""))
		assert_bool(found.has(passenger.get("id", ""))).is_true()


## What somebody owns is read off the item rather than listed on the person, so the two
## cannot disagree -- but an owner who is not aboard can still be written down.
func test_everything_owned_is_owned_by_somebody_aboard() -> void:
	for item: Dictionary in GameContent.items():
		var owner := str(item.get("owner", ""))
		if owner.is_empty():
			continue
		assert_bool(GameContent.by_id("passengers", owner).is_empty()) \
			.override_failure_message("'%s' belongs to '%s', who is not aboard"
				% [item.get("id", ""), owner]).is_false()


func test_an_unwritten_section_is_empty_rather_than_missing() -> void:
	var anybody: Dictionary = GameContent.passengers()[0]
	assert_bool(GameContent.section(anybody, "a_heading_nobody_wrote").is_empty()).is_true()


## Every passenger owes one, because who the body is, is drawn: whoever it turns out to
## be has to read as somebody rather than as a slot.
func test_everybody_has_a_body_written_for_them() -> void:
	for passenger: Dictionary in GameContent.passengers():
		assert_bool(GameContent.section(passenger, "the_body").is_empty()) \
			.override_failure_message("%s has no '## The Body' to be found as"
				% passenger.get("id", "")).is_false()
