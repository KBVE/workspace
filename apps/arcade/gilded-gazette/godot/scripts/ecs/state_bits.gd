class_name StateBits

## GENERATED FILE - DO NOT EDIT.
##
## Source: shared/state.json + shared/events.json
## Regenerate: npm run gen (from vite/). Runs automatically on dev and build.

## Where the game as a whole is; replaces sniffing scene paths on the React side.
enum RunState {
	BOOTING = 0,
	MENU = 1,
	PLAYING = 2,
	PAUSED = 3,
	ENDED = 4,
}

## Which kind of world the player is in right now. A murder mystery moves between flat
## interior scenes and spatial sections, and both React and the ECS need to know which
## without guessing from the scene path.
enum WorldMode {
	NONE = 0,
	MODE_2D = 1,
	MODE_3D = 2,
}

## What kind of fact a journal entry records. The journal is the run's memory: who spoke
## to whom, what was used on what, where the player has been. Each entry carries a ULID,
## so entries sort by when they happened without a clock field being trusted or
## compared.
enum JournalKind {
	ENTERED = 0,
	TALKED = 1,
	SHOWED = 2,
	USED = 3,
	FOUND = 4,
	ACCUSED = 5,
}

## Per frame player state! Packed because systems test these thousands of times a
## second; a bit test is a single AND against a register but overkill for now, damn
## safari.
const PLAYER_ALIVE := 1 << 0
const PLAYER_MOVING := 1 << 1
const PLAYER_ATTACKING := 1 << 2
const PLAYER_INVULNERABLE := 1 << 3

## True when every bit in [param flags] is set in [param value].
static func has_all(value: int, flags: int) -> bool:
	return (value & flags) == flags

## True when any bit in [param flags] is set in [param value].
static func has_any(value: int, flags: int) -> bool:
	return (value & flags) != 0

# Debug decoders. A packed int is unreadable in a log or a breakpoint, which is
# the one real cost of packing state - so the names travel with the layout and
# are generated from the same source rather than retyped.

const _RUN_STATE_NAMES := {0: "BOOTING", 1: "MENU", 2: "PLAYING", 3: "PAUSED", 4: "ENDED"}
## Human-readable name for a [enum RunState] value.
static func run_state_name(value: int) -> String:
	return _RUN_STATE_NAMES.get(value, "UNKNOWN(%d)" % value)

const _WORLD_MODE_NAMES := {0: "NONE", 1: "MODE_2D", 2: "MODE_3D"}
## Human-readable name for a [enum WorldMode] value.
static func world_mode_name(value: int) -> String:
	return _WORLD_MODE_NAMES.get(value, "UNKNOWN(%d)" % value)

const _JOURNAL_KIND_NAMES := {0: "ENTERED", 1: "TALKED", 2: "SHOWED", 3: "USED", 4: "FOUND", 5: "ACCUSED"}
## Human-readable name for a [enum JournalKind] value.
static func journal_kind_name(value: int) -> String:
	return _JOURNAL_KIND_NAMES.get(value, "UNKNOWN(%d)" % value)

const _PLAYER_FLAGS_NAMES := {1: "ALIVE", 2: "MOVING", 4: "ATTACKING", 8: "INVULNERABLE"}
## Renders a packed [code]PlayerFlags[/code] value as "ALIVE|MOVING", or "NONE".
static func describe_player_flags(value: int) -> String:
	var parts: PackedStringArray = []
	for bit: int in _PLAYER_FLAGS_NAMES:
		if value & bit:
			parts.append(_PLAYER_FLAGS_NAMES[bit])
	var known: int = 0
	for bit: int in _PLAYER_FLAGS_NAMES:
		known |= bit
	if value & ~known:
		parts.append("UNKNOWN(0x%x)" % (value & ~known))
	return "|".join(parts) if not parts.is_empty() else "NONE"
