extends Control
## Minimal DEBUG view of the core loop (part C1): colored shapes for the
## fortress, moat, enemies, towers, projectiles and the steam lens; text
## counters; a list of purchase buttons. The real view (C2) replaces this.
## Mouse over the field = lens follows the cursor.

const FIELD_TOP: float = 40.0
const PANEL_X: float = 900.0
const REFRESH: float = 0.25

var _core: GameCore
var _floaters: Array = []           ## [{pos, text, color, t}]
var _blasts: Array = []             ## [{pos, r, t}]
var _splashes: Array = []           ## [{pos, t}]
var _top: Label
var _list: VBoxContainer
var _buttons: Dictionary = {}       ## offer id -> Button
var _boss_btn: Button
var _refresh_t: float = 0.0
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_font = ThemeDB.fallback_font
	_core = Game.start()
	_build_ui()
	print("Main scene ready (locale %s)" % TranslationServer.get_locale())


func _build_ui() -> void:
	_top = Label.new()
	_top.position = Vector2(8, 8)
	_top.add_theme_color_override("font_color", Config.color("parchment_2"))
	_top.add_theme_font_size_override("font_size", 15)
	add_child(_top)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(PANEL_X + 8, FIELD_TOP + 8)
	scroll.size = Vector2(1280 - PANEL_X - 16, 720 - FIELD_TOP - 16)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(scroll.size.x - 12, 0)
	scroll.add_child(_list)
	_boss_btn = Button.new()
	_boss_btn.text = tr("UI_BOSS_CALL_AGAIN")
	_boss_btn.pressed.connect(_on_boss)
	_list.add_child(_boss_btn)


func _process(delta: float) -> void:
	var b: Battle = _core.battle
	if Game.bot == null:
		var mp: Vector2 = get_local_mouse_position()
		var over: bool = mp.x < PANEL_X and mp.y > FIELD_TOP and b.in_field(mp) \
			and get_viewport().get_visible_rect().has_point(get_viewport().get_mouse_position())
		_core.set_cursor(mp, over)
	for ev: Dictionary in _core.drain_events():
		_on_event(ev)
	for arr: Array in [_floaters, _blasts, _splashes]:
		for f: Dictionary in arr:
			f["t"] = float(f["t"]) + delta
	_floaters = _floaters.filter(func(f: Dictionary) -> bool: return float(f["t"]) < 0.9)
	_blasts = _blasts.filter(func(f: Dictionary) -> bool: return float(f["t"]) < 0.3)
	_splashes = _splashes.filter(func(f: Dictionary) -> bool: return float(f["t"]) < 0.6)
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH
		_refresh_ui()
	queue_redraw()


func _on_event(ev: Dictionary) -> void:
	match str(ev["type"]):
		"enemy_killed":
			var loot: Dictionary = ev["loot"]
			_floaters.append({"pos": ev["pos"], "text": "+" + Fmt.num(float(loot.get("gears", 0.0))),
				"color": Config.color("brass_3"), "t": 0.0})
		"enemy_hit":
			if bool(ev["crit"]):
				_floaters.append({"pos": ev["pos"] + Vector2(0, -14), "text": Fmt.num(float(ev["amount"])),
					"color": Config.color("ember_2"), "t": 0.0})
		"shell_exploded":
			_blasts.append({"pos": ev["pos"], "r": float(ev["radius"]), "t": 0.0})
		"enemy_fell_in_moat":
			_splashes.append({"pos": ev["pos"], "t": 0.0})


func _refresh_ui() -> void:
	var s: GameState = _core.state
	var parts: PackedStringArray = []
	for r: String in ["gears", "blueprints"]:
		parts.append("%s %s (+%s/%s)" % [tr("RES_" + r.to_upper()), Fmt.num(s.res(r)),
			Fmt.num(float(_core.income.get(r, 0.0))), tr("UI_SEC")])
	parts.append("%s %d" % [tr("UI_KILLS"), int(s.stats["kills"])])
	parts.append("%s %d" % [tr("UI_FALLS"), int(s.stats["falls"])])
	parts.append("%s: %s" % [tr("UI_LENS"), tr("UI_LENS_" + _core.battle.lens_mode.to_upper())])
	parts.append(Fmt.time(s.time))
	_top.text = "   ".join(parts)
	var ids: Array[String] = _core.offer_ids()
	for id: String in _buttons.keys():
		if not ids.has(id):
			(_buttons[id] as Button).queue_free()
			_buttons.erase(id)
	for id in ids:
		var btn: Button = _buttons.get(id, null)
		if btn == null:
			btn = Button.new()
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_font_size_override("font_size", 13)
			btn.pressed.connect(_on_buy.bind(id))
			_list.add_child(btn)
			_buttons[id] = btn
		var price: Dictionary = _core.price(id)
		var pp: PackedStringArray = []
		for r: String in price:
			pp.append("%s %s" % [Fmt.num(float(price[r])), tr("RES_" + r.to_upper() + "_SHORT")])
		btn.text = "%s  [%d/%d]  %s" % [tr(_name_key(id)), _core.level_of(id), _core.max_of(id), ", ".join(pp)]
		btn.tooltip_text = tr(_desc_key(id))
		btn.disabled = not _core.can_buy(id)
	var can_boss: bool = false
	for bid: String in _core.data.bosses:
		can_boss = can_boss or _core.can_call_boss(bid)
	_boss_btn.visible = can_boss


func _name_key(id: String) -> String:
	var p: PackedStringArray = GameCore.split_id(id)
	match p[0]:
		"tower":
			return str(_core.data.towers[p[1]].get("name", id))
		"upg":
			return str(_core.data.upgrades[p[1]].get("name", id))
	return GameData.node_name_key(p[1])


func _desc_key(id: String) -> String:
	var p: PackedStringArray = GameCore.split_id(id)
	match p[0]:
		"tower":
			return str(_core.data.towers[p[1]].get("desc", ""))
		"upg":
			return str(_core.data.upgrades[p[1]].get("name", id)) + "_DESC"
	return GameData.node_desc_key(p[1])


func _on_buy(id: String) -> void:
	_core.buy(id)
	_refresh_ui()


func _on_boss() -> void:
	for bid: String in _core.data.bosses:
		if _core.can_call_boss(bid):
			_core.call_boss(bid)
	_refresh_ui()


func _draw() -> void:
	var b: Battle = _core.battle
	var c := func(n: String) -> Color: return Config.color(n)
	draw_rect(Rect2(0, 0, 1280, 720), c.call("soot_1"))
	draw_rect(Rect2(0, FIELD_TOP, 220, 720 - FIELD_TOP), c.call("iron_0"))                  # fortress
	draw_rect(Rect2(220, FIELD_TOP, b.moat_x - 220, 720 - FIELD_TOP), c.call("teal_0"))     # moat
	if _core.mods.moat_dps > 0.0:
		draw_rect(Rect2(b.moat_x, FIELD_TOP, float(_core.data.waves.get("curtain_width", 50)), 720 - FIELD_TOP),
			Color(c.call("steam_2"), 0.18))
	draw_rect(Rect2(b.moat_x, b.y_min - 20, b.spawn_x - b.moat_x, b.y_max - b.y_min + 40), c.call("soot_2"))  # road
	draw_rect(Rect2(PANEL_X, 0, 1280 - PANEL_X, 720), c.call("soot_0"))
	for s: Dictionary in _splashes:
		draw_circle(s["pos"], 6.0 + 20.0 * float(s["t"]), Color(c.call("steam_3"), 0.6 - float(s["t"])), false, 2.0)
	for tw: Battle.Tower in b.towers:
		var col: Color = Config.color(str(_core.data.towers[tw.type].get("color", "brass_2")))
		var sz: float = 18.0 if tw.type == "mortar" else 14.0
		draw_rect(Rect2(tw.pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)
	for e: Battle.Enemy in b.enemies:
		var col: Color = Config.color(str(_core.data.enemies[e.type].get("color", "parchment_1")))
		var r: float = e.radius
		draw_rect(Rect2(e.pos - Vector2(r, r), Vector2(r, r) * 2.0), col)
		if e.scald_t > 0.0:
			draw_rect(Rect2(e.pos - Vector2(r, r), Vector2(r, r) * 2.0), c.call("steam_3"), false, 2.0)
		if e.hp < e.max_hp:
			var w: float = maxf(16.0, r * 2.0)
			draw_rect(Rect2(e.pos + Vector2(-w * 0.5, -r - 6), Vector2(w, 3)), c.call("soot_0"))
			draw_rect(Rect2(e.pos + Vector2(-w * 0.5, -r - 6), Vector2(w * e.hp / e.max_hp, 3)), c.call("ember_2"))
	for p: Battle.Projectile in b.projectiles:
		match p.kind:
			"rivet":
				draw_line(p.pos - p.dir * 8.0, p.pos, c.call("copper_3"), 2.0)
			"shell":
				var k: float = clampf(p.t / p.flight, 0.0, 1.0)
				draw_circle(p.pos + Vector2(0, -sin(PI * k) * 70.0), 4.0, c.call("iron_3"))
			_:
				draw_circle(p.pos, 2.0, c.call("brass_3"))
	for bl: Dictionary in _blasts:
		draw_circle(bl["pos"], float(bl["r"]), Color(c.call("ember_2"), 0.5 - float(bl["t"])))
	var lens_col: Color = c.call("brass_3") if b.lens_mode == "manual" else c.call("steam_2")
	draw_circle(b.lens_pos, float(_core.mods.lens["radius"]), lens_col, false, 2.0)
	if b.boss_enemy != null:
		var be: Battle.Enemy = b.boss_enemy
		draw_rect(Rect2(300, FIELD_TOP + 8, 560, 10), c.call("soot_0"))
		draw_rect(Rect2(300, FIELD_TOP + 8, 560 * be.hp / be.max_hp, 10), c.call("ember_1"))
		draw_string(_font, Vector2(300, FIELD_TOP + 34), tr(str(_core.data.bosses[b.boss_id]["name"])),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c.call("parchment_2"))
	for f: Dictionary in _floaters:
		var col2: Color = f["color"]
		col2.a = 1.0 - float(f["t"]) / 0.9
		draw_string(_font, f["pos"] + Vector2(-8, -16 - 30.0 * float(f["t"])), str(f["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col2)
