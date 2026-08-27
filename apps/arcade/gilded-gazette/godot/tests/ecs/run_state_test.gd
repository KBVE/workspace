# GdUnitTestSuite
extends GdUnitTestSuite

## &regression -> level, score and outcome used to be Train locals, so a scene
##                swap reset the run. They live on Session now, which outlives it.

func after_test() -> void:
	Session.begin()


func test_the_run_survives_a_scene_being_torn_down() -> void:
	Session.run.score = 7
	Session.run.level_index = 2
	var carriage: Node = auto_free(load("res://scenes/train/train.scn").instantiate())
	add_child(carriage)
	await await_idle_frame()
	remove_child(carriage)
	await await_idle_frame()
	assert_int(Session.run.score).override_failure_message(
		"the score reset when the scene left; run state is scene-local again"
	).is_equal(7)


func test_begin_resets_the_run_without_replacing_the_components() -> void:
	var run_before := Session.run
	var clock_before := Session.time_of_day
	Session.run.score = 5
	Session.begin()
	assert_int(Session.run.score).is_equal(0)
	assert_object(Session.run).override_failure_message(
		"begin() replaced CRun, so anything holding a reference now has a stale one"
	).is_same(run_before)
	assert_object(Session.time_of_day).is_same(clock_before)


func test_the_run_starts_at_departure() -> void:
	Session.begin()
	assert_int(Session.time_of_day.minutes_past_midnight).is_equal(Session.DEPARTURE_MINUTES)


func test_the_whole_cast_is_aboard() -> void:
	assert_int(Ecs.world.view(CPassenger).size()).is_equal(GameContent.passengers().size())
