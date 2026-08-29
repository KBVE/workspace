extends ECSSystem
class_name SSound

## SSound is everything the train is heard as.
##
## It reads the world rather than being told about it. A door is heard because its leaf
## moved, a footstep because a body covered another stride, a carriage because it is a
## carriage -- no system anywhere else knows that sound exists, and none of them should:
## the moment [SDoor] has to remember to make a noise, a door added somewhere else is a
## silent door and nothing says so.
##
## Two things are exceptions, and both are exceptions for the same reason: they are
## events rather than states. A locked door that refuses is not a change anything can
## be read off afterwards -- the leaf does not move -- and a notice being taken off the
## wall is the player's own doing rather than the sheet's. Those arrive on the bus.
##
## Nothing here holds a listener. Godot hears from the current [Camera3D] unless an
## [AudioListener3D] says otherwise, and the camera is already where the player's eyes
## are: giving the ear a node of its own would be a second thing to keep in step with
## the head for no gain.

const BANK_DIR := "res://assets/audio"

## Key to what is under it: the file, how loud it is by default, and whether it is a
## thing that goes on. The levels are here rather than on the components because they
## are a property of the recording -- a footstep and a rumble are not mixed against each
## other by whoever places them.
const BANK := {
	&"carriage_rumble": {"file": "carriage_rumble", "db": -16.0, "loops": true},
	&"rail_joints": {"file": "rail_joints", "db": -13.0, "loops": true},
	&"gas_hiss": {"file": "gas_hiss", "db": -26.0, "loops": true},
	&"footstep_a": {"file": "footstep_a", "db": -14.0, "loops": false},
	&"footstep_b": {"file": "footstep_b", "db": -14.0, "loops": false},
	&"door_open": {"file": "door_open", "db": -8.0, "loops": false},
	&"door_shut": {"file": "door_shut", "db": -7.0, "loops": false},
	&"door_locked": {"file": "door_locked", "db": -9.0, "loops": false},
	&"paper": {"file": "paper", "db": -10.0, "loops": false},
}

## Everything goes to SFX, which is the bus the options menu already has a slider for.
const BUS := &"SFX"

## How many one-shots can be in the air at once. Small on purpose: past a handful the
## mix is mud, and the eleventh footstep in a frame is one nobody can pick out of the
## ten before it.
const VOICES := 12

## How far through its swing a leaf has to get before it counts as having opened, and
## how far back before it counts as having shut. Two thresholds rather than one, so a
## door resting near the middle does not bang open and shut every frame it wobbles.
const SWUNG_OPEN := 0.55
const SWUNG_SHUT := 0.15

## Where the players are parented. Handed in like [SCastBody]'s root, because a system
## does not own a place in the tree.
var sound_root: Node3D

## Off by default so a headless run makes no sound and asks the audio driver for
## nothing. The tests set it: what they check is the decisions, not the noise.
var enabled: bool = true

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0

## One player per entity that is making a continuous sound, and the key it was started
## on, so a carriage that changes what it sounds like is restarted rather than left.
var _looping: Dictionary = {}

## What the leaf was doing last time it was looked at, by door. A door is heard on the
## crossing rather than on the state, and the state is all a component holds.
var _door_was_open: Dictionary = {}

## Said by the player rather than by a thing in the world: their own hand on a handle,
## their own sheet. Played flat rather than placed, because the source is where they
## are standing and a positional voice at the listener is a positional voice fighting
## its own falloff.
var _at_hand: AudioStreamPlayer


## Held so the two bus subscriptions can be taken off again. A callable that captured
## this system and outlived it is a lambda holding a freed object, which the bus goes on
## calling every time a door is tried for the rest of the process.
var _listens: Dictionary = {}


func _on_enter(w: ECSWorld) -> void:
	for key: StringName in BANK:
		_streams[key] = _load(key)
	for event: StringName in [GameEvents.DOOR_STATE, GameEvents.NOTICE_READ]:
		var listener := func(e: GameEvent) -> void: heard(e, event)
		_listens[event] = listener
		w.add_callable(event, listener)
	if sound_root == null:
		return
	for i in range(VOICES):
		var voice := AudioStreamPlayer3D.new()
		voice.bus = BUS
		sound_root.add_child(voice)
		_voices.append(voice)
	_at_hand = AudioStreamPlayer.new()
	_at_hand.bus = BUS
	sound_root.add_child(_at_hand)


func _on_exit(w: ECSWorld) -> void:
	for event: StringName in _listens:
		w.remove_callable(event, _listens[event])
	_listens.clear()
	for id: int in _looping.keys():
		_release(id)


## The looping streams are told to loop here rather than in an import setting, because
## the import is written by whoever added the file and this is the only place that
## knows which of them is a bed and which is a bang. A stream that is not marked comes
## back as a two-second rumble followed by silence, which reads as the engine cutting
## out.
func _load(key: StringName) -> AudioStream:
	var path := "%s/%s.wav" % [BANK_DIR, BANK[key]["file"]]
	if not ResourceLoader.exists(path):
		push_error("SSound: no %s -- run tools/gen-sounds.py" % path)
		return null
	var stream: AudioStream = load(path)
	var wav := stream as AudioStreamWAV
	if wav != null and BANK[key]["loops"]:
		wav = wav.duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2
		return wav
	return stream


func _on_update(delta: float) -> void:
	var ear := _listening_from()
	_keep_the_loops(ear)
	_walk(delta, ear)
	_swing(ear)


## Where hearing happens, which is the camera. Null before one exists, and everything
## downstream treats that as nothing being close enough to hear -- which is true: there
## is nobody there.
func _listening_from() -> Vector3:
	for eye: CCamera in view(&"CCamera"):
		if eye.camera != null:
			return eye.camera.global_position
	return Vector3.INF


## Continuous sounds, started and stopped as they come into and go out of earshot.
##
## Stopped rather than turned down. A silent player is a voice held for something that
## cannot be heard, and ten carriages of held voices is the pool gone before the player
## has walked anywhere.
func _keep_the_loops(ear: Vector3) -> void:
	var still_going := {}
	for entry: Dictionary in multi_view([CNoise, ECSViewComponent]):
		var noise: CNoise = entry[&"CNoise"]
		var at := entry[&"ECSViewComponent"].view as Node3D
		if at == null or not is_instance_valid(at) or noise.sound.is_empty():
			continue
		var id: int = entry["entity"].get_instance_id()
		var far := ear == Vector3.INF \
			or ear.distance_to(at.global_position) > noise.audible_within_metres
		if far or not enabled or noise.gain <= 0.0:
			continue
		still_going[id] = true
		_hold(id, noise, at)
	for id: int in _looping.keys():
		if not still_going.has(id):
			_release(id)


func _hold(id: int, noise: CNoise, at: Node3D) -> void:
	var held: Dictionary = _looping.get(id, {})
	var player: AudioStreamPlayer3D = held.get("player")
	if player != null and held.get("sound", &"") != noise.sound:
		_release(id)
		player = null
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.bus = BUS
		player.stream = _streams.get(noise.sound)
		sound_root.add_child(player)
		player.play()
		_looping[id] = {"player": player, "sound": noise.sound}
	player.global_position = at.global_position
	player.max_distance = noise.reach_metres
	player.pitch_scale = noise.pitch
	player.volume_db = float(BANK[noise.sound]["db"]) + linear_to_db(maxf(noise.gain, 0.0001))


func _release(id: int) -> void:
	var held: Dictionary = _looping.get(id, {})
	var player: AudioStreamPlayer3D = held.get("player")
	if player != null and is_instance_valid(player):
		player.stop()
		player.queue_free()
	_looping.erase(id)


## A foot goes down every stride covered, alternating.
##
## Distance rather than time, because the walk clips are played at a time scale that
## answers to speed: a footstep on a timer keeps its rhythm while the legs speed up,
## and that is heard immediately by somebody not even listening for it.
func _walk(delta: float, ear: Vector3) -> void:
	for entry: Dictionary in multi_view([CLocomotion, CFootsteps, CPosture, CCharacterRig]):
		var feet: CFootsteps = entry[&"CFootsteps"]
		var posture: CPosture = entry[&"CPosture"]
		var locomotion: CLocomotion = entry[&"CLocomotion"]
		if posture.state != CPosture.AFOOT and not CPosture.STANDING_STATES.has(posture.state):
			# Sitting, dying and in the air have no feet on the floor to put down.
			feet.since_metres = 0.0
			continue
		var covered := Vector2(locomotion.strafe_metres_per_second,
			locomotion.forward_metres_per_second).length() * delta
		if covered <= 0.0:
			continue
		feet.since_metres += covered
		if feet.since_metres < feet.stride_metres:
			continue
		feet.since_metres = 0.0
		feet.other_foot = not feet.other_foot
		var rig: CharacterRig = entry[&"CCharacterRig"].live()
		if rig == null:
			continue
		if ear == Vector3.INF \
				or ear.distance_to(rig.global_position) > feet.audible_within_metres:
			continue
		play(&"footstep_b" if feet.other_foot else &"footstep_a",
			rig.global_position, feet.gain)


## A door is heard when the leaf crosses, not while it is across.
func _swing(ear: Vector3) -> void:
	for entry: Dictionary in multi_view([CDoor, ECSViewComponent]):
		var door: CDoor = entry[&"CDoor"]
		var leaf: Node3D = entry[&"ECSViewComponent"].view as Node3D
		if leaf == null or not is_instance_valid(leaf):
			continue
		var id: int = entry["entity"].get_instance_id()
		var was: bool = _door_was_open.get(id, false)
		var now := was
		if door.swing >= SWUNG_OPEN:
			now = true
		elif door.swing <= SWUNG_SHUT:
			now = false
		if now == was:
			continue
		_door_was_open[id] = now
		if ear != Vector3.INF and ear.distance_to(leaf.global_position) < 24.0:
			play(&"door_open" if now else &"door_shut", leaf.global_position)


## One sound, somewhere. Voices are taken round the ring rather than searched for a
## free one: past a handful of overlapping one-shots the mix is mud anyway, so the
## twelfth footstep in a frame cutting the first is the right thing to happen.
func play(key: StringName, at: Vector3, gain: float = 1.0) -> void:
	if not enabled or _voices.is_empty() or not _streams.has(key):
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _streams[key]
	voice.global_position = at
	voice.volume_db = float(BANK[key]["db"]) + linear_to_db(maxf(gain, 0.0001))
	voice.play()


## Something the player did, heard at the player. Their hand on a handle that will not
## turn, their own sheet off the wall: the source is where they are standing, and a
## positional voice there is a voice fighting its own falloff for no reason.
func at_hand(key: StringName) -> void:
	if not enabled or _at_hand == null or not _streams.has(key):
		return
	_at_hand.stream = _streams[key]
	_at_hand.volume_db = float(BANK[key]["db"])
	_at_hand.play()


## The two things that are events rather than states. A refused door does not move, so
## there is no crossing to read it off afterwards; a notice coming off the wall is the
## player's doing rather than the sheet's.
func heard(event: GameEvent, name: StringName) -> void:
	if name == GameEvents.DOOR_STATE and event.data.get("locked", false):
		at_hand(&"door_locked")
	elif name == GameEvents.NOTICE_READ:
		at_hand(&"paper")
