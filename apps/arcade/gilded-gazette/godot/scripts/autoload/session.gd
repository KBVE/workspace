extends Node

## Session : ECS state that outlives a scene swap.

## The Order's escort, and the watch they came aboard with. Four knights and three
## duties: two over the crate, one walking the train, one off the watch entirely. The
## fourth is what makes it a watch rather than a tableau -- there is somebody to hand a
## duty to. [SGuardWatch] turns the ring.
##
## They are not passengers: no berth, no timeline, no alibi, and nothing in the content
## about them, because they are the image the guard's van is selling rather than anybody
## the mystery turns on. Dame Marchand is the one with a name, and she is content.
##
## The seeds are written down rather than derived so the four of them stay the four of
## them; the faces under the helmets are rolled, the plate is not.
const ESCORT_LOCATION := &"guard_van"
## The duties are written as the bare names [CWatch] uses rather than through it: a
## const cannot be built out of another class's const, and a rota that could not be a
## const would be a rota anybody could edit at runtime.
const ESCORT := [
	{"seed": 0x5eed_0001, "outfit": &"male_knight", "duty": &"post", "post": 0},
	{"seed": 0x5eed_0002, "outfit": &"female_knight", "duty": &"post", "post": 1},
	{"seed": 0x5eed_0003, "outfit": &"male_knight", "duty": &"patrol", "post": 0},
	{"seed": 0x5eed_0004, "outfit": &"female_knight", "duty": &"relief", "post": 0},
]

## The quarter turn every rig aboard is built with, the player's included. Held here
## rather than read off the train, because the cast are spawned before a train exists
## and outlive the one they were spawned for.
const WALKING_YAW_OFFSET := -PI * 0.5

## The conductor's rounds: the length of the train and back, over and over, all night.
##
## His timeline in the content is what he tells an enquiry, and it is still what the
## register says. Where he actually is, is this: thirty years of walking the same
## corridor, which is the one thing about him nobody disputes.
const ROUNDS_OF_THE_TRAIN := &"moreau"

## Departure, in minutes past midnight. Earliest authored timeline is Dupont boarding at Paris.
const DEPARTURE_MINUTES := 16 * 60 + 5

var time_of_day: CTimeOfDay
var run: CRun

var _scope := ECSScope.new()
var _clock: SClock

func _ready() -> void:
	time_of_day = CTimeOfDay.new()
	run = CRun.new()
	_scope.spawn().add(time_of_day).add(run)

	_clock = SClock.new()
	_clock.world_minutes_per_second = 1.0
	_scope.add_system(&"clock", _clock)
	var places := SPassengerPlace.new()
	places.departure_minutes = DEPARTURE_MINUTES
	_scope.add_system(&"passenger_place", places)

	# What they wear is decided here, once, rather than when a carriage comes into
	# view: the rig [SCastBody] builds is thrown away and rebuilt every time the player
	# walks back, and a passenger who changed coat on the way past would be a lie the
	# whole game is about telling deliberately.
	for passenger: Dictionary in GameContent.passengers():
		var identity := CIdentity.new()
		identity.content_id = passenger.get("id", "")
		var errand := CErrand.new()
		if identity.content_id == ROUNDS_OF_THE_TRAIN:
			errand.beat = the_length_of_the_train()
		var entity := _scope.spawn().add(CPassenger.new()).add(identity) \
			.add(CLocation.new()).add(Wardrobe.appearance_of(identity.content_id)) \
			.add(CCharacterRig.new()).add(errand).add(_walking_locomotion()).add(CGait.new()) \
			.add(CPosture.new()).add(CSeating.new()).add(_seated_idle(identity.content_id))
		# The conductor is on his rounds all night and never sits down, which is the one
		# thing everybody who has ever taken this train agrees about him.
		if identity.content_id != ROUNDS_OF_THE_TRAIN:
			entity.add(_pastime(identity.content_id))

	for sworn: Dictionary in ESCORT:
		var post := CLocation.new()
		post.location_id = ESCORT_LOCATION
		var duty := CWatch.new()
		duty.duty = sworn["duty"]
		duty.post_index = sworn["post"]
		_scope.spawn().add(post).add(CCharacterRig.new()) \
			.add(Wardrobe.roll(sworn["seed"], sworn["outfit"])) \
			.add(duty).add(CErrand.new()).add(_walking_locomotion()).add(CGait.new())

	begin()


## Resets the run in place. The component instances survive, so anything holding
## a reference to them keeps working across a restart.
func begin() -> void:
	run.level_index = 0
	run.score = 0
	run.outcome = &"start"
	time_of_day.running = true
	_clock.set_minutes(time_of_day, DEPARTURE_MINUTES)


func _exit_tree() -> void:
	_scope.dispose()


## The turned-round facing every rig in this project carries, and nothing else the
## player's own locomotion holds: a passenger has no input, no jump and no capsule.
func _walking_locomotion() -> CLocomotion:
	var locomotion := CLocomotion.new()
	locomotion.forward_yaw_offset_radians = WALKING_YAW_OFFSET
	return locomotion


## Every room aboard, down the train and back again. The turn at each end is the return
## leg rather than a jump: without it the conductor walks the length of the carriages
## and then appears at the far end to do it again.
func the_length_of_the_train() -> Array[StringName]:
	var down := GameContent.carriage_locations()
	var rounds: Array[StringName] = []
	for room: StringName in down:
		rounds.append(room)
	for i in range(down.size() - 2, 0, -1):
		rounds.append(down[i])
	return rounds


## Seeded off who they are, so a carriage of passengers do not shift their weight in
## unison and are the same person on every run.
func _seated_idle(content_id: StringName) -> CSeatedIdle:
	var idle := CSeatedIdle.new()
	idle.rng.seed = Wardrobe.seed_of(content_id)
	return idle


func _pastime(content_id: StringName) -> CPastime:
	var pastime := CPastime.new()
	pastime.rng.seed = Wardrobe.seed_of(content_id) ^ 0x9e37
	pastime.wanders_before_settling = pastime.rng.randi_range(0, 2)
	return pastime
