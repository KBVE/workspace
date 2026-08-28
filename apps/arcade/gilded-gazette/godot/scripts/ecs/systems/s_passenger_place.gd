extends ECSSystem
class_name SPassengerPlace

## SPassengerPlace walks every passenger to where their authored timeline says
## they are. This is the truth; what they CLAIM is prose in their `alibi` section,
## and the two disagreeing is the game.
##
## Pure data, no nodes: the first promotion to [ECSParallel] once the cast is
## large enough to pay for the dispatch. Eight is not.

const MINUTES_PER_DAY := 1440

## Journey start, so boarding times can be measured as an offset from it rather
## than compared against a wall clock that wraps past midnight.
var departure_minutes: int = 0

## Who did it, drawn per run by [Session] and known to nothing else. Empty until a run
## begins, which is what keeps the tests below honest about the authored timelines.
##
## The draw moves exactly one passenger's TRUTH: for the length of the murder they were
## in the compartment, whatever their timeline says, and afterwards they are back on it.
## Nothing about their prose changes, because their alibi was already only a claim -- so
## the run's culprit is the one passenger the player can catch somewhere their own words
## deny. That is the whole deduction, and it is why the answer can be drawn rather than
## written.
var culprit: StringName = &""

## How long the culprit is at the scene, either side of the minute it happened. Long
## enough that a player walking the train at the hour can find them there, short enough
## that they are not simply living in the wrong room all night.
const AT_THE_SCENE_MINUTES := 10

func _on_update(_delta: float) -> void:
	var clocks: Array = view(&"CTimeOfDay")
	if clocks.is_empty():
		return
	var minutes: int = clocks[0].minutes_past_midnight
	var elapsed := _since_departure(minutes)

	for entry: Dictionary in multi_view([CPassenger, CIdentity, CLocation]):
		var passenger := GameContent.by_id("passengers", entry[&"CIdentity"].content_id)
		if passenger.is_empty():
			continue
		# The victim's timeline is the only one that means something by ending. Past its
		# last step he is not somewhere else, he is where he was left.
		#
		# Posture is asked for rather than required, the way the errand below is: this
		# system places people, and a passenger with no rig to pose is still somewhere.
		# Requiring it would quietly stop placing anyone who lacked one.
		# Where they really were, which for one of them tonight is not where their
		# timeline says. Checked before the timeline and after the errand: a conductor
		# on his rounds is still the conductor, right up until the ten minutes he was
		# not on them.
		if _at_the_scene(entry[&"CIdentity"].content_id, elapsed):
			entry[&"CLocation"].location_id = _scene_of_the_murder()
			continue
		if _is_over(passenger, elapsed):
			var posture: CPosture = entry["entity"].getc(CPosture) as CPosture
			if posture != null:
				posture.dead = true
			entry[&"CLocation"].location_id = _last_where(passenger)
			continue
		# Anybody walking rounds is somewhere because they walked there, and saying
		# otherwise would teleport the conductor back up the train mid-stride.
		var errand: CErrand = entry["entity"].getc(CErrand) as CErrand
		if errand != null and not errand.beat.is_empty():
			continue
		entry[&"CLocation"].location_id = _where(passenger, minutes, elapsed)


## Before their boarding time a passenger is not on the train at all. Without
## this, where_was() reads a clock earlier than their first timeline step as the
## following day: Lady Beaumont sat in her cabin two hours before she boarded.
func _where(passenger: Dictionary, minutes: int, elapsed: int) -> StringName:
	var boarded: Dictionary = passenger.get("boarded", {})
	if boarded.has("at") and elapsed < _since_departure(_minutes_of(boarded["at"])):
		return &""
	return StringName(GameContent.where_was(passenger, minutes))


## Whether this is the drawn culprit, inside the window it happened in.
func _at_the_scene(content_id: StringName, elapsed: int) -> bool:
	if culprit.is_empty() or content_id != culprit:
		return false
	var moment := _moment_of_the_murder()
	if moment < 0:
		return false
	return absi(elapsed - moment) <= AT_THE_SCENE_MINUTES


## The minute it happened and the room it happened in, both read off the victim rather
## than written down here: the body is the only authority on either, and a victim whose
## last step moved would otherwise leave the culprit standing in the wrong empty room.
func _victim_last_step() -> Dictionary:
	for passenger: Dictionary in GameContent.passengers():
		if not passenger.get("victim", false):
			continue
		var steps: Array = passenger.get("timeline", [])
		if steps.is_empty():
			return {}
		return steps[steps.size() - 1]
	return {}


func _moment_of_the_murder() -> int:
	var step := _victim_last_step()
	if step.is_empty():
		return -1
	return _since_departure(_minutes_of(step.get("at", "00:00")))


func _scene_of_the_murder() -> StringName:
	return StringName(_victim_last_step().get("where", ""))


## Whether this passenger's timeline has run out, which only a victim's does. Everyone
## else simply stays wherever their last step put them and goes on being a person there.
func _is_over(passenger: Dictionary, elapsed: int) -> bool:
	if not passenger.get("victim", false):
		return false
	var steps: Array = passenger.get("timeline", [])
	if steps.is_empty():
		return false
	var last: Dictionary = steps[steps.size() - 1]
	return elapsed >= _since_departure(_minutes_of(last.get("at", "00:00")))


func _last_where(passenger: Dictionary) -> StringName:
	var steps: Array = passenger.get("timeline", [])
	if steps.is_empty():
		return &""
	return StringName(steps[steps.size() - 1].get("where", ""))


## Minutes travelled since departure. The journey is linear even though the
## clock it is told in wraps.
func _since_departure(minutes: int) -> int:
	return posmod(minutes - departure_minutes, MINUTES_PER_DAY)


func _minutes_of(hhmm: String) -> int:
	var parts := hhmm.split(":")
	return int(parts[0]) * 60 + (int(parts[1]) if parts.size() > 1 else 0)
