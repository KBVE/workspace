class_name TheNight

## One run's arrangement of the evening: where every passenger actually was, half hour
## by half hour, who it happened to, who did it, with what, and in which room.
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

## What it was done with. Drawn from the weapons the run is able to put in a room and
## from no others: a weapon with no model cannot be found aboard, and an answer nobody
## can find is a fifth of the accusation decided by luck.
var weapon_id: StringName = &""

## Minutes after departure, not a wall clock: the journey is linear and the clock it is
## told in wraps past midnight. Before nought nobody is anywhere -- the train has not
## left, and a step index clamped to zero would put the Paris boarders on a platform
## they had not reached yet.
var murder_elapsed: int = -1

## content_id -> Array of room per step, indexed by step. An empty room means not yet
## aboard, or no longer anywhere.
var _rooms: Dictionary = {}
var _notes: Dictionary = {}

## content_id -> the alibi this run drew for them, as it appears in their `alibis`.
## What they say changes per run, so nothing may read `claims` off the content: the
## content holds every account they might have given and this holds the one they did.
var _alibis: Dictionary = {}


## Every weapon the run could name, which is every weapon it could also put in a room.
##
## The model is the qualification, not the kind. A weapon with no model is real content
## -- somebody owns it, it has a page -- but nothing can place it aboard, so a player
## has no way to find it and naming it would be a guess between things they never saw.
## The notebook draws its own column from this same rule, so what is listed and what
## can be drawn are one set, the way the suspects are.
static func weapons() -> Array[StringName]:
	var out: Array[StringName] = []
	for item: Dictionary in GameContent.items():
		if item.get("kind", "") == "weapon" and str(item.get("model", "")) != "":
			out.append(StringName(item.get("id", "")))
	out.sort()
	return out


## What this passenger told the enquiry this run, as the `says` lines they gave.
func says_of(id: StringName) -> Array:
	return _alibis.get(id, {}).get("says", [])


## What that account would mean if it were true, which is what the night is placed
## against. Never read `claims` off [GameContent]: that is every account they might
## have given, and this is the one they did.
func claims_of(id: StringName) -> Array:
	return _alibis.get(id, {}).get("claims", [])


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

	# Who it happened to is drawn like everything else. It used to be a flag in the
	# content, which made every run the same murder with a different murderer: the
	# same berth, the same gap in the register, the same evening reframed around one
	# man. Drawing it means the question the enquiry opens with changes too.
	var aboard: Array[StringName] = []
	for id: StringName in cast:
		aboard.append(id)
	aboard.sort()
	if aboard.size() < 2:
		return false
	victim_id = aboard[rng.randi_range(0, aboard.size() - 1)]

	# What each of them says, drawn before anything is worked out from it. A fixed
	# alibi makes every night the same deduction with a different answer -- the same
	# people are catchable and the same people are not, whoever did it -- so the
	# reasoning was identical across runs even when the culprit was not.
	for id: StringName in aboard:
		var bank: Array = cast[id].get("alibis", [])
		if bank.is_empty():
			return false
		_alibis[id] = bank[rng.randi_range(0, bank.size() - 1)]

	var arsenal := weapons()
	if arsenal.is_empty():
		return false
	weapon_id = arsenal[rng.randi_range(0, arsenal.size() - 1)]

	# The culprit is drawn before the hour is, and this order is the whole of the
	# fairness. Drawing the hour first and then taking whoever it left catchable
	# hands the choosing to candidacy: a passenger claiming one room all evening is
	# catchable in every hour of it, one claiming a narrow window is catchable in
	# few, and the second is then hardly ever the answer. Measured over two thousand
	# nights that ran 565 to 54 between the widest and the narrowest alibi, which is
	# a cast the experienced player stops considering.
	#
	# Picking the person first and fitting the hour to them costs a search over
	# twenty-odd half hours and makes every suspect equally likely, which is what
	# the notebook promises by listing them.
	var suspects: Array[StringName] = []
	for id: StringName in aboard:
		if id != victim_id:
			suspects.append(id)
	suspects.shuffle()

	for who: StringName in suspects:
		# Every hour and room that would catch this one in a lie, gathered before any
		# of it is chosen so the pick is uniform over the openings rather than over
		# the hours that happen to have one.
		var openings: Array[Dictionary] = []
		for elapsed in range(EARLIEST, LATEST + 1):
			var step := _step_of(elapsed)
			for room: StringName in _rooms_that_would_be_a_lie(cast[who], cast[victim_id],
					step, departure_minutes, who, victim_id):
				openings.append({"elapsed": elapsed, "room": room})
		if openings.is_empty():
			continue
		var chosen: Dictionary = openings[rng.randi_range(0, openings.size() - 1)]
		culprit_id = who
		murder_elapsed = int(chosen["elapsed"])
		scene = chosen["room"]
		break

	if culprit_id.is_empty():
		return false
	var murder_step := _step_of(murder_elapsed)

	for id: StringName in cast:
		_walk(rng, id, cast[id], departure_minutes, murder_step)
	return true


## Rooms both of them have a line for, where being there at [param step] contradicts
## what the first of them says. The victim's own sightings matter because the scene is
## a room he could have been found in, not merely one the culprit could have reached.
func _rooms_that_would_be_a_lie(who: Dictionary, victim: Dictionary, step: int,
		departure_minutes: int, who_id: StringName, victim_who: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	var theirs: Dictionary = victim.get("sightings", {})
	for room: String in who.get("sightings", {}):
		var where := StringName(room)
		if where == BOARDING_ONLY or not theirs.has(room):
			continue
		# The victim has to be able to be there honestly. Exactly one person's word
		# fails in a night, and it is the culprit's -- if the scene were a room the
		# victim's own claims denied, the body would be found somewhere it had sworn
		# it was not, and a second contradiction is a second answer to the question
		# the whole deduction asks.
		#
		# It cost nothing while the victim was authored, because that one passenger
		# was written with no claims to break. Drawing the body is what made every
		# passenger's alibi somebody's alibi.
		if not _allows_claims(claims_of(victim_who), where, step, departure_minutes):
			continue
		if not _allows_claims(claims_of(who_id), where, step, departure_minutes):
			found.append(where)
	return found


## Whether this passenger's own claims leave them free to be in [param where] at
## [param step]. A never claim closes a room for the whole journey; a window claim
## closes every other room for its length.
func _allows_claims(claims: Array, where: StringName, step: int,
		departure_minutes: int) -> bool:
	# Nobody's alibi is about the platform. Everybody was demonstrably on it, in front of
	# a guard with a register, and a claim to have been elsewhere at boarding would be
	# a claim about the one moment of the evening nobody disputes.
	if where == BOARDING_ONLY:
		return true
	for claim: Dictionary in claims:
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
			var open := _open_rooms(id, sightings, step, departure_minutes)
			if open.is_empty():
				here = here
			elif not open.has(here) or rng.randf() < 0.35:
				here = open[rng.randi_range(0, open.size() - 1)]
		rooms.append(here)
		notes.append(_a_line_for(rng, sightings, here))
	_rooms[id] = rooms
	_notes[id] = notes


func _open_rooms(who_id: StringName, sightings: Dictionary, step: int,
		departure_minutes: int) -> Array[StringName]:
	var open: Array[StringName] = []
	for room: String in sightings:
		var where := StringName(room)
		if where == BOARDING_ONLY:
			continue
		if _allows_claims(claims_of(who_id), where, step, departure_minutes):
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
