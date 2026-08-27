# GdUnitTestSuite
extends GdUnitTestSuite

## godot-ecs @ VENDOR_SHA -> godothub/godot-ecs, MIT
##
## &claims -> every assert is about UPSTREAM, not our code
## &private -> ECSWorld._query_caches ONLY
## &why -> a GodotECS bump breaks HERE, naming the dead assumption
##
## &bump -> recopy upstream, drop test_suite.gd + test_scheduler.gd,
##          bump VENDOR.md; this suite then FAILS until you read it again, huge damn issue here.
##          and move VENDOR_SHA afterwards, need to be careful.

## &pin -> checked against VENDOR.md; a re-vendor cannot inherit a green run
const VENDOR_SHA := "5f3eca675b2db99369048640755682ca41315e5d"
const VENDOR_DOC := "res://addons/GodotECS/VENDOR.md"

var _world: ECSWorld


func before_test() -> void:
	_world = ECSWorld.new()


func after_test() -> void:
	_world.clear()


class CacheSpy extends RefCounted:
	var calls: Array[Array] = []

	func on_component_changed(entity_id: int, name: StringName, is_added: bool) -> void:
		calls.append([entity_id, name, is_added])


# ---- &vendor : the sha these claims were checked against ----

func test_vendored_sha_is_the_one_reviewed() -> void:
	var file := FileAccess.open(VENDOR_DOC, FileAccess.READ)
	assert_object(file).is_not_null()
	assert_str(file.get_as_text()) \
		.override_failure_message(
			"addons/GodotECS was revendored, but this suite still pins %s. "
			% VENDOR_SHA
			+ "Every assertion below is a claim about that exact upstream, probly need to read them again. "
			+ "against the new code, then move VENDOR_SHA but do not just bump it green? I hope, this might be a solid failure point."
		).contains(VENDOR_SHA)


# ---- &private : ECSWorld._query_caches ----

func test_world_still_exposes_the_query_cache_registry() -> void:
	assert_object(_world.get("_query_caches")) \
		.override_failure_message(
			"_query_caches gone -> no component observer fires. "
			+ "Find the new global add/remove hook in world.gd, update _init()."
		).is_not_null()


func test_component_add_and_remove_both_notify_every_query_cache() -> void:
	var spy := CacheSpy.new()
	_world._query_caches[&"@contract_probe"] = spy

	var e := _world.create_entity(7)
	e.add(CHealth.new(10))
	e.remove(CHealth)

	assert_array(spy.calls) \
		.override_failure_message(
			"add/remove no longer notifies query caches -> center cannot find entities."
		).contains_exactly([[7, &"CHealth", true], [7, &"CHealth", false]])


func test_the_cache_hook_runs_before_the_entity_signal() -> void:
	# &why -> center connects signals from inside the hook; hook must run first
	var order: Array[String] = []
	var spy := CacheSpy.new()
	var e := _world.create_entity()
	e.on_component_added.connect(func(_e, _c): order.append("signal"))
	_world._query_caches[&"@contract_probe"] = _wrap(spy, order)

	e.add(CHealth.new(1))
	assert_array(order) \
		.override_failure_message(
			"cache hook now runs after on_component_added -> entities miss their first."
		).contains_exactly(["cache", "signal"])


func _wrap(spy: CacheSpy, order: Array[String]) -> RefCounted:
	var w := OrderSpy.new()
	w.inner = spy
	w.order = order
	return w


class OrderSpy extends RefCounted:
	var inner: RefCounted
	var order: Array[String]

	func on_component_changed(entity_id: int, name: StringName, is_added: bool) -> void:
		order.append("cache")
		inner.on_component_changed(entity_id, name, is_added)


# ---- &public : documented surface ----

func test_entities_are_stable_objects_not_fresh_wrappers() -> void:
	# &why -> signals are per entity, so the instance must be stable
	var e := _world.create_entity(42)
	assert_object(_world.get_entity(42)) \
		.override_failure_message("ECSEntity wrappers no longer stable per id.") \
		.is_same(e)


func test_remove_component_signal_still_carries_the_component() -> void:
	# &why -> hook fires after removal, so REMOVED payloads come from this signal
	var seen: Array[ECSComponent] = []
	var e := _world.create_entity()
	e.on_component_removed.connect(func(_e, c): seen.append(c))
	var health := CHealth.new(5)
	e.add(health)
	e.remove(CHealth)

	assert_array(seen).has_size(1)
	assert_object(seen[0]).is_same(health)


func test_destroying_an_entity_removes_its_components_one_by_one() -> void:
	var removed: Array[StringName] = []
	var e := _world.create_entity()
	e.on_component_removed.connect(func(_e, c): removed.append(c.name()))
	e.add(CPlayer.new())
	e.add(CHealth.new(1))
	e.destroy()

	assert_array(removed) \
		.override_failure_message("destroy() -> no per-component removals.") \
		.contains_exactly([&"CPlayer", &"CHealth"])


func test_data_components_still_announce_writes() -> void:
	var seen: Array[Variant] = []
	var health := CHealth.new(100)
	_world.create_entity().add(health)
	health.on_data_changed.connect(func(_s, d): seen.append(d))

	health.set_data(50)
	assert_array(seen) \
		.override_failure_message(
			"ECSDataComponent.on_data_changed is gone!!! on_changed() observers depend on it."
		).contains_exactly([50])


func test_the_event_bus_delivers_a_game_event_object() -> void:
	var seen: Array[GameEvent] = []
	_world.add_callable(&"contract_probe", func(e: GameEvent): seen.append(e))
	_world.notify(&"contract_probe", {"n": 1})

	assert_array(seen).has_size(1)
	assert_str(seen[0].name).is_equal("contract_probe")
	assert_dict(seen[0].data).is_equal({"n": 1})


func test_remove_callable_actually_unsubscribes() -> void:
	var count := [0]
	var cb := func(_e: GameEvent): count[0] += 1
	_world.add_callable(&"contract_probe", cb)
	_world.notify(&"contract_probe", null)
	_world.remove_callable(&"contract_probe", cb)
	_world.notify(&"contract_probe", null)

	assert_int(count[0]) \
		.override_failure_message("remove_callable no longer unsubscribes -> relays leak.") \
		.is_equal(1)
