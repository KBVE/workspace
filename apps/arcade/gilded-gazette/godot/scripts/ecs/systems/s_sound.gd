extends ECSSystem
class_name SSound

## SSound is everything the train is heard as.
##
## It reads the world rather than being told about it: a door is heard because its leaf
## moved, a footstep because a body covered another stride. Nothing else knows sound
## exists, and nothing else should -- the moment [SDoor] has to remember to make a
## noise, a door added somewhere else is a silent door and nothing says so.
##
## What arrives on the bus instead is what is an event rather than a state: a refused
## door does not move, a notice off the wall is the player's doing rather than the
## sheet's, and a verdict is a moment.
##
## No listener node. Godot hears from the current [Camera3D], which is already where
## the player's eyes are.

const BANK_DIR := "res://assets/audio"

## The file, its level, and whether it goes on. Levels live here rather than on the
## components: they are a property of the recording, not of whoever places it.
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
	&"sit": {"file": "sit", "db": -13.0, "loops": false},
	&"rise": {"file": "rise", "db": -13.0, "loops": false},
	&"verdict_right": {"file": "verdict_right", "db": -6.0, "loops": false},
	&"verdict_wrong": {"file": "verdict_wrong", "db": -6.0, "loops": false},
}

## Everything goes to SFX, which is the bus the options menu already has a slider for.
const BUS := &"SFX"

## One-shots in the air at once. Small: past a handful the mix is mud.
const VOICES := 12

## Two thresholds rather than one, so a leaf resting near the middle does not bang
## open and shut every frame it wobbles.
const SWUNG_OPEN := 0.55
const SWUNG_SHUT := 0.15

## Where the players are parented; a system does not own a place in the tree.
var sound_root: Node3D

## Off in a headless run, which has no audio driver to ask. The tests check the
## decisions, not the noise.
var enabled: bool = true

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0

## One player per entity that is making a continuous sound, and the key it was started
## on, so a carriage that changes what it sounds like is restarted rather than left.
var _looping: Dictionary = {}

## Players that were holding a bed and are not any more, kept rather than freed.
##
## Walking the train crosses in and out of earshot constantly -- three beds a carriage
## against a pitch shorter than the range they carry -- so building and freeing a node
## per crossing is scene-tree churn for the whole run. The one-shots have gone round a
## ring from the start; the beds used to be the exception, and there was no reason for
## it beyond their number not being known in advance.
var _spare: Array[AudioStreamPlayer3D] = []

## What each body was last doing, by entity. A sit is heard on the crossing into the
## one-shot posture, not for every frame it runs.
var _posture_was: Dictionary = {}

## What the leaf was doing last time it was looked at, by door. A door is heard on the
## crossing rather than on the state, and the state is all a component holds.
var _door_was_open: Dictionary = {}

## Said by the player rather than by a thing in the world: their own hand on a handle,
## their own sheet. Played flat rather than placed, because the source is where they
## are standing and a positional voice at the listener is a positional voice fighting
## its own falloff.
var _at_hand: AudioStreamPlayer


## Held so the subscriptions can be taken off again: a callable that captured this
## system and outlived it is the bus calling a freed object for the rest of the run.
var _listens: Dictionary = {}


func _on_enter(w: ECSWorld) -> void:
	for key: StringName in BANK:
		_streams[key] = _load(key)
	for event: StringName in [GameEvents.DOOR_STATE, GameEvents.NOTICE_READ,
			GameEvents.VERDICT]:
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
	_spare.clear()


## Loops are marked here rather than in the import, which is written by whoever adds
## the file: this is the only place that knows a bed from a bang. Unmarked, a rumble
## plays for two seconds and stops, which reads as the engine cutting out.
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
	_sit(ear)
	_swing(ear)


## Where hearing happens. Nothing before a camera exists, which everything downstream
## reads as nobody being near enough to hear -- true, because there is nobody there.
func _listening_from() -> Vector3:
	for eye: CCamera in view(&"CCamera"):
		if eye.camera != null:
			return eye.camera.global_position
	return Vector3.INF


## Continuous sounds, started and stopped as they come into and go out of earshot.
## Stopped rather than turned down: ten carriages of silent players is the pool gone
## before the player has walked anywhere.
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
		player = _a_voice()
		player.stream = _streams.get(noise.sound)
		player.play()
		_looping[id] = {"player": player, "sound": noise.sound}
	player.global_position = at.global_position
	player.max_distance = noise.reach_metres
	player.pitch_scale = noise.pitch
	player.volume_db = float(BANK[noise.sound]["db"]) + linear_to_db(maxf(noise.gain, 0.0001))


## One off the pile, or a new one when the pile is empty. The pile settles at however
## many beds are audible at once, which is a property of the train rather than a number
## anybody has to choose.
func _a_voice() -> AudioStreamPlayer3D:
	if not _spare.is_empty():
		return _spare.pop_back()
	var player := AudioStreamPlayer3D.new()
	player.bus = BUS
	sound_root.add_child(player)
	return player


func _release(id: int) -> void:
	var held: Dictionary = _looping.get(id, {})
	var player: AudioStreamPlayer3D = held.get("player")
	if player != null and is_instance_valid(player):
		player.stop()
		_spare.append(player)
	_looping.erase(id)


## A foot goes down every stride covered, alternating. Distance rather than time --
## see [CFootsteps].
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


## Down onto the cushion and back off it, heard on the crossing into the posture the
## way a door is: fired every frame it holds, it is a bench sat on forty times.
func _sit(ear: Vector3) -> void:
	for entry: Dictionary in multi_view([CPosture, CCharacterRig]):
		var posture: CPosture = entry[&"CPosture"]
		var id: int = entry["entity"].get_instance_id()
		var was: StringName = _posture_was.get(id, &"")
		if posture.state == was:
			continue
		_posture_was[id] = posture.state
		if posture.state != CPosture.SEATING and posture.state != CPosture.RISING:
			continue
		var rig: CharacterRig = entry[&"CCharacterRig"].live()
		if rig == null:
			continue
		if ear == Vector3.INF or ear.distance_to(rig.global_position) > 12.0:
			continue
		play(&"sit" if posture.state == CPosture.SEATING else &"rise",
			rig.global_position)


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


## One sound, somewhere. Voices go round the ring rather than being searched for a
## free one: the twelfth footstep in a frame cutting the first is the right outcome.
func play(key: StringName, at: Vector3, gain: float = 1.0) -> void:
	if not enabled or _voices.is_empty() or not _streams.has(key):
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _streams[key]
	voice.global_position = at
	voice.volume_db = float(BANK[key]["db"]) + linear_to_db(maxf(gain, 0.0001))
	voice.play()


## Something the player did, heard at the player: their hand on a handle that will not
## turn. A positional voice at the listener fights its own falloff for nothing.
func at_hand(key: StringName) -> void:
	if not enabled or _at_hand == null or not _streams.has(key):
		return
	_at_hand.stream = _streams[key]
	_at_hand.volume_db = float(BANK[key]["db"])
	_at_hand.play()


## What is an event rather than a state, and so has no crossing to be read off.
func heard(event: GameEvent, name: StringName) -> void:
	if name == GameEvents.DOOR_STATE and event.data.get("locked", false):
		at_hand(&"door_locked")
	elif name == GameEvents.NOTICE_READ:
		at_hand(&"paper")
	elif name == GameEvents.VERDICT:
		_ring_the_bell(event.data)


## The envelope, opened: a bell in tune with itself, or the same bell with a crack in
## it. Whether they were right is worked out here rather than sent, for the reason
## React works it out too -- the answer and its comparison are one fact, and two copies
## of it can disagree.
func _ring_the_bell(said: Dictionary) -> void:
	var right: bool = said.get("who", "") == said.get("named_who", "") \
		and said.get("weapon", "") == said.get("named_weapon", "") \
		and said.get("room", "") == said.get("named_room", "")
	at_hand(&"verdict_right" if right else &"verdict_wrong")
