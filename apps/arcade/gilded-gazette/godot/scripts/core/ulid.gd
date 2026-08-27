class_name Ulid

## Ulid identifier that sorts b time.
## 48 bits for ms timestamp && 80 bits random, base32 baby.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const TIME_CHARS := 10
const RAND_CHARS := 16
const RAND_HALF_CHARS := RAND_CHARS / 2
const LENGTH := TIME_CHARS + RAND_CHARS
const RAND_HALF_MAX := (1 << 40) - 1

static var _last_ms: int = -1
static var _rand_high: int = 0
static var _rand_low: int = 0

## [param ms] overrides the clock, for tests only.
static func generate(ms: int = -1) -> String:
	# `x * 1000.0 as int` casts the 1000.0, not the product
	var timestamp_ms: int = ms if ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)

	if timestamp_ms == _last_ms:
		# increment, not redraw, or ids minted in one ms come back out of order
		_rand_low += 1
		if _rand_low > RAND_HALF_MAX:
			_rand_low = 0
			_rand_high += 1
			if _rand_high > RAND_HALF_MAX:
				_last_ms += 1
				timestamp_ms = _last_ms
				_seed_random()
	else:
		_last_ms = timestamp_ms
		_seed_random()

	return _encode(timestamp_ms, TIME_CHARS) \
		+ _encode(_rand_high, RAND_HALF_CHARS) \
		+ _encode(_rand_low, RAND_HALF_CHARS)


## Milliseconds since the epoch, or -1 if [param id] is malformed.
static func timestamp_of(id: String) -> int:
	if not is_valid(id):
		return -1
	var ms := 0
	for i in range(TIME_CHARS):
		ms = ms * 32 + ALPHABET.find(id[i])
	return ms


static func is_valid(id: String) -> bool:
	if id.length() != LENGTH:
		return false
	for symbol: String in id:
		if ALPHABET.find(symbol) < 0:
			return false
	return true


static func _seed_random() -> void:
	_rand_high = _random_half()
	_rand_low = _random_half()


## randi_range is 32-bit; asked for a 40-bit span it returned the bounds.
static func _random_half() -> int:
	return ((randi() << 8) ^ randi()) & RAND_HALF_MAX


static func _encode(value: int, width: int) -> String:
	var text := ""
	var remaining := value
	for i in range(width):
		text = ALPHABET[remaining & 31] + text
		remaining >>= 5
	return text
