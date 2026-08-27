extends Node3D
class_name Train

## Train : Node3D
##
## Actual carriage geometry, 32k tris, one 2048 atlas. No baked light, so time of
## day is runtime state and the camera goes anywhere.
##
## One scene, one camera, walked from inside the aisle. Everything else the run
## needs is a component on the ECS, not another scene to swap to.

const LEVEL_NAME := "Aisle"

## Where a run starts, in metres along the train.
const START_X := -7.0

## How far behind the player the camera rides, and where it sits relative to the end
## of that arm. The offset is what makes it over the shoulder rather than straight
## down the spine: the body sits left of centre and the aisle ahead stays clear.
##
## Metres, framed against a person of [member PlayerBody.stature_metres]; shrinking
## him and leaving these alone films him from a giant's remove. Shorter still than an outdoor game would use, because only the
## floor and the side walls of a carriage carry collision: the seats and the end
## bulkheads are mesh with nothing behind them, so a longer arm does not get pulled
## in by the spring, it simply ends up inside them or outside the train.
const BOOM_LENGTH := 0.95
const BOOM_SHOULDER_OFFSET := Vector3(0.12, 0.28, 0.0)

## Radians turned per unit of input, so one full swipe is most of a turn.
const TURN_RADIANS_PER_UNIT := 2.4

## Metres walked per unit of input.
const WALK_METRES_PER_UNIT := 4.0

## A carriage on welded rail is nearly steady. What you actually feel is the
## joints going under the bogies, so the constant part is almost nothing and the
## motion arrives as spaced-out knocks that fade.
const SWAY_HZ := 0.7
const SWAY_RISE := 0.0025
const SWAY_ROLL := 0.0005

## Seconds between knocks, how long one takes to die away, and how hard it hits.
## The gap is long on purpose: a bump the player can predict stops being a bump.
## JOLT_HZ against JOLT_FADE decides how many times the carriage moves per knock,
## and roughly one is what reads as a joint rather than a wobble.
const JOLT_GAP := Vector2(60.0, 120.0)
const JOLT_FADE := 0.55
const JOLT_HZ := 2.0
const JOLT_RISE := 0.020
const JOLT_ROLL := 0.0032



## Wide enough that he cannot slip between a seat and the wall, narrow enough for the
## aisle, which is three metres across.
const PLAYER_RADIUS := 0.30

## The camera is a quarter turn off the body so it looks down the train rather than
## across it. Shared by the rig, which has to face the same way, and by the walk,
## which has to go that way.
const CAMERA_YAW_OFFSET := -PI * 0.5

@onready var _frame: SubViewportContainer = $Screen/Frame
@onready var _world: SubViewport = $Screen/Frame/World
@onready var _player: CharacterBody3D = $Screen/Frame/World/Player
@onready var _player_shape: CollisionShape3D = $Screen/Frame/World/Player/Body
@onready var _cam: Camera3D = $Screen/Frame/World/Player/Camera3D
@onready var _consist: Consist = $Screen/Frame/World/Consist
@onready var _forest: ParallaxBackdrop = $Screen/Frame/World/Backdrop/Forest

var _t := 0.0
## INF, or re-seeding on every _ready() restarts the evening on re-entry.
var _seed_phase := INF
var _seed_running := true
var _yaw_override := INF
var _eye_override := INF
var _viewer: CViewer
var _locomotion: CLocomotion
var _intent: CInput
var _posture: CPosture
var _foot_planting: CFootPlanting
var _seating: CSeating
var _pointer: CPointer
var _prompt: CPrompt
var _seated_idle: CSeatedIdle
var _control: SPlayerControl
var _thumbs: TouchControls
var _occupant: COccupant
var _here: CLocation
var _time_of_day: CTimeOfDay
var _run: CRun
## Seconds until the next knock, and how much of the last one is left.
var _jolt_countdown := 0.0
var _jolt_energy := 0.0

## Torn down with the scene. The clock is not here; it lives on [Session].
var _scope := ECSScope.new()

## Holds the world's resolution against the frame clock. Built here rather than
## in the scene so a device that changes speed mid-run can be answered mid-run.
var _render_budget := RenderBudget.new()
var _published_shrink := 0

func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--yaw="):
			# applied after _begin, which faces the player down the train
			_yaw_override = clampf(float(a.split("=")[1]), -1.4, 1.4)
		if a.begins_with("--eye="):
			_eye_override = float(a.split("=")[1])
		if a.begins_with("--phase="):
			# 0.0 noon, 0.5 midnight
			_seed_phase = fposmod(float(a.split("=")[1]), 1.0)
			_seed_running = false
		if a.begins_with("--detail="):
			var v := a.split("=")[1].split(",")
			_tune_detail(float(v[0]), float(v[1]), float(v[2]))
	_time_of_day = Session.time_of_day
	_run = Session.run

	# one mesh repeated, so rooms are authored not modelled; order is
	# shared/data/locations, which React reads as the same list
	var rooms := GameContent.carriage_locations()
	if rooms.size() != _consist.carriage_count:
		push_error("Consist has %d carriages but shared/data/locations authors %d. Rebuild the scene."
			% [_consist.carriage_count, rooms.size()])
	for i in range(mini(rooms.size(), _consist.carriage_count)):
		var room := CLocation.new()
		room.location_id = rooms[i]
		var carriage := CCarriage.new()
		carriage.index = i
		_scope.spawn().add(carriage).add(room).add(CLamp.new()) \
			.add(ECSViewComponent.new(_consist.lamps_for(i)))

	# built first: how tall he is decides where his eyes are, and his eyes are where
	# the camera goes
	var body := _add_player_body()
	_fit_the_capsule_to(body)

	_viewer = CViewer.new()
	_occupant = COccupant.new()
	_here = CLocation.new()
	_locomotion = CLocomotion.new()
	_locomotion.forward_yaw_offset_radians = CAMERA_YAW_OFFSET
	_locomotion.eye_height_metres = \
		_eye_override if is_finite(_eye_override) else body.eye_height_metres()
	_locomotion.turn_radians_per_unit = TURN_RADIANS_PER_UNIT
	_locomotion.walk_metres_per_unit = WALK_METRES_PER_UNIT
	_intent = CInput.new()
	_posture = CPosture.new()
	_foot_planting = CFootPlanting.new()
	_seating = CSeating.new()
	_pointer = CPointer.new()
	_seated_idle = _rolled_seated_idle()
	_prompt = CPrompt.new()
	_scope.spawn().add(_viewer).add(_occupant).add(_here).add(_intent) \
		.add(_locomotion).add(_carriage_camera()) \
		.add(CCharacterRig.new(body)).add(CGait.new()).add(_posture).add(_foot_planting).add(_seating).add(_seated_idle).add(_pointer).add(_prompt).add(_the_highlight()) \
		.add(ECSViewComponent.new(_player))
	_control = SPlayerControl.new()
	# an exported build is somebody playing and starts live. A debug run is somebody
	# working, with an editor behind the window it just stole focus from, and starts
	# inert until [Tab] says otherwise. Headless is the tests, which press real actions.
	_control.engaged = DisplayServer.get_name() == "headless" \
		or not OS.has_feature("editor")
	_scope.add_system(&"player_control", _control)
	_spawn_the_seats()
	_scope.add_system(&"pointing", SPointing.new())
	_scope.add_system(&"highlight", SHighlight.new())
	for posting: Dictionary in _consist.notice_anchors():
		var notice := CNotice.new()
		notice.notice_id = posting["id"]
		notice.at = posting["at"]
		_scope.spawn().add(notice).add(ECSViewComponent.new(posting["sheet"]))
	_scope.add_system(&"notice", SNotice.new())
	_scope.add_system(&"seating", SSeating.new())
	_scope.add_system(&"locomotion", SLocomotion.new())
	_scope.add_system(&"camera_aim", SCameraAim.new())
	_scope.add_system(&"character_animation", SCharacterAnimation.new())
	_scope.add_system(&"seated_idle", SSeatedIdle.new())
	_scope.add_system(&"posture", SPosture.new())
	_scope.add_system(&"foot_planting", SFootPlanting.new())
	_scope.add_system(&"viewer", SViewer.new())
	var occupancy := SOccupancy.new()
	occupancy.carriage_pitch = _consist.pitch
	occupancy.carriage_count = _consist.carriage_count
	_scope.add_system(&"occupancy", occupancy)
	_scope.add_system(&"cast_body", _cast_body_system())
	_scope.add_system(&"cast_walk", _cast_walk_system())
	_scope.add_system(&"door_traffic", SDoorTraffic.new())
	_scope.add_system(&"guard_watch", _guard_watch_system())
	_scope.add_system(&"pastime", SPastime.new())
	_scope.spawn().add(CParallax.new()).add(ECSViewComponent.new(_forest))
	_scope.add_system(&"parallax", SParallax.new())
	_scope.spawn().add(CWorldLighting.new()).add(ECSViewComponent.new($Screen/Frame/World/Lighting))
	_scope.add_system(&"world_lighting", SWorldLighting.new())
	var lamps := SCarriageLamps.new()
	lamps.lamp_glass = _consist.glow_material()
	for leaf: Node3D in _consist.door_leaves():
		var door := CDoor.new()
		# opening outward by default, so a door swung by anything that is not the
		# player -- a passenger walking through, a scripted beat -- still clears the
		# aisle rather than sweeping down it. SDoor overrides this per press.
		door.swing_sign = -1.0 if leaf.position.x > 0.0 else 1.0
		_scope.spawn().add(door).add(ECSViewComponent.new(leaf))
	_scope.add_system(&"door", SDoor.new())
	_scope.add_system(&"carriage_lamps", lamps)

	var crosshair := Crosshair.new()
	crosshair.aiming = _intent
	_frame.get_parent().add_child(crosshair)

	_scope.add_system(&"prompt", SPrompt.new())
	var label := InteractionLabel.new()
	label.name = "InteractionLabel"
	label.prompt = _prompt
	_frame.get_parent().add_child(label)

	_thumbs = TouchControls.new()
	var thumbs := _thumbs
	thumbs.name = "Thumbs"
	thumbs.control = _control
	thumbs.crosshair = crosshair
	# built on every platform and shown only where there is a thumb, so a touchscreen
	# the engine notices late is a visibility change rather than a scene that has to be
	# rebuilt. TouchControls keeps that up to date itself.
	thumbs.visible = DisplayServer.is_touchscreen_available()
	_frame.get_parent().add_child(thumbs)

	# the world owns the camera now, so picking is its viewport's job, not the
	# window's
	_world.physics_object_picking = true
	_render_budget.begin(DisplayServer.is_touchscreen_available(),
		DisplayServer.screen_get_scale(), DisplayServer.screen_get_size(),
		DisplayServer.screen_get_refresh_rate())
	_apply_render_budget()
	# React's ui:restart and an in-world loss take the same path
	Ecs.world.add_callable(GameEvents.UI_RESTART, _on_ui_restart)

	# a full gap, so the run does not open on a knock
	_jolt_countdown = randf_range(JOLT_GAP.x, JOLT_GAP.y)
	_time_of_day.running = _seed_running
	if is_finite(_seed_phase):
		_time_of_day.phase = fposmod(_seed_phase, 1.0)
	_begin()
	if is_finite(_yaw_override):
		_locomotion.facing_radians = _yaw_override

## Driven by `-- --detail=tiling,strength,albedo`, to sweep without rebuilding.
func _tune_detail(tiling: float, strength: float, albedo: float) -> void:
	_consist.tune_detail(tiling, strength, albedo)

func _process(delta: float) -> void:
	_t += delta
	_read_clock_keys()
	# after _apply_shot, which writes the resting height and would otherwise
	# wipe the sway back out every frame
	_advance_jolt(delta)
	# squared so the knock lands hard and tails off, rather than fading linearly
	var knock := _jolt_energy * _jolt_energy
	_player.position.y += sin(_t * TAU * SWAY_HZ) * SWAY_RISE \
		+ sin(_t * TAU * JOLT_HZ) * JOLT_RISE * knock
	_player.rotation.z = sin(_t * TAU * SWAY_HZ * 0.37) * SWAY_ROLL \
		+ sin(_t * TAU * JOLT_HZ * 0.73) * JOLT_ROLL * knock

	# only the cars near the viewer draw; cost is O(1) in train length
	_consist.cull_around(_viewer.world_x)
	_adapt_render_scale(delta)


## Hands the frame clock to [RenderBudget] and applies whatever it decides.
##
## Runs every frame because the sampling and the hysteresis belong to the budget,
## not to its caller.
func _adapt_render_scale(delta: float) -> void:
	# an unfocused window is not a slow one; the browser throttles the tab and every
	# frame of it would read as a device that cannot cope
	if not get_window().has_focus():
		return
	var before := _render_budget.shrink
	if _render_budget.sample(Engine.get_frames_per_second(), delta) != before:
		_apply_render_budget()


## Resizing the SubViewport reallocates its render target, so this is only ever
## called on an actual change.
func _apply_render_budget() -> void:
	_frame.stretch_shrink = _render_budget.shrink
	_world.msaa_3d = _render_budget.msaa()
	if _render_budget.shrink == _published_shrink:
		return
	_published_shrink = _render_budget.shrink
	Ecs.notify(GameEvents.RENDER_BUDGET, {
		"shrink": _render_budget.shrink,
		"detail": _render_budget.describe(),
	})

## Counts down to the next knock and bleeds the last one away.
func _advance_jolt(delta: float) -> void:
	_jolt_energy = maxf(_jolt_energy - delta / JOLT_FADE, 0.0)
	_jolt_countdown -= delta
	if _jolt_countdown > 0.0:
		return
	_jolt_countdown = randf_range(JOLT_GAP.x, JOLT_GAP.y)
	_jolt_energy = 1.0


func _exit_tree() -> void:
	_scope.dispose()

## Where the camera hangs is the boom's business now, and where it points is
## [SCameraAim]'s. This is what is left: the near plane and the announcement.
func _frame_the_shot() -> void:
	_cam.near = 0.05
	GameBridge.set_world_mode(StateBits.WorldMode.MODE_3D)


## The capsule was authored around a camera hung at two metres sixty, which is what
## the player used to be: a viewpoint with no body under it. Sized against a person
## it is nearly a metre too long, and its bottom ends up under the floor, where
## depenetration lifts him off it every frame.
##
## Y is pinned by [SLocomotion] and there is no gravity, so this shape only ever has
## to keep him out of the walls.
func _fit_the_capsule_to(body: PlayerBody) -> void:
	var capsule := CapsuleShape3D.new()
	capsule.height = body.stature_metres
	capsule.radius = PLAYER_RADIUS
	_player_shape.shape = capsule
	_player_shape.position.y = body.floor_height_metres + body.stature_metres * 0.5 \
		- body.eye_height_metres()


## The rig is a child of the body, so walking and turning carry it for free and
## nothing has to copy a transform onto it.
func _add_player_body() -> PlayerBody:
	var body := PlayerBody.new()
	body.name = "Rig"
	body.floor_height_metres = Consist.FLOOR_Y
	body.forward_yaw_offset_radians = CAMERA_YAW_OFFSET
	_player.add_child(body)
	return body


## How far off the centre line of the aisle anybody can stand before they are standing
## in a bench. The benches decide it, so it is measured off them rather than written
## down twice.
func _aisle_half_width() -> float:
	return maxf(Consist.SEAT_EDGE_Z - SCastWalk.SHOULDER_METRES, 0.05)


## The Order keeps its own watch, and the rota is a ring of duties rather than a
## schedule. What the train has to tell it is the length of the train.
func _guard_watch_system() -> SGuardWatch:
	var watch := SGuardWatch.new()
	watch.rounds = Session.the_length_of_the_train()
	return watch


func _cast_walk_system() -> SCastWalk:
	var walking := SCastWalk.new()
	walking.aisle_half_width = _aisle_half_width()
	return walking


## Passengers hang off a node of their own rather than off the consist, because a
## carriage is culled by visibility and a rig is culled by being built at all.
func _cast_body_system() -> SCastBody:
	var cast_root := Node3D.new()
	cast_root.name = "Cast"
	_consist.get_parent().add_child(cast_root)

	var bodies := SCastBody.new()
	bodies.cast_root = cast_root
	bodies.carriage_pitch = _consist.pitch
	bodies.carriage_count = _consist.carriage_count
	bodies.carriage_window = _consist.mesh_window
	bodies.floor_height_metres = Consist.FLOOR_Y
	bodies.aisle_half_width = _aisle_half_width()
	bodies.forward_yaw_offset_radians = _locomotion.forward_yaw_offset_radians
	return bodies


## The carriage is mesh, not collision, so the spring arm cannot be trusted to keep
## the camera indoors. These are the bounds it is held within.
func _carriage_camera() -> CCamera:
	var eye := CCamera.new(_add_boom(), _cam)
	eye.rest_offset = BOOM_SHOULDER_OFFSET
	eye.standing_boom_metres = BOOM_LENGTH
	eye.interior_half_z = Consist.INTERIOR_HALF_Z - 0.15
	eye.lowest_y = Consist.FLOOR_Y + 0.4
	eye.highest_y = Consist.WALL_HEIGHT - 0.35
	return eye


## Hangs the camera off a spring arm and hands back the arm, because the arm is what
## [SCameraAim] turns. Children of a [SpringArm3D] are placed along its +Z, so the
## camera ends up behind whatever the arm is pointing at, and pulls in on its own
## when a seat back or a bulkhead gets between the two.
##
## The mount exists because the arm writes the position of its direct children every
## frame; the shoulder offset has to hang off something the arm does not own.
func _add_boom() -> SpringArm3D:
	var boom := SpringArm3D.new()
	boom.name = "Boom"
	boom.spring_length = BOOM_LENGTH
	boom.add_excluded_object(_player.get_rid())
	_player.add_child(boom)

	var mount := Node3D.new()
	mount.name = "Mount"
	boom.add_child(mount)

	_cam.reparent(mount, false)
	_cam.position = BOOM_SHOULDER_OFFSET
	_cam.rotation = Vector3.ZERO
	return boom


## Starts the run. There is one scene and one camera, so this sets the framing
## and announces it; it never swaps anything.
func _begin() -> void:
	_run.level_index = 0
	_locomotion.facing_radians = 0.0
	_locomotion.pitch_radians = 0.0
	_player.velocity = Vector3.ZERO
	_player.position = Vector3(START_X, _locomotion.eye_height_metres, 0.0)
	_player.rotation.y = 0.0
	_frame_the_shot()
	GameBridge.set_player_flags(StateBits.PLAYER_ALIVE)
	Journal.record(StateBits.JournalKind.ENTERED, "player", "", LEVEL_NAME.to_lower())
	_notify_level("start")


func _on_ui_restart(_event: GameEvent) -> void:
	Session.begin()
	Journal.clear()
	_begin()


func _notify_level(outcome: String) -> void:
	_run.outcome = outcome
	Ecs.notify(GameEvents.LEVEL_CHANGED, {
		"level": LEVEL_NAME,
		"index": 0,
		"total": 1,
		"outcome": outcome,
	})


## The mouse looks on the right button, and the pointer is never captured: the left
## button has to stay a pointer or there is nothing to click the evidence with. The web
## export already swallows the context menu. Fingers are [TouchControls]' to read.
##
## _input, not _unhandled_input: the SubViewportContainer consumes pointer events
## to forward them inward, so nothing reaches the unhandled pass. Sizes come from
## the window rather than the world, so lowering RENDER_SHRINK cannot change how
## far a look travels.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_control.accumulate_look((event as InputEventMouseMotion).relative,
			float(get_window().size.y))


func _read_clock_keys() -> void:
	if Input.is_action_just_pressed(&"ui_accept"):
		_time_of_day.running = not _time_of_day.running
	if Input.is_action_just_pressed(&"ui_page_up"):
		_time_of_day.phase = fposmod(_time_of_day.phase + 0.08, 1.0)
	if Input.is_action_just_pressed(&"ui_page_down"):
		_time_of_day.phase = fposmod(_time_of_day.phase - 0.08, 1.0)


## One entity per cushion. They carry no view of their own: the bench is already drawn
## by the carriage, and what the entity adds is the only thing the mesh cannot say,
## which is whether anybody is in it.
func _spawn_the_seats() -> void:
	for anchor: Dictionary in _consist.seat_anchors():
		var seat := CSeat.new()
		seat.at = anchor["at"]
		seat.facing_radians = anchor["facing"]
		seat.carriage_index = anchor["carriage"]
		_scope.spawn().add(seat)


## The outline lives beside the consist rather than on the player, because what it marks
## is out in the carriage and the player is the one thing it never draws.
func _the_highlight() -> CHighlight:
	var marker := SelectionHighlight.new()
	marker.name = "Selection"
	_consist.get_parent().add_child(marker)
	var pointing := CHighlight.new()
	pointing.view = marker
	return pointing


## Seeded off the clock so two runs do not shift their weight at the same moments, and
## so the player does not learn the rhythm of his own idle.
func _rolled_seated_idle() -> CSeatedIdle:
	var idle := CSeatedIdle.new()
	idle.rng.randomize()
	return idle
