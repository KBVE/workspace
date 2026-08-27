extends RefCounted
class_name ECSObserverQuery

## ECSObserverQuery : declarative reactive query
##
## [Querier] answers "who matches now"; this adds "tell me when that changes".
## Build one from [member ECSObserver.q].
##
## [codeblock]
## q.with([CHealth]).on_added().on_removed()
## q.with([CHealth]).on_changed([CHealth])
## q.on_event(GameEvents.SCORE_CHANGED)
## [/codeblock]

var _world: ECSWorld

var with_names: Array[StringName] = []
var without_names: Array[StringName] = []
var watch_names: Array[StringName] = []
var event_names: Array[StringName] = []
var events_mask: int = 0

func _init(world: ECSWorld) -> void:
	_world = world

# ---- filters : which entities ----

func with(keys: Array) -> ECSObserverQuery:
	_resolve_into(keys, with_names)
	return self

func without(keys: Array) -> ECSObserverQuery:
	_resolve_into(keys, without_names)
	return self

# ---- axes : when it fires ----

## Empty [param keys] means everything in [method with].
func on_added(keys: Array = []) -> ECSObserverQuery:
	return _watch(ECSObserver.Event.ADDED, keys)

## Empty [param keys] means everything in [method with].
func on_removed(keys: Array = []) -> ECSObserverQuery:
	return _watch(ECSObserver.Event.REMOVED, keys)

## Only [ECSDataComponent] has a change signal; writes to a plain
## [ECSComponent] are silent and never fire this.
func on_changed(keys: Array = []) -> ECSObserverQuery:
	return _watch(ECSObserver.Event.CHANGED, keys)

func on_match() -> ECSObserverQuery:
	events_mask |= 1 << ECSObserver.Event.MATCH
	return self

func on_unmatch() -> ECSObserverQuery:
	events_mask |= 1 << ECSObserver.Event.UNMATCH
	return self

## The entity is null; only the dispatched value is carried.
func on_event(event_name: StringName) -> ECSObserverQuery:
	if not event_names.has(event_name):
		event_names.append(event_name)
	events_mask |= 1 << ECSObserver.Event.EVENT
	return self

# ---- internals ----

func wants(event: int) -> bool:
	return (events_mask & (1 << event)) != 0


func touches(name: StringName) -> bool:
	return with_names.has(name) or without_names.has(name) or watch_names.has(name)


func matches(entity_id: int) -> bool:
	for n: StringName in with_names:
		if not _world.has_component(entity_id, n):
			return false
	for n: StringName in without_names:
		if _world.has_component(entity_id, n):
			return false
	return true

func _watch(event: int, keys: Array) -> ECSObserverQuery:
	events_mask |= 1 << event
	if keys.is_empty():
		for n: StringName in with_names:
			if not watch_names.has(n):
				watch_names.append(n)
	else:
		_resolve_into(keys, watch_names)
	return self

func _resolve_into(keys: Array, target: Array[StringName]) -> void:
	for k: Variant in keys:
		var n: StringName = _world.resolve_name(k)
		if not n.is_empty() and not target.has(n):
			target.append(n)
