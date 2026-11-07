extends "res://tests/test_case.gd"


func test_loads_all_json() -> void:
	var errors: Array = []
	var data: Dictionary = ConfigLoader.load_dir("res://config", errors)
	assert_eq(errors.size(), 0, str(errors))
	assert_has(data, "economy")
	assert_has(data, "visual")
	assert_has(data, "palette")


func test_path_value() -> void:
	var d: Dictionary = {"a": {"b": {"c": 5}}}
	assert_eq(ConfigLoader.get_path_value(d, "a.b.c"), 5)
	assert_eq(ConfigLoader.get_path_value(d, "a.x", 9), 9)


func test_palette_colors_valid() -> void:
	var data: Dictionary = ConfigLoader.load_file("res://config/palette.json")
	var colors: Dictionary = data["colors"]
	assert_true(colors.size() >= 24 and colors.size() <= 32, "palette size %d" % colors.size())
	for k in colors:
		assert_true(Color.html_is_valid(str(colors[k])), k)


func test_translations_present() -> void:
	TranslationServer.set_locale("ru")
	assert_ne(String(TranslationServer.translate("GAME_TITLE")), "GAME_TITLE", "ru translation loaded")
	TranslationServer.set_locale("en")
	assert_eq(String(TranslationServer.translate("GAME_TITLE")), "Idle King")
	TranslationServer.set_locale("ru")


func test_malformed_json_reported_not_crash() -> void:
	var dir: String = "user://test_bad_config"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("broken.json"), FileAccess.WRITE)
	f.store_string("{ \"a\": 1, }}")
	f.close()
	var g := FileAccess.open(dir.path_join("good.json"), FileAccess.WRITE)
	g.store_string("{\"b\": 2}")
	g.close()
	expected_errors = 1
	print("    (one 'malformed JSON' error below is expected)")
	var errors: Array = []
	var data: Dictionary = ConfigLoader.load_dir(dir, errors)
	assert_eq(errors, ["broken.json"])
	assert_eq(data.keys(), ["good"])
	DirAccess.remove_absolute(dir.path_join("broken.json"))
	DirAccess.remove_absolute(dir.path_join("good.json"))
