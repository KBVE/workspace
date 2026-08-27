extends Node

## Journal : what the run remembers
##
## A murder mystery is a record of who did what, in what order. Systems ask the
## journal, not each other: "has the player shown the telegram to Weiss yet" is a
## query, not a flag someone has to remember to set.
## Every entry carries a ULID, so entries sort by creation without trusting a
## clock field, and Godot and React agree on identity.
## `at` is in-world minutes, which is what the player reasons about. It is not
## the ordering key: the world clock scrubs and repeats, so two entries in one
## in-world minute would tie.

const LIMIT := 512

var _entries: Array[Dictionary] = []
var _clock: int = -1

func _ready() -> void:
	Ecs.world.add_callable(GameEvents.WORLD_CLOCK, _on_clock)

func _on_clock(event: GameEvent) -> void:
	var payload: Variant = event.data
	if payload is Dictionary:
		_clock = int(payload.get("hour", 0)) * 60 + int(payload.get("minute", 0))

## Records one fact and returns its id.
## [param actor] and [param target] are content ids (`beaumont`, `telegram`).
func record(kind: int, actor: String = "", target: String = "", place: String = "") -> String:
	var entry := {
		"id": Ulid.generate(),
		"kind": kind,
		"actor": actor,
		"target": target,
		"place": place,
		"at": _clock,
	}
	_entries.append(entry)
	# a run cannot grow without bound in wasm; the oldest facts go first
	if _entries.size() > LIMIT:
		_entries = _entries.slice(_entries.size() - LIMIT)
	Ecs.notify(GameEvents.JOURNAL_ENTRY, entry)
	return entry["id"]

func entries() -> Array[Dictionary]:
	return _entries.duplicate()

## Every entry matching a kind, and optionally an actor and a target.
## An empty string means "any", so callers filter on what they know.
func find_entries(kind: int = -1, actor: String = "", target: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in _entries:
		if kind >= 0 and int(e["kind"]) != kind:
			continue
		if not actor.is_empty() and e["actor"] != actor:
			continue
		if not target.is_empty() and e["target"] != target:
			continue
		out.append(e)
	return out

## The question most systems actually ask.
func has_happened(kind: int, actor: String = "", target: String = "") -> bool:
	return not find_entries(kind, actor, target).is_empty()

## The most recent entry, or {} when the run has done nothing yet.
func last() -> Dictionary:
	return _entries[-1] if not _entries.is_empty() else {}

func clear() -> void:
	_entries.clear()
