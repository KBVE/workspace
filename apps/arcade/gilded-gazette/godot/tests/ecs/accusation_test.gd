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


func _accuse(who: StringName) -> void:
	Ecs.notify(GameEvents.UI_ACCUSE, {"who": String(who)})


func _run() -> CRun:
	return Session.run


func _somebody_innocent() -> StringName:
	for passenger: Dictionary in GameContent.passengers():
		var id := StringName(passenger.get("id", ""))
		if id != Session.culprit and id != Session.night.victim_id:
			return id
	return &""


func test_naming_the_culprit_wins_the_run() -> void:
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
