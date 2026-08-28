class_name TheNight

## One run's arrangement of the evening: where every passenger actually was, half hour
## by half hour, who it happened to, who did it, and in which room.
##
## Drawn rather than authored, and the reason that is possible without generated prose
## is that an alibi was already only a claim. Everybody is placed consistently with
## their OWN claims; exactly one passenger is placed somewhere their claims forbid, and
## that passenger is the culprit. So the words never change and the truth underneath
## them does, which is the only thing a deduction needs.
##
## The alternative -- placing people freely -- makes liars of them at random. Several
## passengers then contradict themselves for no reason anybody can act on, and
## contradiction stops identifying anyone. A generated mystery is a constraint problem
## before it is a random one.
##
## Pure data, no nodes and no content mutation: [GameContent] stays the authored record
## and this is what one night made of it looks like.

## Half hours. Fine enough that somebody can be caught somewhere for one of them, coarse
## enough that a night is two dozen decisions rather than a thousand.
const STEP_MINUTES := 30

## How long the evening runs for, from departure. Past the last step nobody moves again.
const JOURNEY_MINUTES := 12 * 60

## When it can happen, as minutes after departure. Late enough that the train has
## settled and everybody has an evening behind them to account for.
const EARLIEST := 6 * 60
const LATEST := 9 * 60 + 30

## The platform is where boarding happens and nowhere else: a passenger who wandered
## back onto it halfway to Constantinople would be a bug with a sighting line.
const BOARDING_ONLY := &"platform"

var victim_id: StringName = &""
var culprit_id: StringName = &""
var scene: StringName = &""

## Minutes after departure, not a wall clock: the journey is linear and the clock it is
## told in wraps past midnight. Before nought nobody is anywhere -- the train has not
## left, and a step index clamped to zero would put the Paris boarders on a platform
## they had not reached yet.
var murder_elapsed: int = -1

## content_id -> Array of room per step, indexed by step. An empty room means not yet
## aboard, or no longer anywhere.
var _rooms: Dictionary = {}
var _notes: Dictionary = {}


## Draws a night, or returns null if the content cannot support one -- no victim, or
## nobody who could have done it in a room the two of them could both be in.
static func draw(rng: RandomNumberGenerator, departure_minutes: int) -> TheNight:
	var night := TheNight.new()
	if not night._draw(rng, departure_minutes):
		return null
	return night


## Where this passenger was, [param elapsed] minutes after departure.
func where_is(content_id: StringName, elapsed: int) -> StringName:
	var rooms: Array = _rooms.get(content_id, [])
	if rooms.is_empty() or elapsed < 0:
		return &""
	return rooms[_step_of(elapsed)]


## The authored line for finding them there, or empty when they are nowhere.
func note_for(content_id: StringName, elapsed: int) -> String:
	var notes: Array = _notes.get(content_id, [])
	if notes.is_empty() or elapsed < 0:
		return ""
	return notes[_step_of(elapsed)]


## Whether the body has been left where it was left.
func is_over(content_id: StringName, elapsed: int) -> bool:
	return content_id == victim_id and murder_elapsed >= 0 and elapsed >= murder_elapsed


func steps() -> int:
	return JOURNEY_MINUTES / STEP_MINUTES + 1


func _step_of(elapsed: int) -> int:
	return clampi(int(floor(float(elapsed) / STEP_MINUTES)), 0, steps() - 1)


func _draw(rng: RandomNumberGenerator, departure_minutes: int) -> bool:
	var cast := {}
	for passenger: Dictionary in GameContent.passengers():
		cast[StringName(passenger.get("id", ""))] = passenger
	if cast.is_empty():
		return false

	for id: StringName in cast:
		if cast[id].get("victim", false):
			victim_id = id
	if victim_id.is_empty():
		return false

	murder_elapsed = rng.randi_range(EARLIEST, LATEST)
	var murder_step := _step_of(murder_elapsed)

	# The culprit has to be placeable somewhere their own claims deny, or nothing they
	# said can ever be caught out and the run has no answer a player could reach.
	var candidates: Array[StringName] = []
	for id: StringName in cast:
		if id == victim_id:
			continue
		if not _rooms_that_would_be_a_lie(cast[id], cast[victim_id], murder_step,
				departure_minutes).is_empty():
			candidates.append(id)
	if candidates.is_empty():
		return false
	culprit_id = candidates[rng.randi_range(0, candidates.size() - 1)]
	var lies := _rooms_that_would_be_a_lie(cast[culprit_id], cast[victim_id], murder_step,
		departure_minutes)
	scene = lies[rng.randi_range(0, lies.size() - 1)]

	for id: StringName in cast:
		_walk(rng, id, cast[id], departure_minutes, murder_step)
	return true


## Rooms both of them have a line for, where being there at [param step] contradicts
## what the first of them says. The victim's own sightings matter because the scene is
## a room he could have been found in, not merely one the culprit could have reached.
func _rooms_that_would_be_a_lie(who: Dictionary, victim: Dictionary, step: int,
		departure_minutes: int) -> Array[StringName]:
	var found: Array[StringName] = []
	var theirs: Dictionary = victim.get("sightings", {})
	for room: String in who.get("sightings", {}):
		var where := StringName(room)
		if where == BOARDING_ONLY or not theirs.has(room):
			continue
		if not _allows(who, where, step, departure_minutes):
			found.append(where)
	return found


## Whether this passenger's own claims leave them free to be in [param where] at
## [param step]. A never claim closes a room for the whole journey; a window claim
## closes every other room for its length.
func _allows(who: Dictionary, where: StringName, step: int, departure_minutes: int) -> bool:
	# Nobody's alibi is about the platform. Everybody was demonstrably on it, in front of
	# a guard with a register, and a claim to have been elsewhere at boarding would be
	# a claim about the one moment of the evening nobody disputes.
	if where == BOARDING_ONLY:
		return true
	for claim: Dictionary in who.get("claims", []):
		var claimed := StringName(claim.get("where", ""))
		if claim.get("never", false):
			if claimed == where:
				return false
			continue
		# `until` is exclusive and `from` inclusive, so that two claims meeting at the
		# same hour do not both cover it. Weiss puts himself in his cabin until
		# midnight and in the corridor from midnight; read inclusively that is a man
		# obliged to be in two rooms at once, and no night can be drawn for him.
		var from_step := 0
		var until_step := steps()
		if claim.has("from"):
			from_step = _step_of(_elapsed_of(claim["from"], departure_minutes))
		if claim.has("until"):
			until_step = _step_of(_elapsed_of(claim["until"], departure_minutes))
		if step >= from_step and step < until_step and claimed != where:
			return false
	return true


## One passenger's evening. They stay put unless their claims move them, and take a
## room at random when they are free to: a night where everybody changes room every half
## hour is a train full of people who cannot settle.
func _walk(rng: RandomNumberGenerator, id: StringName, who: Dictionary,
		departure_minutes: int, murder_step: int) -> void:
	var boarding := _step_of(_elapsed_of(str(who.get("boarded", {}).get("at", "00:00")),
		departure_minutes))
	var sightings: Dictionary = who.get("sightings", {})
	var rooms: Array = []
	var notes: Array = []
	var here := &""
	for step in steps():
		if step < boarding:
			rooms.append(&"")
			notes.append("")
			continue
		if step == boarding and sightings.has(String(BOARDING_ONLY)):
			here = BOARDING_ONLY
		elif id == victim_id and step >= murder_step:
			here = scene
		elif id == culprit_id and step == murder_step:
			here = scene
		else:
			var open := _open_rooms(who, sightings, step, departure_minutes)
			if open.is_empty():
				here = here
			elif not open.has(here) or rng.randf() < 0.35:
				here = open[rng.randi_range(0, open.size() - 1)]
		rooms.append(here)
		notes.append(_a_line_for(rng, sightings, here))
	_rooms[id] = rooms
	_notes[id] = notes


func _open_rooms(who: Dictionary, sightings: Dictionary, step: int,
		departure_minutes: int) -> Array[StringName]:
	var open: Array[StringName] = []
	for room: String in sightings:
		var where := StringName(room)
		if where == BOARDING_ONLY:
			continue
		if _allows(who, where, step, departure_minutes):
			open.append(where)
	return open


func _a_line_for(rng: RandomNumberGenerator, sightings: Dictionary,
		where: StringName) -> String:
	if where.is_empty():
		return ""
	var lines: Array = sightings.get(String(where), [])
	if lines.is_empty():
		return ""
	return str(lines[rng.randi_range(0, lines.size() - 1)])


func _elapsed_of(hhmm: String, departure_minutes: int) -> int:
	var parts := hhmm.split(":")
	var minutes := int(parts[0]) * 60 + (int(parts[1]) if parts.size() > 1 else 0)
	return posmod(minutes - departure_minutes, 24 * 60)
