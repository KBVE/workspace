extends ECSSystem
class_name SPassengerPlace

## SPassengerPlace walks every passenger to where the night says they are.
##
## The night is drawn, not authored: [TheNight] places everybody consistently with
## their own claims and exactly one passenger somewhere their claims deny. This is the
## truth; what they CLAIM is prose in their `alibi` section, and the two disagreeing is
## the game.
##
## Pure data, no nodes: the first promotion to [ECSParallel] once the cast is large
## enough to pay for the dispatch. Eight is not.

const MINUTES_PER_DAY := 1440

## Journey start, so the night can be measured as an offset from it rather than compared
## against a wall clock that wraps past midnight.
var departure_minutes: int = 0

## This run's arrangement of the evening. Null until [Session] begins a run, and with no
## night there is nothing to place anybody by, so nobody moves.
var night: TheNight = null


func _on_update(_delta: float) -> void:
	if night == null:
		return
	var clocks: Array = view(&"CTimeOfDay")
	if clocks.is_empty():
		return
	var elapsed := _since_departure(clocks[0].minutes_past_midnight)

	for entry: Dictionary in multi_view([CPassenger, CIdentity, CLocation]):
		var who: StringName = entry[&"CIdentity"].content_id
		# Anybody walking rounds is somewhere because they walked there, and saying
		# otherwise would teleport the conductor back up the train mid-stride.
		var errand: CErrand = entry["entity"].getc(CErrand) as CErrand
		if errand != null and not errand.beat.is_empty():
			continue
		entry[&"CLocation"].location_id = night.where_is(who, elapsed)
		if not night.is_over(who, elapsed):
			continue
		# Posture is asked for rather than required, the way the errand above is: this
		# system places people, and a passenger with no rig to pose is still somewhere.
		var posture: CPosture = entry["entity"].getc(CPosture) as CPosture
		if posture != null:
			posture.dead = true


## Minutes travelled since departure. The journey is linear even though the clock it is
## told in wraps.
func _since_departure(minutes: int) -> int:
	return posmod(minutes - departure_minutes, MINUTES_PER_DAY)
