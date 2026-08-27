extends RefCounted
class_name RenderBudget

## RenderBudget : RefCounted
##
## Chooses how far to divide the world's render resolution, from measured frame
## time rather than from a device name. An iPad reports itself as a Mac and every
## Android GPU shares one user-agent, so the name is not evidence; the frame clock
## is. This also means hardware neither of us has ever run still gets a sane
## answer.
##
## Only the 3D world scales. The HUD is React, drawn by the browser outside the
## canvas, so nothing here can make text soft.

## Bounds on the divisor. 4 is a quarter resolution per axis, a sixteenth of the
## fragments, and past that the aisle stops reading as a corridor.
const FASTEST_SHRINK := 1
const SLOWEST_SHRINK := 4

## Where a run has to fall before pixels are worth giving up.
##
## Not a share of the refresh rate. Missing the panel's cadence is not the same as being
## unplayable: this is a train you walk down at a stroll, and forty frames of it reads
## as fine where a quarter-resolution aisle reads as broken. Judged at three quarters of
## the refresh, every machine that merely failed to pin 60 went soft for nothing.
const DEGRADE_BELOW_FPS := 24.0

## A slow panel needs the floor brought down with it, or a 30Hz display never reaches a
## fixed 24 and hands back pixels it was coping without.
const DEGRADE_CEILING_SHARE := 0.6

## Headroom is still measured against the panel, because that is the only thing a
## browser can report: it paints on the compositor's clock and never beats the refresh.
## An absolute bar above it is one no display can clear, so whatever level a run opened
## at would be the level it died at.
const UPGRADE_ABOVE_SHARE := 0.90

## What to measure against when the platform will not say. Web reports nothing useful
## for the refresh rate, and 60 is what a browser paints at unless told otherwise.
const ASSUMED_REFRESH_HZ := 60.0
const SLOWEST_CREDIBLE_REFRESH_HZ := 24.0
const FASTEST_CREDIBLE_REFRESH_HZ := 240.0

## A screen no bigger than this on its long edge is held in the hands. A touchscreen on
## its own is not evidence of one: a Windows laptop with a touch panel reports exactly
## what a phone reports, and starting it at a third of the resolution is how a machine
## with a real GPU ends up looking like a phone.
const HANDHELD_LONGEST_EDGE_PX := 1400

## A frame this long is a stall, not a workload: a scene streaming in, a tab coming
## back from the background, the browser collecting garbage. Feeding one to the
## average drops a level for something that is already over.
const STALL_SECONDS := 0.25

## Frame rate is noisy per-frame, so decisions run on a smoothed value sampled on
## this cadence.
const SAMPLE_SECONDS := 0.5
const SMOOTHING := 0.15

## Giving up pixels must be quick, because the player is watching it stutter now.
## Taking them back must be slow, or the scale oscillates every time a carriage
## comes into view. Quick is not instant: at 1.5 a single busy moment mid-aisle was
## enough, and the player saw the whole run go soft a frame after it.
const SECONDS_SLOW_BEFORE_DEGRADE := 3.0
const SECONDS_FAST_BEFORE_UPGRADE := 6.0

## Each degrade doubles the wait before that level may be tried again, so a device
## that genuinely cannot hold a level stops re-testing it every few seconds.
const UPGRADE_PENALTY_SECONDS := 20.0

## Doubling with nothing to stop it is how one bad minute costs the rest of the run:
## four degrades put the next attempt three minutes out and it never came back.
const LONGEST_UPGRADE_PENALTY := 60.0

## Hold a clean frame rate this long and the doubling is forgiven a step, so a
## device that had one bad patch is not judged on it forever.
const SECONDS_CLEAN_BEFORE_FORGIVEN := 30.0

var shrink := FASTEST_SHRINK

var _refresh_hz := ASSUMED_REFRESH_HZ
var _smoothed_fps := ASSUMED_REFRESH_HZ
var _seconds_since_sample := 0.0
var _seconds_slow := 0.0
var _seconds_fast := 0.0
var _upgrade_locked_for := 0.0
var _upgrade_penalty := UPGRADE_PENALTY_SECONDS
var _seconds_clean := 0.0


## Starts where the device is likely to cope, so the first seconds of a run are
## not the worst ones, and fixes what a healthy frame rate is worth on this display.
##
## Only a handheld opens below full resolution: one at two or more device pixels per
## CSS pixel is drawing several million fragments for a screen held at arm's length and
## almost never holds its refresh at full resolution. Everything else starts at full
## resolution and is judged on its measured frame rate like anything else.
func begin(has_touchscreen: bool, pixel_ratio: float, screen: Vector2i,
		refresh_hz: float = 0.0) -> void:
	_refresh_hz = refresh_hz if refresh_hz >= SLOWEST_CREDIBLE_REFRESH_HZ \
		and refresh_hz <= FASTEST_CREDIBLE_REFRESH_HZ else ASSUMED_REFRESH_HZ
	_smoothed_fps = _refresh_hz
	var handheld := has_touchscreen \
		and maxi(screen.x, screen.y) <= HANDHELD_LONGEST_EDGE_PX
	if handheld and pixel_ratio >= 2.0:
		shrink = 3
	elif handheld:
		shrink = 2
	else:
		shrink = FASTEST_SHRINK


## The frame rate a run has to beat to keep what it is holding.
func degrade_below() -> float:
	return minf(DEGRADE_BELOW_FPS, _refresh_hz * DEGRADE_CEILING_SHARE)


## The frame rate a run has to hold before it is given pixels back.
func upgrade_above() -> float:
	return _refresh_hz * UPGRADE_ABOVE_SHARE


## Feeds one frame in and returns the divisor to use now. The return is the whole
## answer, so the caller never has to ask twice or track state of its own.
func sample(frames_per_second: float, delta: float) -> int:
	if delta > STALL_SECONDS:
		return shrink
	_smoothed_fps = lerpf(_smoothed_fps, frames_per_second, SMOOTHING)
	_upgrade_locked_for = maxf(_upgrade_locked_for - delta, 0.0)
	_seconds_since_sample += delta
	if _seconds_since_sample < SAMPLE_SECONDS:
		return shrink
	_seconds_since_sample = 0.0

	if _smoothed_fps < degrade_below():
		_seconds_fast = 0.0
		_seconds_slow += SAMPLE_SECONDS
	elif _smoothed_fps > upgrade_above():
		_seconds_slow = 0.0
		_seconds_fast += SAMPLE_SECONDS
	else:
		# the band between the two is where we want to sit, so neither timer runs
		_seconds_slow = 0.0
		_seconds_fast = 0.0

	_forgive_a_clean_stretch()

	if _seconds_slow >= SECONDS_SLOW_BEFORE_DEGRADE and shrink < SLOWEST_SHRINK:
		shrink += 1
		_seconds_slow = 0.0
		_seconds_clean = 0.0
		_upgrade_locked_for = _upgrade_penalty
		_upgrade_penalty = minf(_upgrade_penalty * 2.0, LONGEST_UPGRADE_PENALTY)
	elif _seconds_fast >= SECONDS_FAST_BEFORE_UPGRADE and shrink > FASTEST_SHRINK \
			and is_zero_approx(_upgrade_locked_for):
		shrink -= 1
		_seconds_fast = 0.0
	return shrink


## The doubling is what stops a device re-testing a level it cannot hold. It is also
## what turns one stall into a run that never recovers, so a long clean stretch takes
## a step back off it.
func _forgive_a_clean_stretch() -> void:
	if _smoothed_fps <= upgrade_above():
		_seconds_clean = 0.0
		return
	_seconds_clean += SAMPLE_SECONDS
	if _seconds_clean < SECONDS_CLEAN_BEFORE_FORGIVEN:
		return
	_seconds_clean = 0.0
	_upgrade_penalty = maxf(_upgrade_penalty * 0.5, UPGRADE_PENALTY_SECONDS)


## Antialiasing costs a multiple of whatever the resolution already costs, so it
## is the first thing to go and the last to come back. At a divided resolution
## there is little left for it to fix anyway.
func msaa() -> Viewport.MSAA:
	if shrink >= 3:
		return Viewport.MSAA_DISABLED
	if shrink == 2:
		return Viewport.MSAA_2X
	return Viewport.MSAA_4X


## What the panel shows, so a slow phone can say why it looks soft.
func describe() -> String:
	var names := {
		Viewport.MSAA_DISABLED: "off",
		Viewport.MSAA_2X: "2x",
		Viewport.MSAA_4X: "4x",
	}
	return "1/%d, msaa %s" % [shrink, names.get(msaa(), "?")]
