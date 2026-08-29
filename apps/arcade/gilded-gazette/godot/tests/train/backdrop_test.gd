# GdUnitTestSuite
extends GdUnitTestSuite

## The world outside the window, and the light coming in through it.
##
## [SParallax] and [SWorldLighting] are the two systems nothing was checking, and both
## sell the same lie: the train is standing still on a fixed piece of ground, and
## everything that says otherwise is a scrolling material and a rotated sun. A backdrop
## that stops scrolling is a train that has stopped, and nothing anywhere reports it.

const SCENE := "res://scenes/train/train.scn"

## Phase 0 is noon and half a turn is midnight, which is what daylight is derived from.
const NOON := 0.0
const MIDNIGHT := 0.5


func _phase_to(phase: float) -> void:
	Session.time_of_day.running = false
	var clock: SClock = Ecs.runner.get_system(&"clock")
	clock.set_phase(Session.time_of_day, phase)


func after_test() -> void:
	Session.time_of_day.running = true


func _parallax() -> Dictionary:
	return Ecs.world.multi_view([CParallax, ECSViewComponent])[0]


func _lighting() -> Dictionary:
	return Ecs.world.multi_view([CWorldLighting, ECSViewComponent])[0]


func test_the_country_goes_past() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	_phase_to(NOON)
	var parallax: CParallax = _parallax()[&"CParallax"]
	var was := parallax.scroll_offset
	await runner.simulate_frames(10)
	assert_float(parallax.scroll_offset).override_failure_message(
		"the backdrop stopped moving, which is a train that has stopped"
	).is_greater(was)


## Night closes the canopy over the horizon. It is not a mood: an opaque canopy is what
## lets the terrain behind it stop being drawn at all.
func test_night_closes_the_canopy_and_noon_opens_it() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var parallax: CParallax = _parallax()[&"CParallax"]

	_phase_to(MIDNIGHT)
	await runner.simulate_frames(3)
	var at_night := parallax.canopy_opacity

	_phase_to(NOON)
	await runner.simulate_frames(3)
	assert_float(parallax.canopy_opacity).override_failure_message(
		"the canopy is %f at noon and %f at midnight" % [parallax.canopy_opacity, at_night]
	).is_less(at_night)


func test_the_canopy_never_leaves_its_range() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var parallax: CParallax = _parallax()[&"CParallax"]
	for phase in range(0, 20):
		_phase_to(phase / 20.0)
		await runner.simulate_frames(2)
		assert_float(parallax.canopy_opacity).is_between(0.0, 1.0)


## The backdrop is a handful of quads a few metres from the window, so it has to travel
## with the player: left where it was built, walking two carriages puts the forest at
## an angle through the end wall.
func test_the_backdrop_travels_with_the_viewer() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var backdrop: ParallaxBackdrop = _parallax()[&"ECSViewComponent"].view
	if not backdrop.recentre_on_viewer:
		return
	var viewer: CViewer = Ecs.world.view(&"CViewer")[0]
	await runner.simulate_frames(2)
	assert_float(backdrop.global_position.x).override_failure_message(
		"the forest stands at %f and the player is at %f"
			% [backdrop.global_position.x, viewer.world_x]
	).is_equal_approx(viewer.world_x, 0.01)


## Behind an opaque canopy the terrain is pure overdraw, and so is the material write
## that scrolls it.
func test_a_closed_canopy_takes_the_terrain_out_of_the_frame() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var state: CWorldLighting = _lighting()[&"CWorldLighting"]
	var parallax: CParallax = _parallax()[&"CParallax"]

	# Driven from the clock, not written directly: [SParallax] recomputes the canopy
	# from daylight every frame, before [SWorldLighting] reads it.
	_phase_to(MIDNIGHT)
	await runner.simulate_frames(3)
	assert_float(parallax.canopy_opacity).override_failure_message(
		"midnight left the canopy at %f, so there is nothing to hide behind"
			% parallax.canopy_opacity).is_greater(0.99)
	assert_bool(state.terrain_visible).override_failure_message(
		"the terrain was drawn behind a canopy nothing can see through").is_false()

	var held := state.terrain_scroll
	await runner.simulate_frames(6)
	assert_float(state.terrain_scroll).override_failure_message(
		"the hidden terrain went on scrolling, which is a material write for nobody"
	).is_equal_approx(held, 0.0001)


func test_an_open_canopy_puts_it_back() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var state: CWorldLighting = _lighting()[&"CWorldLighting"]
	_phase_to(NOON)
	await runner.simulate_frames(3)
	assert_bool(state.terrain_visible).is_true()
	var was := state.terrain_scroll
	await runner.simulate_frames(6)
	assert_float(state.terrain_scroll).override_failure_message(
		"the ground outside stopped moving while it was in shot").is_not_equal(was)


## The scroll is a UV offset, so it has to stay inside one turn of the texture. Left to
## climb, it is a float that loses its fraction after a long enough night and the
## ground outside stops moving.
func test_the_terrain_scroll_stays_inside_one_turn() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var state: CWorldLighting = _lighting()[&"CWorldLighting"]
	_phase_to(NOON)
	for _step in range(30):
		await runner.simulate_frames(4)
		assert_float(state.terrain_scroll).is_between(0.0, 1.0)


## The sun answers to the clock, and midnight is not merely a darker noon: the light
## changes colour as well as strength, which is the whole of what makes an evening.
func test_the_sun_answers_to_the_clock() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(20)
	var lighting: WorldLighting = _lighting()[&"ECSViewComponent"].view

	_phase_to(NOON)
	await runner.simulate_frames(3)
	var noon_energy: float = lighting._sun.light_energy
	var noon_colour: Color = lighting._sun.light_color

	_phase_to(MIDNIGHT)
	await runner.simulate_frames(3)
	assert_float(lighting._sun.light_energy).override_failure_message(
		"the sun burns as hard at midnight as at noon").is_less(noon_energy)
	assert_bool(lighting._sun.light_color.is_equal_approx(noon_colour)) \
		.override_failure_message("midnight is noon turned down rather than a night") \
		.is_false()
