class_name NumFmt
extends RefCounted
## Pure number/time formatting (no autoload dependency). The `Fmt` autoload
## forwards to these functions; tests and headless tools may call them directly.

const SUFFIXES: Array[String] = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
const SMALL_LIMIT := 1000.0
const INF_TEXT := "∞"
const SECONDS_PER_MINUTE := 60
const SECONDS_PER_HOUR := 3600
const SECONDS_PER_DAY := 86400


## 12, 12.5, 999, 1.23K, 12.3K, 123K, 1.2M ... 999Dc, then 5.60e35.
## NaN -> "0", +/-inf -> "∞"/"-∞". Never fails.
static func num(x: float) -> String:
	if is_nan(x):
		return "0"
	if is_inf(x):
		return INF_TEXT if x > 0.0 else "-" + INF_TEXT
	if x < 0.0:
		var pos := num(-x)
		return pos if pos == "0" else "-" + pos
	if x < SMALL_LIMIT:
		var r := roundf(x * 10.0) / 10.0
		if r < SMALL_LIMIT:
			return _small(r)
	var e := _exp10(x)
	var tier := e / 3
	if tier < SUFFIXES.size():
		var digits_before := e - tier * 3 + 1  # 1..3
		var decimals := 3 - digits_before
		var m := _round_to(x / pow(10.0, tier * 3), decimals)
		if m >= SMALL_LIMIT:
			tier += 1
			m = _round_to(m / SMALL_LIMIT, 2)
			decimals = 2
		if tier < SUFFIXES.size():
			return _strip_zeros(_fixed(m, decimals)) + SUFFIXES[tier]
	return sci(x)


## Scientific notation with 3 significant digits: 5.60e35.
static func sci(x: float) -> String:
	if is_nan(x):
		return "0"
	if is_inf(x):
		return INF_TEXT if x > 0.0 else "-" + INF_TEXT
	if x == 0.0:
		return "0"
	var sign := "-" if x < 0.0 else ""
	var a := absf(x)
	var e := _exp10(a)
	var m := _round_to(a / pow(10.0, e), 2)
	if m >= 10.0:
		m /= 10.0
		e += 1
	return "%s%se%d" % [sign, _fixed(m, 2), e]


## "1ч 05м", "3м 12с", "45с" (and "2д 03ч" for days) via tr keys TIME_*.
static func time(seconds: float) -> String:
	if is_nan(seconds) or seconds < 0.0:
		seconds = 0.0
	if is_inf(seconds):
		return INF_TEXT
	var s := int(floorf(minf(seconds, 9.0e15)))
	if s >= SECONDS_PER_DAY:
		return _tr("TIME_DH") % [s / SECONDS_PER_DAY, (s % SECONDS_PER_DAY) / SECONDS_PER_HOUR]
	if s >= SECONDS_PER_HOUR:
		return _tr("TIME_HM") % [s / SECONDS_PER_HOUR, (s % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE]
	if s >= SECONDS_PER_MINUTE:
		return _tr("TIME_MS") % [s / SECONDS_PER_MINUTE, s % SECONDS_PER_MINUTE]
	return _tr("TIME_S") % [s]


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))


static func _small(r: float) -> String:
	if is_equal_approx(r, roundf(r)):
		return str(int(roundf(r)))
	return _fixed(r, 1)


## floor(log10(a)) for a > 0, corrected for floating error.
static func _exp10(a: float) -> int:
	var e := int(floorf(log(a) / log(10.0)))
	if pow(10.0, e) > a:
		e -= 1
	elif e < 308 and pow(10.0, e + 1) <= a:
		e += 1
	return e


static func _round_to(v: float, decimals: int) -> float:
	var k := pow(10.0, decimals)
	return roundf(v * k) / k


static func _fixed(v: float, decimals: int) -> String:
	return ("%." + str(decimals) + "f") % v


static func _strip_zeros(s: String) -> String:
	if s.find(".") < 0:
		return s
	s = s.rstrip("0")
	if s.ends_with("."):
		s = s.left(s.length() - 1)
	return s
