extends GdUnitTestSuite

## The scaler is what stands between a phone and 15 fps, and every one of its
## decisions is a timer with hysteresis. Those are exactly the rules that rot
## silently, so they are pinned here rather than left to be noticed on a device.

const FRAME := 1.0 / 60.0

const PHONE := Vector2i(390, 844)
const TOUCH_LAPTOP := Vector2i(1920, 1080)
const DESKTOP := Vector2i(2560, 1440)


func _run_at(budget: RenderBudget, fps: float, seconds: float) -> void:
	for _i in range(int(seconds / FRAME)):
		budget.sample(fps, FRAME)


func test_a_touchscreen_starts_below_full_resolution() -> void:
	var phone := RenderBudget.new()
	phone.begin(true, 3.0, PHONE)
	assert_int(phone.shrink).override_failure_message(
		"a high density touchscreen has never held 60 at full resolution"
	).is_greater(RenderBudget.FASTEST_SHRINK)

	var desktop := RenderBudget.new()
	desktop.begin(false, 2.0, DESKTOP)
	assert_int(desktop.shrink).is_equal(RenderBudget.FASTEST_SHRINK)


func test_a_slow_device_gives_up_pixels() -> void:
	var budget := RenderBudget.new()
	budget.begin(false, 1.0, DESKTOP)
	_run_at(budget, 20.0, 6.0)
	assert_int(budget.shrink).override_failure_message(
		"20 fps for six seconds has to divide the resolution"
	).is_greater(RenderBudget.FASTEST_SHRINK)


func test_it_never_divides_past_the_floor() -> void:
	var budget := RenderBudget.new()
	budget.begin(true, 3.0, PHONE)
	_run_at(budget, 5.0, 600.0)
	assert_int(budget.shrink).is_equal(RenderBudget.SLOWEST_SHRINK)


func test_headroom_is_taken_back_but_not_at_once() -> void:
	var budget := RenderBudget.new()
	budget.begin(true, 3.0, PHONE)
	var started_at := budget.shrink

	_run_at(budget, 60.0, 4.0)
	assert_int(budget.shrink).override_failure_message(
		"four fast seconds is not yet proof; upgrading that eagerly is what oscillates"
	).is_equal(started_at)

	_run_at(budget, 60.0, 6.0)
	assert_int(budget.shrink).is_less(started_at)


func test_a_level_that_proved_slow_is_not_retried_immediately() -> void:
	var budget := RenderBudget.new()
	budget.begin(false, 1.0, DESKTOP)
	_run_at(budget, 20.0, 6.0)
	var after_degrade := budget.shrink

	# the frame rate recovers precisely because the resolution dropped, which is
	# the trap: treating that as headroom walks straight back into the stutter
	_run_at(budget, 60.0, 10.0)
	assert_int(budget.shrink).override_failure_message(
		"recovering because we degraded is not evidence the old level works"
	).is_equal(after_degrade)


func test_antialiasing_goes_before_the_resolution_does() -> void:
	var budget := RenderBudget.new()
	budget.shrink = 1
	assert_int(budget.msaa()).is_equal(Viewport.MSAA_4X)
	budget.shrink = 2
	assert_int(budget.msaa()).is_equal(Viewport.MSAA_2X)
	budget.shrink = 3
	assert_int(budget.msaa()).is_equal(Viewport.MSAA_DISABLED)


## A hitch is not a workload. Streaming a carriage in, a tab coming back from the
## background and a garbage collection all arrive as one very long frame, and
## dropping a level for one is what made the whole run go soft mid-aisle.
func test_one_long_stall_does_not_cost_a_level() -> void:
	var budget := RenderBudget.new()
	budget.begin(false, 1.0, DESKTOP)
	_run_at(budget, 60.0, 4.0)

	for _i in range(6):
		budget.sample(4.0, 0.30)

	assert_int(budget.shrink).override_failure_message(
		"a stall spent the resolution the player was already holding"
	).is_equal(RenderBudget.FASTEST_SHRINK)


## The wait before retrying a level doubles on every degrade. Without a ceiling and
## a way back, one bad minute puts the next attempt minutes out and the run never
## recovers what it gave up.
func test_a_bad_patch_is_forgiven_once_the_device_proves_itself() -> void:
	var patchy := RenderBudget.new()
	patchy.begin(false, 1.0, DESKTOP)
	_run_at(patchy, 20.0, 30.0)
	assert_int(patchy.shrink).is_greater(RenderBudget.FASTEST_SHRINK)

	_run_at(patchy, 60.0, 120.0)
	assert_int(patchy.shrink).override_failure_message(
		"two clean minutes and it still will not give the pixels back"
	).is_equal(RenderBudget.FASTEST_SHRINK)


## Dropping the resolution is a worse outcome than an imperfect frame rate. A run that
## holds forty frames is a run nobody is complaining about, and spending pixels to chase
## the last twenty is how a machine with a real GPU ends up looking like a phone.
func test_a_merely_imperfect_frame_rate_keeps_its_pixels() -> void:
	var steady := RenderBudget.new()
	steady.begin(false, 1.0, DESKTOP, 60.0)
	_run_at(steady, 40.0, 60.0)
	assert_int(steady.shrink).override_failure_message(
		"forty frames is playable; the aisle at a quarter resolution is not"
	).is_equal(RenderBudget.FASTEST_SHRINK)


## A touch panel is not a phone. A laptop that has one reports everything a phone
## reports, and opening it at a third of the resolution is how a machine with a real
## GPU spent the whole run looking like one.
func test_a_touch_laptop_starts_at_full_resolution() -> void:
	var laptop := RenderBudget.new()
	laptop.begin(true, 2.0, TOUCH_LAPTOP)
	assert_int(laptop.shrink).is_equal(RenderBudget.FASTEST_SHRINK)


## The frame rate a healthy run reports is the panel's refresh, so what counts as fast
## has to be read off the panel. Judged against an absolute 58, a 50Hz display is slow
## from its first frame and gives up pixels it never needed to.
func test_a_slower_panel_is_judged_against_its_own_refresh() -> void:
	var fifty := RenderBudget.new()
	fifty.begin(false, 1.0, DESKTOP, 50.0)
	_run_at(fifty, 49.0, 30.0)
	assert_int(fifty.shrink).override_failure_message(
		"a 50Hz panel painting 49 frames is not a device in trouble"
	).is_equal(RenderBudget.FASTEST_SHRINK)


## The mirror of it: a run that opened shrunk has to be able to climb back out, and it
## cannot if the bar is set above what the display can ever report.
func test_pixels_come_back_at_the_refresh_rate_rather_than_above_it() -> void:
	var phone := RenderBudget.new()
	phone.begin(true, 3.0, PHONE, 60.0)
	var started_at := phone.shrink
	_run_at(phone, 58.0, 10.0)
	assert_int(phone.shrink).override_failure_message(
		"58 frames on a 60Hz panel is headroom, not a device at its limit"
	).is_less(started_at)
