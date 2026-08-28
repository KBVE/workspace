# GdUnitTestSuite
extends GdUnitTestSuite

## The run's one irreversible move. The answer is drawn, so this is the only place the
## game compares what the player worked out against what actually happened.

const SCENE := "res://scenes/train/train.scn"


## The journal and the run outlive a scene, so a verdict or an entry from the test
## before this one would be read as this one's.
func before_test() -> void:
	Journal.clear()
	Session.begin()


## The whole accusation, defaulting to the parts the night actually drew, so a test
## about one third of it does not have to spell out the other two.
func _accuse(who: StringName, weapon: StringName = &"", room: StringName = &"") -> void:
	Ecs.notify(GameEvents.UI_ACCUSE, {
		"who": String(who),
		"weapon": String(weapon if not weapon.is_empty() else Session.night.weapon_id),
		"room": String(room if not room.is_empty() else Session.night.scene),
	})


## A weapon that is not the one it was done with.
func _another_weapon() -> StringName:
	for id: StringName in TheNight.weapons():
		if id != Session.night.weapon_id:
			return id
	return &""


## A room that is not the one it happened in.
func _another_room() -> StringName:
	for id: StringName in GameContent.carriage_locations():
		if id != Session.night.scene:
			return id
	return &""


func _run() -> CRun:
	return Session.run


func _somebody_innocent() -> StringName:
	for passenger: Dictionary in GameContent.passengers():
		var id := StringName(passenger.get("id", ""))
		if id != Session.culprit and id != Session.night.victim_id:
			return id
	return &""


func test_the_whole_answer_wins_the_run() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(Session.culprit)
	await runner.simulate_frames(4)
	assert_str(_run().outcome).is_equal("won")


func test_naming_anybody_else_loses_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(_somebody_innocent())
	await runner.simulate_frames(4)
	assert_str(_run().outcome).is_equal("lost")


func test_the_accusation_is_recorded_against_the_name() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	var accused := _somebody_innocent()
	_accuse(accused)
	await runner.simulate_frames(4)

	var written := Journal.find_entries(StateBits.JournalKind.ACCUSED)
	assert_int(written.size()).override_failure_message(
		"the run recorded %d accusations for one name given" % written.size()
	).is_equal(1)
	assert_str(written[0]["target"]).is_equal(String(accused))


func test_a_second_name_does_not_overwrite_the_first() -> void:
	# The run is over either way. Letting a second accusation land would turn a wrong
	# answer into a right one with nothing recording that the player had been wrong.
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(_somebody_innocent())
	await runner.simulate_frames(4)
	_accuse(Session.culprit)
	await runner.simulate_frames(4)
	assert_str(_run().outcome).override_failure_message(
		"a second accusation talked the run out of a verdict it had already given"
	).is_equal("lost")


func test_a_name_nobody_aboard_answers_to_is_refused() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(&"nobody_by_that_name")
	await runner.simulate_frames(4)
	assert_str(_run().outcome).override_failure_message(
		"the run ended on a name that is not on the register"
	).is_equal("start")


func test_the_night_stops_when_the_name_is_given() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(Session.culprit)
	await runner.simulate_frames(4)
	assert_bool(Session.time_of_day.running).override_failure_message(
		"the evening carried on after there was nobody left watching it"
	).is_false()


## The three parts that make it worth asking for three parts. Each of these is the
## right answer to two thirds of the question, and none of them is the answer.
func test_the_right_name_with_the_wrong_weapon_loses() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(Session.culprit, _another_weapon())
	await runner.simulate_frames(4)
	assert_str(_run().outcome).override_failure_message(
		"the run was won on a weapon it was not done with"
	).is_equal("lost")


func test_the_right_name_in_the_wrong_room_loses() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(Session.culprit, &"", _another_room())
	await runner.simulate_frames(4)
	assert_str(_run().outcome).override_failure_message(
		"the run was won on a room it did not happen in"
	).is_equal("lost")


func test_the_whole_answer_against_the_wrong_person_loses() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(_somebody_innocent())
	await runner.simulate_frames(4)
	assert_str(_run().outcome).is_equal("lost")


## An accusation is refused rather than lost when part of it is not a thing at all.
## A reader cannot have meant a weapon that does not exist, so recording it as their
## answer would be recording something they did not say.
func test_a_weapon_that_is_not_one_is_refused() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(Session.culprit, &"a_harsh_word")
	await runner.simulate_frames(4)
	assert_str(_run().outcome).override_failure_message(
		"the run ended on a weapon that is not aboard"
	).is_equal("start")


func test_a_room_that_is_not_aboard_is_refused() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(Session.culprit, &"", &"the_footplate")
	await runner.simulate_frames(4)
	assert_str(_run().outcome).override_failure_message(
		"the run ended in a room that is not in the consist"
	).is_equal("start")


## The platform in particular, because it is a location and not a room: nobody is
## killed before they board, and TheNight will not put the scene there.
func test_the_platform_is_not_somewhere_it_can_have_happened() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(Session.culprit, &"", &"platform")
	await runner.simulate_frames(4)
	assert_str(_run().outcome).override_failure_message(
		"the run ended on the platform, where nobody was killed"
	).is_equal("start")


## Where it was named is worth keeping. The journal already records who, and a verdict
## the player can read back needs the room they gave with it.
func test_the_room_given_is_recorded_with_the_name() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(30)
	_accuse(Session.culprit)
	await runner.simulate_frames(4)
	var written := Journal.find_entries(StateBits.JournalKind.ACCUSED)
	assert_int(written.size()).is_equal(1)
	assert_str(written[0]["place"]).is_equal(String(Session.night.scene))
