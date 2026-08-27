extends RefCounted
class_name ECSObserverCenter

## ECSObserverCenter : dispatch engine behind [ECSObserver]
##
## godot-ecs exposes its add/remove hook to query caches only, so this squats
## [constant HOOK_KEY] in the cache table to hook entity signals on their first
## component. That runs before the entity emits, so nothing is missed.
##
## Dispatch comes from the entity signals, not the hook: only they carry the
## component instance on removal.

## Not a valid component-set key, so it cannot collide with a real query.
const HOOK_KEY := &"@observers"

class Binding extends RefCounted:
	var observer: ECSObserver
	var query: ECSObserverQuery
	var callback: Callable
	var matched: Dictionary = {}

	func alive() -> bool:
		return is_instance_valid(observer) and observer.active

## A duck-typed query cache that holds no results.
class EntityHook extends RefCounted:
	var center: WeakRef

	func on_component_changed(entity_id: int, _name: StringName, _is_added: bool) -> void:
		var c: ECSObserverCenter = center.get_ref()
		if c:
			c._ensure_entity_hooked(entity_id)

## One per event name, because Godot 4.7 Callable equality ignores bound args:
## f.bind(a) == f.bind(b). GameEventCenter guards with is_connected(), so a bound
## Callable connects once and silently drops the rest. A distinct object dodges it.
class BusRelay extends RefCounted:
	var center: WeakRef
	var event_name: StringName

	func receive(event: GameEvent) -> void:
		var c: ECSObserverCenter = center.get_ref()
		if c:
			c._on_bus_event(event, event_name)

var _world: ECSWorld
var _bindings: Array[Binding] = []
var _hooked_entities: Dictionary = {}
var _bus_relays: Dictionary[StringName, BusRelay] = {}
var _main_thread_id: int = OS.get_main_thread_id()

func _init(world: ECSWorld) -> void:
	_world = world
	var hook := EntityHook.new()
	hook.center = weakref(self)
	# the only reach into godot-ecs internals; pinned by godot_ecs_contract_test
	var caches: Variant = _world.get("_query_caches")
	if caches == null:
		push_error(
			"ECSObserverCenter: ECSWorld has no _query_caches. The vendored godot-ecs "
			+ "changed - component observers will not fire. See addons/GodotECS/VENDOR.md."
		)
		return
	caches[HOOK_KEY] = hook

# ---- registration ----

## Safe to call before or after the observer's entities exist.
func register(observer: ECSObserver) -> void:
	observer._set_world(_world)
	for pair: Array in observer._collect_bindings():
		if pair.size() != 2:
			push_warning("%s: sub_observers() entries must be [query, callable]." % observer)
			continue
		var binding := Binding.new()
		binding.observer = observer
		binding.query = pair[0]
		binding.callback = pair[1]
		if binding.query == null or not binding.callback.is_valid():
			push_warning("%s: skipping a malformed observer binding." % observer)
			continue
		_bindings.append(binding)
		_seed_matched(binding)
		_connect_bus(binding)

func unregister(observer: ECSObserver) -> void:
	var kept: Array[Binding] = []
	var orphaned: Array[StringName] = []
	for binding: Binding in _bindings:
		if binding.observer != observer:
			kept.append(binding)
			continue
		for event_name: StringName in binding.query.event_names:
			if not orphaned.has(event_name):
				orphaned.append(event_name)
	# swap first; _prune_relays reads _bindings after the removal
	_bindings = kept
	_prune_relays(orphaned)

# ---- hooks : world -> center ----

func _ensure_entity_hooked(entity_id: int) -> void:
	if _hooked_entities.has(entity_id):
		return
	var entity := _world.get_entity(entity_id)
	if entity == null:
		return
	_hooked_entities[entity_id] = true
	entity.on_component_added.connect(_on_component_added)
	entity.on_component_removed.connect(_on_component_removed)

func _on_component_added(entity: ECSEntity, component: ECSComponent) -> void:
	var name := component.name()
	for binding: Binding in _bindings:
		if not binding.alive() or not binding.query.touches(name):
			continue
		if binding.query.wants(ECSObserver.Event.ADDED) \
				and binding.query.watch_names.has(name) \
				and binding.query.matches(entity.id()):
			_dispatch(binding, ECSObserver.Event.ADDED, entity, component)
		_refresh_match(binding, entity)
	if component is ECSDataComponent and _anyone_watches_changes(name):
		if not component.on_data_changed.is_connected(_on_data_changed):
			component.on_data_changed.connect(_on_data_changed)

func _on_component_removed(entity: ECSEntity, component: ECSComponent) -> void:
	var name := component.name()
	if component is ECSDataComponent and component.on_data_changed.is_connected(_on_data_changed):
		component.on_data_changed.disconnect(_on_data_changed)
	for binding: Binding in _bindings:
		if not binding.alive() or not binding.query.touches(name):
			continue
		if binding.query.wants(ECSObserver.Event.REMOVED) \
				and binding.query.watch_names.has(name):
			_dispatch(binding, ECSObserver.Event.REMOVED, entity, component)
		_refresh_match(binding, entity)
	if not entity.valid():
		_hooked_entities.erase(entity.id())

func _on_data_changed(sender: ECSDataComponent, data: Variant) -> void:
	var entity := sender.entity()
	if entity == null:
		return
	var name := sender.name()
	for binding: Binding in _bindings:
		if not binding.alive() or not binding.query.wants(ECSObserver.Event.CHANGED):
			continue
		if not binding.query.watch_names.has(name) or not binding.query.matches(entity.id()):
			continue
		_dispatch(binding, ECSObserver.Event.CHANGED, entity, data)

func _on_bus_event(event: GameEvent, event_name: StringName) -> void:
	for binding: Binding in _bindings:
		if binding.alive() and binding.query.event_names.has(event_name):
			_dispatch(binding, ECSObserver.Event.EVENT, null, event.data)

# ---- internals ----

## Fires only on the edge, never on a change that keeps the same side.
func _refresh_match(binding: Binding, entity: ECSEntity) -> void:
	if not (binding.query.wants(ECSObserver.Event.MATCH) or binding.query.wants(ECSObserver.Event.UNMATCH)):
		return
	var id := entity.id()
	var was: bool = binding.matched.has(id)
	var now: bool = entity.valid() and binding.query.matches(id)
	if now == was:
		return
	if now:
		binding.matched[id] = true
		if binding.query.wants(ECSObserver.Event.MATCH):
			_dispatch(binding, ECSObserver.Event.MATCH, entity, null)
	else:
		binding.matched.erase(id)
		if binding.query.wants(ECSObserver.Event.UNMATCH):
			_dispatch(binding, ECSObserver.Event.UNMATCH, entity, null)

## Late registration replays nothing.
func _seed_matched(binding: Binding) -> void:
	if not (binding.query.wants(ECSObserver.Event.MATCH) or binding.query.wants(ECSObserver.Event.UNMATCH)):
		return
	for id: int in _world.get_entity_keys():
		if binding.query.matches(id):
			binding.matched[id] = true

func _connect_bus(binding: Binding) -> void:
	if not binding.query.wants(ECSObserver.Event.EVENT):
		return
	for event_name: StringName in binding.query.event_names:
		if _bus_relays.has(event_name):
			continue
		var relay := BusRelay.new()
		relay.center = weakref(self)
		relay.event_name = event_name
		_bus_relays[event_name] = relay
		_world.add_callable(event_name, relay.receive)

func _prune_relays(event_names: Array[StringName]) -> void:
	for event_name: StringName in event_names:
		if _still_wanted(event_name):
			continue
		var relay: BusRelay = _bus_relays.get(event_name)
		if relay:
			_world.remove_callable(event_name, relay.receive)
			_bus_relays.erase(event_name)

func _still_wanted(event_name: StringName) -> bool:
	for binding: Binding in _bindings:
		if binding.query.event_names.has(event_name):
			return true
	return false

func _anyone_watches_changes(name: StringName) -> bool:
	for binding: Binding in _bindings:
		if binding.query.wants(ECSObserver.Event.CHANGED) and binding.query.watch_names.has(name):
			return true
	return false

## [ECSParallel] runs on [WorkerThreadPool], so notify() can arrive off-main.
## Nodes and JavaScriptBridge are not thread-safe, so defer.
func _dispatch(binding: Binding, event: int, entity: ECSEntity, payload: Variant) -> void:
	if OS.get_thread_caller_id() == _main_thread_id:
		binding.callback.call(event, entity, payload)
	else:
		binding.callback.call_deferred(event, entity, payload)
