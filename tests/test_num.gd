extends "res://tests/test_case.gd"


func test_safe_passes_finite() -> void:
	assert_eq(Num.safe(12.5), 12.5)
	assert_eq(Num.safe(-3.0), -3.0)
	assert_eq(Num.safe(1.7e308), 1.7e308)


func test_safe_nan_uses_fallback() -> void:
	assert_eq(Num.safe(NAN), 0.0)
	assert_eq(Num.safe(NAN, 7.0), 7.0)


func test_safe_inf_clamps() -> void:
	assert_eq(Num.safe(INF), Num.MAX_FLOAT)
	assert_eq(Num.safe(-INF), -Num.MAX_FLOAT)
	assert_finite(Num.safe(INF))


func test_overflow_stays_finite() -> void:
	assert_finite(Num.mul(1e300, 1e300))
	assert_finite(Num.add(Num.MAX_FLOAT, Num.MAX_FLOAT))
	assert_finite(Num.pow_safe(10.0, 400.0))
	assert_finite(Num.mul(INF, 0.0), "inf*0 is NaN -> fallback")


func test_div() -> void:
	assert_eq(Num.div(10.0, 4.0), 2.5)
	assert_eq(Num.div(1.0, 0.0), 0.0)
	assert_eq(Num.div(1.0, 0.0, -1.0), -1.0)


func test_is_valid() -> void:
	assert_true(Num.is_valid(1e300))
	assert_false(Num.is_valid(NAN))
	assert_false(Num.is_valid(INF))
