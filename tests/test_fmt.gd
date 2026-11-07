extends "res://tests/test_case.gd"


func _f(x: float) -> String:
	return NumFmt.num(x)


func test_small_numbers() -> void:
	assert_eq(_f(0.0), "0")
	assert_eq(_f(12.0), "12")
	assert_eq(_f(12.5), "12.5")
	assert_eq(_f(12.04), "12")
	assert_eq(_f(999.0), "999")
	assert_eq(_f(0.25), "0.3")
	assert_eq(_f(0.04), "0")


func test_thousands_boundary() -> void:
	assert_eq(_f(999.96), "1K", "rounds up into K")
	assert_eq(_f(1000.0), "1K")
	assert_eq(_f(1200.0), "1.2K")
	assert_eq(_f(1234.0), "1.23K")
	assert_eq(_f(12345.0), "12.3K")
	assert_eq(_f(123456.0), "123K")
	assert_eq(_f(999499.0), "999K")
	assert_eq(_f(999500.0), "1M", "rounds up into M")


func test_all_suffixes() -> void:
	var sfx: Array[String] = ["K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
	for i in sfx.size():
		var x: float = 3.4 * pow(10.0, 3 * (i + 1))
		assert_eq(_f(x), "3.4" + sfx[i], "tier %d" % (i + 1))


func test_above_dc_is_scientific() -> void:
	assert_eq(_f(999e33), "999Dc")
	assert_eq(_f(5.6e35), "560Dc")
	assert_eq(_f(1e36), "1.00e36")
	assert_eq(_f(5.6e40), "5.60e40")
	assert_eq(_f(9.999e40), "1.00e41")


func test_huge_values() -> void:
	assert_eq(_f(1e300), "1.00e300")
	assert_eq(_f(1.7e308), "1.70e308")
	assert_eq(_f(Num.MAX_FLOAT), "1.80e308")


func test_negative() -> void:
	assert_eq(_f(-12.5), "-12.5")
	assert_eq(_f(-1234.0), "-1.23K")
	assert_eq(_f(-1e300), "-1.00e300")
	assert_eq(_f(-0.01), "0", "no negative zero")


func test_nan_inf_never_crash() -> void:
	assert_eq(_f(NAN), "0")
	assert_eq(_f(INF), "∞")
	assert_eq(_f(-INF), "-∞")
	assert_eq(NumFmt.sci(NAN), "0")
	assert_eq(NumFmt.sci(INF), "∞")


func test_sci() -> void:
	assert_eq(NumFmt.sci(5.6e35), "5.60e35")
	assert_eq(NumFmt.sci(-2.0), "-2.00e0")
	assert_eq(NumFmt.sci(0.0), "0")


func test_many_magnitudes_have_three_sig_digits() -> void:
	for e in range(3, 36):
		var s: String = _f(1.23456 * pow(10.0, e))
		var digits: String = ""
		for ch in s:
			if ch >= "0" and ch <= "9":
				digits += ch
		assert_eq(digits, "123", "e=%d -> %s" % [e, s])


func test_time_ru() -> void:
	TranslationServer.set_locale("ru")
	assert_eq(NumFmt.time(45.0), "45с")
	assert_eq(NumFmt.time(192.0), "3м 12с")
	assert_eq(NumFmt.time(3900.0), "1ч 05м")
	assert_eq(NumFmt.time(2.0 * 86400.0 + 3.0 * 3600.0), "2д 03ч")
	assert_eq(NumFmt.time(0.0), "0с")
	assert_eq(NumFmt.time(-5.0), "0с")
	assert_eq(NumFmt.time(NAN), "0с")
	assert_eq(NumFmt.time(INF), "∞")
	assert_true(NumFmt.time(1e300).length() > 0)


func test_time_en() -> void:
	TranslationServer.set_locale("en")
	assert_eq(NumFmt.time(3900.0), "1h 05m")
	TranslationServer.set_locale("ru")


func test_fmt_autoload_forwards() -> void:
	var fmt: Node = Engine.get_main_loop().root.get_node_or_null("Fmt")
	assert_true(fmt != null, "Fmt autoload present")
	if fmt:
		assert_eq(fmt.call("num", 1234.0), "1.23K")
