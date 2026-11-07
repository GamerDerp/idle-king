extends "res://tests/test_case.gd"
## Generated art: manifest is consistent, sprite files load, fonts and theme load.


func test_manifest_entries_load() -> void:
	var m: Dictionary = SpriteLib.manifest()
	var sprites: Dictionary = m.get("sprites", {})
	assert_true(sprites.size() >= 50, "sprite count %d" % sprites.size())
	for n: String in sprites:
		var e: Dictionary = sprites[n]
		var tex: Texture2D = load(str(e["file"]))
		assert_true(tex != null, "texture %s" % n)
		if tex == null:
			continue
		var fs: Array = e["frame_size"]
		assert_eq(tex.get_width(), int(fs[0]) * int(e["frames"]), "strip width %s" % n)
		assert_eq(tex.get_height(), int(fs[1]), "strip height %s" % n)


func test_battlefield_layout() -> void:
	var lay := SpriteLib.layout()
	var size: Array = lay.get("size", [])
	assert_eq(Vector2i(int(size[0]), int(size[1])), Vector2i(450, 340))
	assert_eq((lay.get("tower_slots", []) as Array).size(), 5)
	var bg := SpriteLib.texture("battlefield_bg")
	assert_eq(bg.get_width(), 450)


func test_sprite_frames_and_make() -> void:
	var s := SpriteLib.make("scavenger_walk")
	assert_eq(s.sprite_frames.get_frame_count(&"default"), 4)
	assert_eq(s.offset, -SpriteLib.anchor("scavenger_walk"))
	s.free()


func test_fonts_and_theme_load() -> void:
	for f: String in ["regular", "bold", "title"]:
		var font: FontFile = load("res://fonts/kotel_%s.fnt" % f)
		assert_true(font != null, f)
		if font != null:
			assert_true(font.has_char("Ж".unicode_at(0)), "%s has Cyrillic" % f)
			assert_true(font.has_char("№".unicode_at(0)), "%s has №" % f)
	var theme: Theme = load("res://themes/main_theme.tres")
	assert_true(theme != null)
	if theme != null:
		assert_true(theme.has_stylebox("normal", "Button"))
		assert_true(theme.has_stylebox("panel", "CardAffordable"))
		assert_eq(theme.default_font_size, 24)
