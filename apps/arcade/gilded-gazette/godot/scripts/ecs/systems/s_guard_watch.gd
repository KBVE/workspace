extends ECSSystem
class_name SGuardWatch

## SGuardWatch turns the Order's rota into somewhere for each knight to be.
##
## The duties are a ring: the one who has been on patrol longest comes in and stands
## down to relief, the one on relief takes a post, and the post they take is given up by
## whoever has held it longest, who goes out on patrol. Nobody is scheduled; the ring
## turns and everybody moves up one, which is how a watch has actually been kept for as
## long as there have been watches.
##
## What it writes is [CErrand] and [CLocation], because that is all anything downstream
## reads. A knight on patrol is a character with a beat; a knight on post is a character
## with a short pace in the van. Neither [SCastWalk] nor [SCastBody] knows which is which.

## World minutes a knight holds one duty before the ring turns. Two hours: long enough
## that the swap is an event rather than a carousel, short enough to see one in a night.
const WATCH_MINUTES := 120

## How far a knight on post paces. Short -- they are standing over a crate.
const POST_PACE_METRES := 3.0

## And how far apart the two posts stand, so the pair are either side of the cargo
## rather than treading on each other.
const POST_SPACING_METRES := 4.0

var cargo_location: StringName = &"guard_van"

## The rooms a patrolling knight walks. Handed in rather than worked out, because what
## the train is made of is the train's business.
var rounds: Array[StringName] = []

func _on_update(_delta: float) -> void:
	var clocks: Array = view(&"CTimeOfDay")
	if clocks.is_empty():
		return
	var minutes: int = clocks[0].minutes_past_midnight

	var watch: Array = multi_view([CWatch, CErrand, CLocation])
	if watch.is_empty():
		return
	for entry: Dictionary in watch:
		if entry[&"CWatch"].took_duty_at_minutes < 0:
			entry[&"CWatch"].took_duty_at_minutes = minutes
		_stand_the_duty(entry[&"CWatch"], entry[&"CErrand"], entry[&"CLocation"])
	_turn_the_ring(watch, minutes)


## The duty, made concrete. Rewritten every tick rather than on the swap: a knight whose
## rig was thrown away and rebuilt comes back on the duty they were on, and a beat that
## was only written once would be lost with them.
func _stand_the_duty(watch: CWatch, errand: CErrand, location: CLocation) -> void:
	if watch.duty == CWatch.PATROL:
		if errand.beat != rounds:
			errand.beat = rounds
		return

	if not errand.beat.is_empty():
		# Come in off patrol. The beat is what would otherwise walk them straight back
		# out of the van they have just been posted to.
		errand.beat = []
		errand.beat_index = 0
	location.location_id = cargo_location
	errand.patrol_metres = POST_PACE_METRES if watch.duty == CWatch.POST else 0.0
	errand.station_offset_metres = (watch.post_index - 0.5) * POST_SPACING_METRES \
		if watch.duty == CWatch.POST else 0.0


## Everybody moves up one, oldest duty first. The posts are handed over by seniority as
## well, so the knight who has stood over the crate longest is the one who gets the walk.
func _turn_the_ring(watch: Array, minutes: int) -> void:
	var patrolling := watch.filter(func(entry: Dictionary) -> bool:
		return entry[&"CWatch"].duty == CWatch.PATROL)
	if patrolling.is_empty():
		return
	var out_there: CWatch = patrolling[0][&"CWatch"]
	if _minutes_held(out_there, minutes) < WATCH_MINUTES:
		return

	var resting := watch.filter(func(entry: Dictionary) -> bool:
		return entry[&"CWatch"].duty == CWatch.RELIEF)
	if resting.is_empty():
		return
	var posted := watch.filter(func(entry: Dictionary) -> bool:
		return entry[&"CWatch"].duty == CWatch.POST)
	posted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a[&"CWatch"].took_duty_at_minutes < b[&"CWatch"].took_duty_at_minutes)

	var coming_in: CWatch = resting[0][&"CWatch"]
	_hand_over(out_there, CWatch.RELIEF, 0, minutes)
	if posted.is_empty():
		_hand_over(coming_in, CWatch.PATROL, 0, minutes)
		return
	var longest_posted: CWatch = posted[0][&"CWatch"]
	_hand_over(coming_in, CWatch.POST, longest_posted.post_index, minutes)
	_hand_over(longest_posted, CWatch.PATROL, 0, minutes)


func _hand_over(watch: CWatch, duty: StringName, post_index: int, minutes: int) -> void:
	watch.duty = duty
	watch.post_index = post_index
	watch.took_duty_at_minutes = minutes


## How long they have held it, across a midnight. The journey crosses one, and a watch
## taken at eleven and measured at one is two hours old, not twenty-two.
static func _minutes_held(watch: CWatch, minutes: int) -> int:
	return posmod(minutes - watch.took_duty_at_minutes, 1440)
