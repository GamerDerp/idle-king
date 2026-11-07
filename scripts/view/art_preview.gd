extends Control
## Art preview: a composed, animated mock of the battle screen (dev only, not wired to the game core).
## Shows every sprite category, the UI theme and the pixel fonts in their intended 2x layout.
## Run: godot --path . res://scenes/art_preview.tscn  (screenshot: add `-- --shot=shots/preview.png --shot-time=3`)

const TEXT_PATH := "res://scenes/art_preview_text.json"
const FONT_BOLD := preload("res://fonts/kotel_bold.fnt")
const FONT_NUMBER := preload("res://fonts/kotel_number.fnt")
const SCREEN_W := 1280
const PANEL_W := 380
const BAR_H := 40

var _txt: Dictionary = {}
var _lay: Dictionary = {}
var _world: Node2D
var _units: Node2D
var _fx: Node2D
var _lens: AnimatedSprite2D
var _king: AnimatedSprite2D
var _enemies: Array[Dictionary] = []
var _towers: Array[Dictionary] = []
var _shots: Array[Dictionary] = []
var _floaters: Array[Dictionary] = []
var _t: float = 0.0
var _king_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_txt = _load_text()
	_lay = SpriteLib.layout()
	if DevTools.has_arg("kit"):
		_build_kit()
		set_process(false)
		return
	_build_world()
	_build_ui()


func _load_text() -> Dictionary:
	var f := FileAccess.open(TEXT_PATH, FileAccess.READ)
	if f == null:
		push_error("art_preview: missing %s" % TEXT_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


# ------------------------------------------------------------------ world

func _arr2(key: String) -> Vector2:
	var a: Array = _lay.get(key, [0, 0])
	return Vector2(float(a[0]), float(a[1]))


func _road_y(x: float) -> float:
	var samples: Array = _lay.get("road_samples", [])
	if samples.is_empty():
		return float(_lay.get("road_y", 0))
	for i in range(samples.size() - 1):
		var a: Array = samples[i]
		var b: Array = samples[i + 1]
		if x <= float(b[0]):
			var t := clampf((x - float(a[0])) / maxf(1.0, float(b[0]) - float(a[0])), 0.0, 1.0)
			return lerpf(float(a[1]), float(b[1]), t)
	var last: Array = samples[samples.size() - 1]
	return float(last[1])


func _build_world() -> void:
	var sc := float(SpriteLib.scale())
	_world = Node2D.new()
	_world.name = "World"
	_world.scale = Vector2(sc, sc)
	_world.position = _arr2("screen_offset")
	add_child(_world)

	var bg := Sprite2D.new()
	bg.texture = SpriteLib.texture("battlefield_bg")
	bg.centered = false
	_world.add_child(bg)

	var moat_x: Array = _lay.get("moat_x", [0, 0])
	var size: Array = _lay.get("size", [450, 340])
	var h := int(size[1])
	var tile_h := SpriteLib.frame_size("moat_water").y
	for y in range(0, h, tile_h):
		var w := SpriteLib.make("moat_water")
		w.position = Vector2(float(moat_x[0]), float(y))
		_world.add_child(w)

	# towers on the wall
	var kinds: Array[String] = ["rifle_t0", "riveter_t1", "rifle_t2", "mortar_t1", "mortar_t2"]
	var slots: Array = _lay.get("tower_slots", [])
	for i in range(mini(slots.size(), kinds.size())):
		var s: Array = slots[i]
		var tw := SpriteLib.make(kinds[i])
		tw.position = Vector2(float(s[0]), float(s[1]))
		var tsh := SpriteLib.make("shadow_l")
		tsh.position = Vector2(2, -2)
		tsh.show_behind_parent = true
		tw.add_child(tsh)
		_world.add_child(tw)
		var base_kind := kinds[i].get_slice("_", 0)
		_towers.append({"node": tw, "kind": base_kind, "timer": 0.4 * i + 0.3,
			"period": {"rifle": 0.9, "riveter": 1.4, "mortar": 2.6}[base_kind], "flash": 0.0})

	_king = SpriteLib.make("king_idle")
	_king.position = _arr2("king_pos")
	_world.add_child(_king)

	# steam main over the water, then the curtain of sheets above it
	var vents: Array = _lay.get("steam_vents_y", [])
	var pipe_x := float(_lay.get("pipe_x", 101))
	var gate_y := float(_lay.get("gate_y", 196))
	for i in range(vents.size()):
		var vy := float(vents[i])
		if absf(vy - gate_y) < 30.0:
			continue
		var pipe := SpriteLib.make("steam_pipe_valve" if i % 4 == 1 else "steam_pipe")
		pipe.position = Vector2(pipe_x, vy)
		_world.add_child(pipe)
	for i in range(vents.size()):
		var vy := float(vents[i])
		if absf(vy - gate_y) < 30.0:
			continue
		var st := SpriteLib.make("steam_sheet", (i * 7) % 6)
		st.position = Vector2(pipe_x + 13.0, vy)
		_world.add_child(st)

	for p: Array in _lay.get("smoke_points", []):
		var sm := SpriteLib.make("chimney_smoke", _rng.randi_range(0, 3))
		sm.position = Vector2(float(p[0]), float(p[1]))
		_world.add_child(sm)

	_units = Node2D.new()
	_units.y_sort_enabled = true
	_world.add_child(_units)
	_fx = Node2D.new()
	_world.add_child(_fx)

	# enemies already on the road
	var field_x0 := float(_lay.get("field_x0", 146))
	var spawn: Array = [
		["scavenger_walk", 176.0, -8.0], ["scavenger_walk", 196.0, 7.0], ["hound_run", 226.0, -2.0],
		["junk_cart_walk", 262.0, 5.0], ["scavenger_walk", 288.0, -12.0], ["scavenger_walk", 300.0, 10.0],
		["boss_walk", 352.0, 0.0], ["hound_run", 330.0, 14.0], ["scavenger_walk", 368.0, -14.0],
		["scavenger_walk", 384.0, 12.0], ["junk_cart_walk", 412.0, -6.0], ["scavenger_walk", 432.0, 8.0],
		["hound_run", 446.0, -12.0], ["scavenger_walk", 240.0, 16.0], ["scavenger_walk", 318.0, -20.0],
	]
	for e: Array in spawn:
		_spawn_enemy(str(e[0]), float(e[1]), float(e[2]))
	assert(field_x0 > 0.0)

	_lens = SpriteLib.make("steam_lens")
	_world.add_child(_lens)


func _spawn_enemy(kind: String, x: float, lane: float) -> void:
	var n := SpriteLib.make(kind, _rng.randi_range(0, 3))
	var sh_name: String = {"boss_walk": "shadow_l", "junk_cart_walk": "shadow_l", "hound_run": "shadow_m"}.get(kind, "shadow_s")
	var sh := SpriteLib.make(sh_name)
	sh.position = Vector2(1, 0)
	sh.show_behind_parent = true
	n.add_child(sh)
	_units.add_child(n)
	var speed: float = {"scavenger_walk": 9.0, "junk_cart_walk": 5.0, "hound_run": 20.0, "boss_walk": 4.0}[kind]
	_enemies.append({"node": n, "x": x, "lane": lane, "speed": speed, "kind": kind})
	_place_enemy(_enemies[_enemies.size() - 1])


func _place_enemy(e: Dictionary) -> void:
	var n: AnimatedSprite2D = e["node"]
	var x: float = e["x"]
	n.position = Vector2(roundf(x), roundf(_road_y(x) + float(e["lane"])))


func _fx_once(sprite_name: String, pos: Vector2) -> void:
	var s := SpriteLib.make(sprite_name)
	s.position = pos.round()
	s.animation_finished.connect(s.queue_free)
	_fx.add_child(s)


func _float_text(text: String, pos: Vector2, color_name: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_NUMBER)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Config.color(color_name))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.position = pos.round()
	_fx.add_child(l)
	_floaters.append({"node": l, "age": 0.0, "y": pos.y})


func _process(delta: float) -> void:
	_t += delta
	_step_enemies(delta)
	_step_towers(delta)
	_step_shots(delta)
	_step_floaters(delta)
	_step_lens()
	_step_king(delta)


func _step_enemies(delta: float) -> void:
	var bank := float((_lay.get("bank_x", [138, 145]) as Array)[0])
	for e in _enemies:
		e["x"] = float(e["x"]) - float(e["speed"]) * delta
		if float(e["x"]) < bank + 3.0:
			var n: AnimatedSprite2D = e["node"]
			var kind: String = e["kind"]
			_fx_once(kind.get_slice("_", 0) + ("_cart" if kind.begins_with("junk") else "") + "_fall",
				Vector2(bank - 10.0, n.position.y))
			_fx_once("splash", Vector2(bank - 10.0, n.position.y))
			e["x"] = 470.0
		_place_enemy(e)


func _target() -> Dictionary:
	var best: Dictionary = {}
	for e in _enemies:
		if float(e["x"]) < 440.0 and (best.is_empty() or float(e["x"]) < float(best["x"])):
			best = e
	return best


func _step_towers(delta: float) -> void:
	for tw in _towers:
		var n: AnimatedSprite2D = tw["node"]
		tw["timer"] = float(tw["timer"]) - delta
		if float(tw["flash"]) > 0.0:
			tw["flash"] = float(tw["flash"]) - delta
			if float(tw["flash"]) <= 0.0:
				n.frame = 0
		if float(tw["timer"]) <= 0.0:
			tw["timer"] = float(tw["period"])
			var tgt := _target()
			if tgt.is_empty():
				continue
			n.frame = 1
			tw["flash"] = 0.12
			var kind: String = tw["kind"]
			var from := n.position + Vector2(14, -18)
			if kind == "mortar":
				from = n.position + Vector2(12, -26)
			var tn: AnimatedSprite2D = tgt["node"]
			var dur: float = {"rifle": 0.35, "riveter": 0.45, "mortar": 1.1}[kind]
			var to := tn.position + Vector2(-float(tgt["speed"]) * dur, -6.0)
			var proj: String = {"rifle": "bullet", "riveter": "rivet", "mortar": "shell"}[kind]
			var p := SpriteLib.make(proj)
			p.position = from
			_fx.add_child(p)
			_shots.append({"node": p, "from": from, "to": to, "t": 0.0, "dur": dur, "kind": kind})


func _step_shots(delta: float) -> void:
	var done: Array[Dictionary] = []
	for s in _shots:
		s["t"] = float(s["t"]) + delta
		var k := clampf(float(s["t"]) / float(s["dur"]), 0.0, 1.0)
		var from: Vector2 = s["from"]
		var to: Vector2 = s["to"]
		var pos := from.lerp(to, k)
		if str(s["kind"]) == "mortar":
			pos.y -= sin(k * PI) * 60.0
		var n: AnimatedSprite2D = s["node"]
		n.position = pos.round()
		if k >= 1.0:
			done.append(s)
			n.queue_free()
			var nums: Array = _txt.get("dmg_numbers", ["1"])
			if str(s["kind"]) == "mortar":
				_fx_once("explosion", to + Vector2(0, 6))
				_fx_once("scrap_burst", to + Vector2(0, 6))
				_float_text(str(nums[2]), to + Vector2(-4, -26), "ember_2")
				var coin := SpriteLib.make("gear_coin_fly")
				coin.position = (to + Vector2(6, -10)).round()
				_fx.add_child(coin)
				_floaters.append({"node": coin, "age": 0.0, "y": coin.position.y, "coin": true})
			else:
				_fx_once("hit_spark", to)
				_float_text(str(nums[_rng.randi_range(0, 1)]), to + Vector2(-3, -16), "parchment_2")
	for s in done:
		_shots.erase(s)


func _step_floaters(delta: float) -> void:
	var done: Array[Dictionary] = []
	for f in _floaters:
		f["age"] = float(f["age"]) + delta
		var n: Node2D = f["node"] as Node2D
		var c: Control = f["node"] as Control
		var age: float = f["age"]
		var y := float(f["y"]) - minf(age, 0.6) * 18.0
		if n != null:
			n.position.y = roundf(y)
		elif c != null:
			c.position.y = roundf(y)
		if age > 0.9:
			done.append(f)
			(f["node"] as Node).queue_free()
	for f in done:
		_floaters.erase(f)


func _step_lens() -> void:
	# automatic mode: slow oval over the road (design §5)
	var cx := 262.0
	var cy := _road_y(cx)
	_lens.position = Vector2(cx + cos(_t * 0.5) * 34.0, cy + sin(_t * 1.0) * 14.0).round()


func _step_king(delta: float) -> void:
	_king_timer += delta
	if _king_timer > 5.0 and _king.sprite_frames != SpriteLib.sprite_frames("king_tea"):
		_king.sprite_frames = SpriteLib.sprite_frames("king_tea")
		_king.play(&"default")
	elif _king_timer > 7.0:
		_king_timer = 0.0
		_king.sprite_frames = SpriteLib.sprite_frames("king_idle")
		_king.play(&"default")


# ------------------------------------------------------------------ UI

func _icon(sprite_name: String, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = SpriteLib.texture(sprite_name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


func _label(text: String, variation: String = "", clip: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = StringName(variation)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if clip:  # shrinkable: never forces the panel wider than its design width
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _build_ui() -> void:
	# top resource bar
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBar"
	bar.position = Vector2.ZERO
	bar.size = Vector2(SCREEN_W, BAR_H)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for r: Array in _txt.get("res", []):
		var plate := PanelContainer.new()
		plate.theme_type_variation = &"ResourcePlate"
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.add_child(_icon(str(r[0]), 32))
		h.add_child(_label(str(r[1]), "CounterLabel"))
		if str(r[2]) != "":
			h.add_child(_label(str(r[2]), "GoodLabel"))
		plate.add_child(h)
		row.add_child(plate)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var boss := Button.new()
	boss.text = str(_txt.get("boss_button", ""))
	row.add_child(boss)

	# goal line over the field
	var goal := PanelContainer.new()
	goal.theme_type_variation = &"PlainPanel"
	goal.position = Vector2(300, 48)
	goal.custom_minimum_size = Vector2(580, 0)
	add_child(goal)
	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", 12)
	goal.add_child(gh)
	var gl := _label(str(_txt.get("goal", "")), "", true)
	gh.add_child(gl)
	var bar2 := ProgressBar.new()
	bar2.custom_minimum_size = Vector2(120, 20)
	bar2.value = 62
	bar2.show_percentage = false
	bar2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gh.add_child(bar2)

	# tooltip mock pinned near a hound
	var tip := PanelContainer.new()
	tip.theme_type_variation = &"TooltipLikePanel"
	tip.position = Vector2(560, 560)
	add_child(tip)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tip.add_child(tv)
	var tt := _label(str(_txt.get("tooltip_title", "")), "InkLabel")
	tt.add_theme_font_override("font", FONT_BOLD)
	tv.add_child(tt)
	tv.add_child(_label(str(_txt.get("tooltip_body", "")), "InkLabel"))

	# right shop panel
	var tabs := TabContainer.new()
	tabs.clip_contents = true
	tabs.position = Vector2(SCREEN_W - PANEL_W, BAR_H)
	tabs.size = Vector2(PANEL_W, 720 - BAR_H)
	add_child(tabs)
	var names: Array = _txt.get("tabs", ["1", "2", "3"])
	for i in range(names.size()):
		var page: Control
		if i == 0:
			page = _shop_page()
		else:
			page = Control.new()
		page.name = "Tab%d" % i
		tabs.add_child(page)
		tabs.set_tab_title(i, str(names[i]))


func _shop_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	v.add_child(_label(str(_txt.get("header", "")), "HeaderLabel"))
	v.add_child(HSeparator.new())
	for c: Dictionary in _txt.get("cards", []):
		v.add_child(_card(c))
	return scroll


func _card(c: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = &"CardAffordable" if bool(c.get("affordable", false)) else &"CardPanel"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"InsetPanel"
	slot.custom_minimum_size = Vector2(64, 76)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tower := str(c.get("tower", ""))
	var pic := TextureRect.new()
	pic.texture = SpriteLib.texture(tower if tower != "" else "steam_lens")
	pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.custom_minimum_size = Vector2(64, 80) if tower != "" else Vector2(64, 64)
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not bool(c.get("affordable", false)):
		pic.modulate = Color(1, 1, 1, 0.45)   # dim on the dark slot: "not yet"
	slot.add_child(pic)
	h.add_child(slot)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	v.add_child(_label(str(c.get("name", "")), "BoldLabel", true))
	v.add_child(_label(str(c.get("level", "")), "DimLabel", true))
	var eff := HBoxContainer.new()
	eff.add_theme_constant_override("separation", 4)
	eff.add_child(_icon(str(c.get("dmg", "dmg_impact")), 24))
	eff.add_child(_label(str(c.get("effect", "")), "GoodLabel", true))
	v.add_child(eff)
	var buy := HBoxContainer.new()
	buy.add_theme_constant_override("separation", 4)
	buy.add_child(_icon("res_gears", 32))
	var price := _label(str(c.get("price", "")), "PriceLabel" if bool(c.get("affordable", false)) else "BadLabel")
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.add_child(price)
	var b := Button.new()
	b.text = str(c.get("button", ""))
	b.disabled = not bool(c.get("affordable", false))
	buy.add_child(b)
	v.add_child(buy)
	return p


# ------------------------------------------------------------------ UI kit page (--kit)

func _build_kit() -> void:
	var k: Dictionary = _txt.get("kit", {})
	var bg := ColorRect.new()
	bg.color = Config.color("soot_1")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var cols := HBoxContainer.new()
	cols.position = Vector2(16, 12)
	cols.add_theme_constant_override("separation", 20)
	add_child(cols)

	var c1 := VBoxContainer.new()
	c1.add_theme_constant_override("separation", 6)
	c1.custom_minimum_size = Vector2(400, 0)
	cols.add_child(c1)
	c1.add_child(_label(str(k.get("title", "")), "HeaderLabel"))
	c1.add_child(_label(str(k.get("bold", "")), "BoldLabel"))
	var reg := _label(str(k.get("regular", "")))
	reg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c1.add_child(reg)
	c1.add_child(_label(str(k.get("dim", "")), "DimLabel"))
	for v: String in ["GoodLabel", "BadLabel", "PriceLabel"]:
		c1.add_child(_label(str(k.get({"GoodLabel": "good", "BadLabel": "bad", "PriceLabel": "price"}[v], "")), v))
	var brow := GridContainer.new()
	brow.columns = 2
	brow.add_theme_constant_override("h_separation", 8)
	brow.add_theme_constant_override("v_separation", 8)
	c1.add_child(brow)
	var bnames: Array = k.get("buttons", ["", "", "", ""])
	var buttons: Array[Button] = []
	for i in range(4):
		var b := Button.new()
		b.text = str(bnames[i])
		b.custom_minimum_size = Vector2(180, 0)
		brow.add_child(b)
		buttons.append(b)
	buttons[1].add_theme_stylebox_override("normal", buttons[1].get_theme_stylebox("hover"))
	buttons[2].add_theme_stylebox_override("normal", buttons[2].get_theme_stylebox("pressed"))
	buttons[2].add_theme_color_override("font_color", buttons[2].get_theme_color("font_pressed_color"))
	buttons[3].disabled = true
	var gnames: Array = k.get("gauges", ["", "", ""])
	var gvars: Array[String] = ["", "SteamGauge", "TealGauge"]
	var gvals: Array[float] = [62.0, 35.0, 88.0]
	for i in range(3):
		var gr := HBoxContainer.new()
		gr.add_theme_constant_override("separation", 10)
		var gl := _label(str(gnames[i]), "DimLabel")
		gl.custom_minimum_size = Vector2(110, 0)
		gr.add_child(gl)
		var pb := ProgressBar.new()
		pb.theme_type_variation = StringName(gvars[i])
		pb.custom_minimum_size = Vector2(260, 20)
		pb.value = gvals[i]
		pb.show_percentage = false
		gr.add_child(pb)
		c1.add_child(gr)
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 6)
	for n: String in ["res_gears", "res_blueprints", "res_coal", "res_copper", "res_springs", "res_ether", "res_seal"]:
		irow.add_child(_icon(n, 32))
	c1.add_child(irow)
	var irow2 := HBoxContainer.new()
	irow2.add_theme_constant_override("separation", 10)
	for n: String in ["dmg_impact", "dmg_steam", "dmg_spark", "dmg_blast"]:
		irow2.add_child(_icon(n, 24))
	for n: String in ["gear_coin", "blueprint"]:
		irow2.add_child(_icon(n, 32))
	c1.add_child(irow2)

	var c2 := VBoxContainer.new()
	c2.add_theme_constant_override("separation", 10)
	c2.custom_minimum_size = Vector2(380, 0)
	cols.add_child(c2)
	var pnl := PanelContainer.new()
	pnl.add_child(_label(str(k.get("panel", "")), "BoldLabel"))
	c2.add_child(pnl)
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 10)
	for pair: Array in [["CardPanel", "card"], ["CardAffordable", "card_aff"]]:
		var cp := PanelContainer.new()
		cp.theme_type_variation = StringName(str(pair[0]))
		cp.add_child(_label(str(k.get(str(pair[1]), ""))))
		cr.add_child(cp)
	c2.add_child(cr)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 10)
	var plate := PanelContainer.new()
	plate.theme_type_variation = &"ResourcePlate"
	var ph := HBoxContainer.new()
	ph.add_child(_icon("res_gears", 32))
	ph.add_child(_label(str(k.get("plate", "")), "CounterLabel"))
	plate.add_child(ph)
	pr.add_child(plate)
	var ins := PanelContainer.new()
	ins.theme_type_variation = &"InsetPanel"
	ins.add_child(_label(str(k.get("inset", "")), "DimLabel"))
	pr.add_child(ins)
	var badge := PanelContainer.new()
	badge.theme_type_variation = &"Badge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(_label(str(k.get("badge", "")), "BoldLabel"))
	pr.add_child(badge)
	c2.add_child(pr)
	var tip := PanelContainer.new()
	tip.theme_type_variation = &"TooltipLikePanel"
	tip.add_child(_label(str(k.get("tooltip", "")), "InkLabel"))
	c2.add_child(tip)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(380, 230)
	c2.add_child(tabs)
	var tnames: Array = k.get("tabs", ["1", "2", "3"])
	for i in range(tnames.size()):
		var page: Control
		if i == 0:
			var sc := ScrollContainer.new()
			sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			var lv := VBoxContainer.new()
			for item: Variant in k.get("list", []):
				lv.add_child(_label(str(item)))
				lv.add_child(HSeparator.new())
			sc.add_child(lv)
			page = sc
		else:
			page = Control.new()
		page.name = "K%d" % i
		tabs.add_child(page)
		tabs.set_tab_title(i, str(tnames[i]))

	# sprites at world scale (2x), animated
	var stage := Node2D.new()
	stage.scale = Vector2(2, 2)
	stage.position = Vector2(840, 10)
	add_child(stage)
	var x := 0.0
	var y := 26.0
	for n: String in ["scavenger_walk", "hound_run", "junk_cart_walk", "boss_walk", "king_idle"]:
		var s := SpriteLib.make(n)
		var fs := SpriteLib.frame_size(n)
		s.position = Vector2(x, y) + SpriteLib.anchor(n)
		stage.add_child(s)
		x += float(fs.x) + 6.0
		if x > 180.0:
			x = 0.0
			y += 36.0
	y += 40.0
	for row: int in range(3):
		x = 0.0
		for base: String in ["rifle", "riveter", "mortar"]:
			var n := "%s_t%d" % [base, row]
			var s := SpriteLib.make(n)
			s.position = Vector2(x, y + row * 42.0) + SpriteLib.anchor(n)
			stage.add_child(s)
			x += 36.0
	var lens := SpriteLib.make("steam_lens")
	lens.position = Vector2(150, y + 50) + Vector2(4, 4)
	stage.add_child(lens)
	var fx_names: Array[String] = ["explosion", "scrap_burst", "splash", "steam_puff", "scavenger_fall",
		"hound_fall", "junk_cart_fall", "boss_fall", "hit_spark", "gear_coin_fly"]
	for i: int in range(fx_names.size()):
		var e := SpriteLib.make(fx_names[i])
		e.position = Vector2(14.0 + (i % 5) * 40.0, y + 150.0 + floorf(i / 5.0) * 44.0)
		e.sprite_frames.set_animation_loop(&"default", true)
		e.play(&"default")
		stage.add_child(e)
