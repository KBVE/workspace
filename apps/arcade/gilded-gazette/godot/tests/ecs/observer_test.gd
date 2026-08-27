# GdUnitTestSuite
extends GdUnitTestSuite

## ECSObserver : every reactive axis
##
## &covers -> ADDED | REMOVED | CHANGED | MATCH | UNMATCH | EVENT
## &isolate -> own ECSWorld + ECSObserverCenter per test, not the Ecs autoload
##             -> no leak between tests, order independent

var _world: ECSWorld
var _center: ECSObserverCenter
var _log: Array[String]


class Probe extends ECSObserver:
	var sink: Array[String]
	var build: Callable

	func _init(target: Array[String], query_builder: Callable) -> void:
		sink = target
		build = query_builder

	func query() -> ECSObserverQuery:
		return build.call(q)

	func each(event: int, entity: ECSEntity, payload: Variant) -> void:
		var who: String = str(entity.id()) if entity else "-"
		sink.append("%s(%s,%s)" % [ECSObserver.Event.keys()[event], who, payload])


func before_test() -> void:
	_world = ECSWorld.new()
	_center = ECSObserverCenter.new(_world)
	_log = [] as Array[String]


func after_test() -> void:
	_world.clear()


## &probe -> register(query_builder(q)) ; q is a fresh ECSObserverQuery
func _observe(query_builder: Callable) -> Probe:
	var probe := auto_free(Probe.new(_log, query_builder)) as Probe
	_center.register(probe)
	return probe


## &drain -> take + clear everything the probes recorded, but could be an issue with draining , i still have to check.
func _drain() -> Array[String]:
	var got := _log.duplicate()
	_log.clear()
	return got


# ---- &axes : component add / remove / change ----

func test_added_fires_only_once_the_whole_query_is_satisfied() -> void:
	_observe(func(q): return q.with([CPlayer, CHealth]).on_added([CHealth]))
	var e := _world.create_entity()

	e.add(CHealth.new(100))
	assert_array(_drain()).is_empty()

	e.add(CPlayer.new())
	# &why -> ADDED reports a component arriving, not a query going green
	assert_array(_drain()).is_empty()

	var other := _world.create_entity()
	other.add(CPlayer.new())
	other.add(CHealth.new(50))
	assert_array(_drain()).contains_exactly(["ADDED(%d,component:CHealth)" % other.id()])


func test_removed_carries_the_component_that_left() -> void:
	_observe(func(q): return q.with([CHealth]).on_removed([CHealth]))
	var e := _world.create_entity()
	e.add(CHealth.new(10))
	_drain()

	e.remove(CHealth)
	assert_array(_drain()).contains_exactly(["REMOVED(%d,component:CHealth)" % e.id()])


func test_changed_fires_on_data_component_writes() -> void:
	_observe(func(q): return q.with([CHealth]).on_changed([CHealth]))
	var e := _world.create_entity()
	var health := CHealth.new(100)
	e.add(health)
	_drain()

	health.set_data(80)
	health.set_data(60)
	assert_array(_drain()).contains_exactly([
		"CHANGED(%d,80)" % e.id(),
		"CHANGED(%d,60)" % e.id(),
	])


func test_changed_is_silent_for_a_plain_component() -> void:
	# &why -> plain ECSComponent has no change signal; only set_data() is tracked
	#         -> a silent field write by design, so on_changed can never see it
	_observe(func(q): return q.with([CPlayer]).on_changed([CPlayer]))
	var e := _world.create_entity()
	e.add(CPlayer.new())
	assert_array(_drain()).is_empty()


# ---- &axes : query match / unmatch ----

func test_match_and_unmatch_track_query_edges() -> void:
	_observe(func(q): return q.with([CPlayer, CHealth]).without([CDead]).on_match().on_unmatch())
	var e := _world.create_entity()

	e.add(CPlayer.new())
	assert_array(_drain()).is_empty()

	e.add(CHealth.new(100))
	assert_array(_drain()).contains_exactly(["MATCH(%d,<null>)" % e.id()])

	e.add(CDead.new())
	assert_array(_drain()).contains_exactly(["UNMATCH(%d,<null>)" % e.id()])

	e.remove(CDead)
	assert_array(_drain()).contains_exactly(["MATCH(%d,<null>)" % e.id()])


func test_changed_is_suppressed_while_the_entity_is_unmatched() -> void:
	_observe(func(q): return q.with([CHealth]).without([CDead]).on_changed([CHealth]))
	var e := _world.create_entity()
	var health := CHealth.new(100)
	e.add(health)
	e.add(CDead.new())
	_drain()

	health.set_data(0)
	assert_array(_drain()).is_empty()


func test_registering_late_does_not_replay_existing_entities_as_matches() -> void:
	var e := _world.create_entity()
	e.add(CPlayer.new())
	e.add(CHealth.new(100))

	_observe(func(q): return q.with([CPlayer, CHealth]).on_match().on_unmatch())
	assert_array(_drain()).is_empty()

	# &why -> seeded as already-matching, so the next edge is real, not a phantom MATCH
	e.remove(CHealth)
	assert_array(_drain()).contains_exactly(["UNMATCH(%d,<null>)" % e.id()])


func test_destroying_an_entity_unmatches_then_reports_the_component_gone() -> void:
	_observe(func(q): return q.with([CPlayer, CHealth]).on_removed([CHealth]).on_unmatch())
	var e := _world.create_entity()
	e.add(CPlayer.new())
	e.add(CHealth.new(100))
	_drain()

	# &why -> remove_all_components() walks insertion order; CPlayer unmatches
	#         before CHealth, the component we watch, is reached
	var id := e.id()
	e.destroy()
	assert_array(_drain()).contains_exactly([
		"UNMATCH(%d,<null>)" % id,
		"REMOVED(%d,component:CHealth)" % id,
	])


# ---- &axes : world event bus ----

func test_bus_events_reach_an_on_event_query() -> void:
	_observe(func(q): return q.on_event(GameEvents.SCORE_CHANGED))
	_world.notify(GameEvents.SCORE_CHANGED, {"score": 7})
	assert_array(_drain()).contains_exactly(['EVENT(-,{ "score": 7 })'])


func test_every_observer_on_one_event_is_notified() -> void:
	# &regression -> Godot 4.7 Callable eq ignores bound args:
	#                `f.bind(a) == f.bind(b)` is true
	#             -> GameEventCenter's is_connected() guard dropped every binding
	#                after the first; center now uses one relay per event name
	_observe(func(q): return q.on_event(GameEvents.RUN_OVER))
	_observe(func(q): return q.on_event(GameEvents.RUN_OVER))
	_world.notify(GameEvents.RUN_OVER, {"win": true})
	assert_array(_drain()).has_size(2)


func test_one_observer_can_bind_several_events_to_different_handlers() -> void:
	var probe := auto_free(MultiProbe.new(_log)) as MultiProbe
	_center.register(probe)

	_world.notify(GameEvents.SCORE_CHANGED, {"score": 1})
	_world.notify(GameEvents.RUN_OVER, {})
	assert_array(_drain()).contains_exactly(["score:1", "over"])


class MultiProbe extends ECSObserver:
	var sink: Array[String]

	func _init(target: Array[String]) -> void:
		sink = target

	func sub_observers() -> Array[Array]:
		return [
			[q.on_event(GameEvents.SCORE_CHANGED), _on_score],
			[q.on_event(GameEvents.RUN_OVER), _on_over],
		]

	func _on_score(_event: int, _entity: ECSEntity, payload: Variant) -> void:
		sink.append("score:%d" % payload.get("score", -1))

	func _on_over(_event: int, _entity: ECSEntity, _payload: Variant) -> void:
		sink.append("over")


# ---- &lifecycle : active | unregister | relays ----

func test_an_inactive_observer_receives_nothing() -> void:
	var probe := _observe(func(q): return q.with([CHealth]).on_changed([CHealth]))
	var e := _world.create_entity()
	var health := CHealth.new(100)
	e.add(health)
	_drain()

	probe.active = false
	health.set_data(50)
	assert_array(_drain()).is_empty()

	probe.active = true
	health.set_data(25)
	assert_array(_drain()).contains_exactly(["CHANGED(%d,25)" % e.id()])


func test_unregister_stops_delivery_and_releases_the_relay() -> void:
	var probe := _observe(func(q): return q.on_event(GameEvents.SCORE_CHANGED))
	_world.notify(GameEvents.SCORE_CHANGED, {"score": 1})
	assert_array(_drain()).has_size(1)

	_center.unregister(probe)
	_world.notify(GameEvents.SCORE_CHANGED, {"score": 2})
	assert_array(_drain()).is_empty()
	assert_bool(_center._bus_relays.has(GameEvents.SCORE_CHANGED)).is_false()


func test_a_relay_survives_while_another_observer_still_wants_it() -> void:
	var first := _observe(func(q): return q.on_event(GameEvents.SCORE_CHANGED))
	_observe(func(q): return q.on_event(GameEvents.SCORE_CHANGED))

	_center.unregister(first)
	assert_bool(_center._bus_relays.has(GameEvents.SCORE_CHANGED)).is_true()
	_world.notify(GameEvents.SCORE_CHANGED, {"score": 3})
	assert_array(_drain()).has_size(1)
