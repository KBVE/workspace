# GdUnitTestSuite
extends GdUnitTestSuite

## What everybody says about where they were, sent as the enquiry opens.
##
## Which account a passenger gives is drawn per run, so the browser cannot read it out
## of the compiled content: the content holds every account they might have given and
## nothing about which one they did. Without this the case board has nobody anywhere
## until the player walks in and sees for themselves.

const SCENE := "res://scenes/train/train.scn"


func _statements() -> Array[GameEvent]:
	var said: Array[GameEvent] = []
	Ecs.world.add_callable(GameEvents.TESTIMONY,
		func(e: GameEvent) -> void: said.append(e))
	return said


func test_the_enquiry_takes_a_statement_from_everybody() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var said := _statements()
	Session.begin()
	Ecs.notify(GameEvents.UI_RESTART, {})
	await runner.simulate_frames(6)

	var heard := {}
	for statement: GameEvent in said:
		heard[str(statement.data.get("who", ""))] = true
	assert_int(heard.size()).override_failure_message(
		"%d of %d passengers said anything about where they were"
			% [heard.size(), GameContent.passengers().size()]
	).is_equal(GameContent.passengers().size())


## Testimony is a room and an hour. A statement naming neither places nobody, and the
## board would draw a passenger standing in nowhere at midnight.
func test_every_statement_names_a_room_and_an_hour() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var said := _statements()
	Ecs.notify(GameEvents.UI_RESTART, {})
	await runner.simulate_frames(6)

	assert_int(said.size()).is_greater(0)
	for statement: GameEvent in said:
		var where := str(statement.data.get("where", ""))
		assert_bool(GameContent.by_id("locations", where).is_empty()) \
			.override_failure_message("'%s' is not a room anybody could be in" % where) \
			.is_false()
		assert_int(int(statement.data.get("at", -1))).is_between(0, 24 * 60)


## What they say is drawn from what they might have said, so it has to be one of the
## accounts the content actually writes for them -- a claim assembled anywhere else is
## a statement nobody authored.
func test_what_they_say_is_something_they_could_have_said() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	for passenger: Dictionary in GameContent.passengers():
		var who := StringName(passenger.get("id", ""))
		var drawn := Session.night.claims_of(who)
		assert_int(drawn.size()).override_failure_message(
			"%s was drawn no account at all" % who).is_greater(0)

		var authored := false
		for alibi: Dictionary in passenger.get("alibis", []):
			if alibi.get("claims", []) == drawn:
				authored = true
				break
		assert_bool(authored).override_failure_message(
			"%s is giving an account nobody wrote for them" % who).is_true()


## A claim of never having been somewhere is a real thing to say and the generator
## respects it, but there is nowhere to put a man on the strength of one.
func test_a_denial_places_nobody() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var said := _statements()
	Ecs.notify(GameEvents.UI_RESTART, {})
	await runner.simulate_frames(6)

	var denials := 0
	for passenger: Dictionary in GameContent.passengers():
		for claim: Dictionary in Session.night.claims_of(StringName(passenger.get("id", ""))):
			if claim.get("never", false):
				denials += 1
	assert_int(said.size() + denials).override_failure_message(
		"%d statements went out for %d claims and %d denials"
			% [said.size(), said.size() + denials, denials]
	).is_greater_equal(said.size())


## The hour is absolute, because the browser has a clock and no idea what a step is. A
## claim with no start runs from the moment they boarded.
func test_a_claim_with_no_hour_starts_at_the_call() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	assert_int(Session.night.minutes_of("")).is_equal(Session.DEPARTURE_MINUTES)
	assert_int(Session.night.minutes_of("23:30")).is_equal(23 * 60 + 30)
