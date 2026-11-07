class_name Num
extends RefCounted
## Numeric safety helpers. All game numbers are 64-bit floats (see D-005);
## these guard against NaN/inf ever reaching state or the screen.

## Largest finite double.
const MAX_FLOAT := 1.7976931348623157e308


## NaN -> fallback; +inf/-inf -> +/-MAX_FLOAT; finite values unchanged.
static func safe(x: float, fallback: float = 0.0) -> float:
	if is_nan(x):
		return fallback
	if is_inf(x):
		return MAX_FLOAT if x > 0.0 else -MAX_FLOAT
	return x


## True for normal finite numbers (not NaN, not inf).
static func is_valid(x: float) -> bool:
	return not is_nan(x) and not is_inf(x)


## Safe arithmetic: results are always finite.
static func add(a: float, b: float) -> float:
	return safe(a + b)


static func mul(a: float, b: float) -> float:
	return safe(a * b)


## Division that returns `fallback` for b == 0 or invalid results.
static func div(a: float, b: float, fallback: float = 0.0) -> float:
	if b == 0.0:
		return fallback
	return safe(a / b, fallback)


## Safe power: pow overflow becomes MAX_FLOAT instead of inf.
static func pow_safe(base: float, exponent: float) -> float:
	return safe(pow(base, exponent))
