extends Node
class_name ECSObserver

## ECSObserver : query-driven reactive node
##
## godot-ecs ships [ECSSystem], which polls, and GameEventCenter, which is a flat
## bus. Neither reacts to a query.
##
## [codeblock]
## func query() -> ECSObserverQuery:
##     return q.with([CHealth]).on_added().on_removed()
##
## func each(event: int, entity: ECSEntity, payload: Variant) -> void:
##     match event:
##         Event.ADDED:   print("gained ", payload)
##         Event.REMOVED: print("lost on ", entity)
## [/codeblock]


enum Event {
	ADDED = 0,    ## watched component added
	REMOVED = 1,  ## watched component removed
	CHANGED = 2,  ## watched [ECSDataComponent] value changed
	MATCH = 3,    ## entity newly satisfies the query
	UNMATCH = 4,  ## entity no longer satisfies the query
	EVENT = 5,    ## named event on the world bus
}


@export var active: bool = true

var _world: ECSWorld = null

## A fresh query on every access, so two sub-observers can never share state.
var q: ECSObserverQuery:
	get:
		return ECSObserverQuery.new(_world) if _world else null


func world() -> ECSWorld:
	return _world

# ---- overrides ----

## Null when using [method sub_observers] instead.
func query() -> ECSObserverQuery:
	return null

## Several [query, callable] pairs, for an observer watching more than one axis.
func sub_observers() -> Array[Array]:
	return []

## [param _payload] is the component on ADDED and REMOVED, the value on CHANGED,
## the dispatched value on EVENT, and null on MATCH and UNMATCH.
func each(_event: int, _entity: ECSEntity, _payload: Variant) -> void:
	pass

# ---- internals ----

func _set_world(w: ECSWorld) -> void:
	_world = w


func _collect_bindings() -> Array[Array]:
	var subs := sub_observers()
	if not subs.is_empty():
		return subs
	var single := query()
	if single == null:
		push_warning("%s declares neither query() nor sub_observers()." % self)
		return []
	return [[single, each]] as Array[Array]
