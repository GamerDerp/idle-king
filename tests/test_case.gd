extends RefCounted
## Base class for tests: `extends "res://tests/test_case.gd"`.
## Every method named test_* is run on a fresh instance. Assertions record
## failures (GDScript has no exceptions); the test continues after a failure.

var failures: Array[String] = []
var asserts: int = 0
var current_test: String = ""
## Number of engine errors (push_error etc.) this test deliberately triggers.
## The runner fails a test whose logged error count differs from this.
var expected_errors: int = 0


## Optional hooks.
func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(msg: String) -> void:
	failures.append(msg)


func assert_true(cond: bool, msg: String = "") -> void:
	asserts += 1
	if not cond:
		fail("expected true" + _ctx(msg))


func assert_false(cond: bool, msg: String = "") -> void:
	asserts += 1
	if cond:
		fail("expected false" + _ctx(msg))


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	asserts += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("expected %s, got %s%s" % [var_to_str(expected), var_to_str(actual), _ctx(msg)])


func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	asserts += 1
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		fail("did not expect %s%s" % [var_to_str(actual), _ctx(msg)])


func assert_almost(actual: float, expected: float, eps: float = 1e-9, msg: String = "") -> void:
	asserts += 1
	var tol: float = eps * maxf(1.0, maxf(absf(actual), absf(expected)))
	if is_nan(actual) or absf(actual - expected) > tol:
		fail("expected ~%s, got %s%s" % [str(expected), str(actual), _ctx(msg)])


func assert_finite(x: float, msg: String = "") -> void:
	asserts += 1
	if is_nan(x) or is_inf(x):
		fail("expected finite number, got %s%s" % [str(x), _ctx(msg)])


func assert_has(container: Variant, item: Variant, msg: String = "") -> void:
	asserts += 1
	var ok: bool = false
	if container is Dictionary:
		ok = (container as Dictionary).has(item)
	elif container is Array:
		ok = (container as Array).has(item)
	elif container is String:
		ok = (container as String).contains(str(item))
	if not ok:
		fail("%s does not contain %s%s" % [str(container), str(item), _ctx(msg)])


func _ctx(msg: String) -> String:
	return "" if msg == "" else " — " + msg
