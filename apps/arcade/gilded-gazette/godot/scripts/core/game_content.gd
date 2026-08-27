class_name GameContent

## GameContent : the compiled content, engine side
##
## res://data/content.gen.json is byte-identical to what React reads, both
## compiled from shared/data by tools/gen-content.mjs.
##
## Never edit the generated file. Edit shared/data/**/*.mdx.

const PATH := "res://data/content.gen.json"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		if text.is_empty():
			push_error("GameContent: %s missing; run npm run gen" % PATH)
			return {}
		var parsed: Variant = JSON.parse_string(text)
		_data = parsed if parsed is Dictionary else {}
	return _data

static func articles() -> Array:
	return data().get("articles", [])

static func passengers() -> Array:
	return data().get("passengers", [])

static func items() -> Array:
	return data().get("items", [])

## Every room, the consist in order and then anywhere off the train.
static func locations() -> Array:
	return data().get("locations", [])

## A location with a carriage index is a place in the train at that position,
## which is what [SOccupancy] resolves a world position into. gen-content proves
## the indices run 0..n with no gaps, so this seeds by position without checking.
static func carriage_locations() -> Array:
	var aboard := locations().filter(func(l: Dictionary) -> bool: return l.has("carriage"))
	aboard.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["carriage"]) < int(b["carriage"]))
	return aboard.map(func(l: Dictionary) -> StringName: return StringName(l.get("id", "")))

## What stands in the room at [param carriage], in carriage-local metres.
##
## Keyed by position along the train rather than by room id, because [Consist]
## builds carriages by index and the mdx is what ties the two together.
static func furnishings_at(carriage: int) -> Array:
	for room: Dictionary in locations():
		if room.has("carriage") and int(room["carriage"]) == carriage:
			return room.get("furnishings", [])
	return []

## The sheets posted in the carriage at [param carriage], in carriage-local metres.
##
## Keyed by position along the train for the same reason [method furnishings_at] is:
## [Consist] builds carriages by index, and the mdx is what ties an id to a place.
static func notices_in(carriage: int) -> Array:
	return notices().filter(
		func(n: Dictionary) -> bool: return int(n.get("carriage", -1)) == carriage)


static func notices() -> Array:
	return data().get("notices", [])

static func gazette() -> Dictionary:
	return data().get("gazette", {})

## Returns {} when nothing matches.
static func by_id(collection: String, id: String) -> Dictionary:
	for entry: Dictionary in data().get(collection, []):
		if entry.get("id", "") == id:
			return entry
	return {}

## Their default location, not where they are now.
static func passengers_at(location: String) -> Array:
	return passengers().filter(func(p: Dictionary) -> bool: return p.get("location", "") == location)

## One `##` section of an entry: {heading, paragraphs, bullets}. {} when unwritten.
static func section(entry: Dictionary, key: String) -> Dictionary:
	return entry.get("sections", {}).get(key, {})

## Where a passenger actually was at [param clock], from their timeline. What
## they claim is in the `alibi` section, and the two disagreeing is the game.
##
## The journey crosses midnight, so 00:20 comes after 23:40 even though it is the
## smaller number. Steps are authored in order, so one that moves backwards has
## rolled over to the next day.
static func where_was(passenger: Dictionary, clock: int) -> String:
	var steps: Array = passenger.get("timeline", [])
	if steps.is_empty():
		return ""

	var first := _minutes(steps[0].get("at", "00:00"))
	# a clock reading before the first step belongs to the following morning
	var now := clock + (1440 if clock < first else 0)

	var at := ""
	var prev := -1
	var day := 0
	for step: Dictionary in steps:
		var m := _minutes(step.get("at", "00:00"))
		if prev >= 0 and m < prev:
			day += 1440
		if m + day <= now:
			at = step.get("where", "")
		prev = m
	return at

## By their timelines, not their default location.
static func present_at(location: String, clock: int) -> Array:
	return passengers().filter(
		func(p: Dictionary) -> bool: return where_was(p, clock) == location)

## What a passenger owns, by item.owner.
static func items_of(passenger_id: String) -> Array:
	return items().filter(func(i: Dictionary) -> bool: return i.get("owner", "") == passenger_id)

## The article a moment prints: highest priority whose `when` fits.
## [param clock] is minutes past midnight, or -1 when the clock has not ticked.
static func article_for(level: String, clock: int = -1) -> Dictionary:
	var best: Dictionary = {}
	for a: Dictionary in articles():
		var when: Dictionary = a.get("when", {})
		if when.has("level") and when["level"] != level:
			continue
		if when.get("boot", false) and level != "":
			continue
		if not _in_window(when, clock):
			continue
		if best.is_empty() or int(a.get("priority", 0)) > int(best.get("priority", 0)):
			best = a
	return best

static func _in_window(when: Dictionary, clock: int) -> bool:
	if not when.has("after") and not when.has("before"):
		return true
	if clock < 0:
		return false
	var from := _minutes(when.get("after", "00:00"))
	var to := _minutes(when.get("before", "24:00"))
	if from <= to:
		return clock >= from and clock < to
	return clock >= from or clock < to

static func _minutes(hhmm: String) -> int:
	var parts := hhmm.split(":")
	return int(parts[0]) * 60 + (int(parts[1]) if parts.size() > 1 else 0)
