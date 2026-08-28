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
