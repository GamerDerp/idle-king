class_name Hud
extends Control
## Screen overlay above the field: resource bar (icon, value via Fmt.num,
## +income/с, "+N" and a bump when loot arrives), moat counter, boss call
## button, goal bar (core.next_goal), boss HP bar, banners, toasts and the
## parchment enemy tooltip. Pure view: buys only through MainGame.

signal goal_clicked(goal_id: String)
signal boss_call_pressed

class Plate:
	var res: String = ""
	var panel: PanelContainer
	var icon: TextureRect
	var value: Label
	var income: Label
	var plus: Label
	var plus_amount: float = 0.0
	var plus_t: float = 0.0
	var bump_t: float = 9.0

class Toast:
	var node: PanelContainer
	var t: float = 0.0
	var life: float = 3.0

var kit: ViewKit
var core: GameCore
var plates: Dictionary = {}       ## res -> Plate
var _bar_row: HBoxContainer
var _falls: Label
var _falls_bump: float = 9.0
var _boss_btn: Button
var _goal: PanelContainer
var _goal_icon: TextureRect
var _goal_text: Label
var _goal_cost: Label
var _goal_cost_icon: TextureRect
var _goal_gauge: ProgressBar
var _goal_id: String = ""
var _goal_ready: bool = false
var _boss_panel: PanelContainer
var _boss_name: Label
var _boss_hp: Label
var _boss_gauge: ProgressBar
var _toast_box: VBoxContainer
var _toasts: Array[Toast] = []
var _toast_queue: Array = []
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_t: float = 0.0
var _banner_life: float = 0.0
var _banner_queue: Array = []
var _tip: PanelContainer
var _tip_box: VBoxContainer
var _tip_uid: int = -1
var _time: float = 0.0
var _field_w: float = 900.0


func setup(view_kit: ViewKit) -> void:
	kit = view_kit
	core = kit.core
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_w = 1280.0 - kit.f("panel_width", 380)
	_build_bar()
	_build_goal()
	_build_boss()
	_build_toasts()
	_build_banner()
	_build_tip()


# --- resource bar ----------------------------------------------------------------

func _build_bar() -> void:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TopBar"
	bar.position = Vector2.ZERO
	bar.size = Vector2(1280, kit.f("bar_height", 40))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_bar_row = kit.hbox(8)
	bar.add_child(_bar_row)
	var ids: Array = core.data.resource_ids.duplicate()
	for r: String in ids:
		var pl := Plate.new()
		pl.res = r
		pl.panel = PanelContainer.new()
		pl.panel.theme_type_variation = &"ResourcePlate"
		pl.panel.mouse_filter = Control.MOUSE_FILTER_PASS
		pl.panel.tooltip_text = tr(str(core.data.economy["resources"][r]["name"]))
		var h := kit.hbox(6)
		pl.icon = kit.icon(kit.res_icon(r), 32)
		pl.icon.pivot_offset = Vector2(16, 16)
		h.add_child(pl.icon)
		pl.value = kit.label("0", "CounterLabel")
		h.add_child(pl.value)
		pl.income = kit.label("", "GoodLabel")
		h.add_child(pl.income)
		pl.panel.add_child(h)
		pl.panel.visible = false
		_bar_row.add_child(pl.panel)
		pl.plus = kit.label("", "BoldLabel")
		pl.plus.add_theme_color_override("font_color", kit.num_color(r))
		pl.plus.visible = false
		add_child(pl.plus)
		plates[r] = pl
	var falls_plate := PanelContainer.new()
	falls_plate.theme_type_variation = &"ResourcePlate"
	falls_plate.mouse_filter = Control.MOUSE_FILTER_PASS
	falls_plate.tooltip_text = tr("UI_FALLS_TIP")
	var fh := kit.hbox(6)
	fh.add_child(kit.icon("dmg_steam", 24))
	_falls = kit.label("", "DimLabel")
	fh.add_child(_falls)
	falls_plate.add_child(fh)
	_bar_row.add_child(falls_plate)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_row.add_child(spacer)
	_boss_btn = Button.new()
	_boss_btn.visible = false
	_boss_btn.pressed.connect(func() -> void: boss_call_pressed.emit())
	_bar_row.add_child(_boss_btn)


func plate_target(res: String) -> Vector2:
	var pl: Plate = plates.get(res, null)
	if pl == null or not pl.panel.visible:
		pl = plates.get("gears", null)
	if pl == null:
		return Vector2(30, 20)
	return pl.icon.get_global_rect().get_center()


## Loot arrived at a counter: bump the icon, show "+N" under the plate.
func bump(res: String, amount: float) -> void:
	var pl: Plate = plates.get(res, null)
	if pl == null:
		return
	pl.bump_t = 0.0
	if pl.plus_t > kit.f("loot.plus_window", 0.8):
		pl.plus_amount = 0.0
	pl.plus_amount += amount
	pl.plus_t = 0.0
	pl.plus.text = "+" + Fmt.num(pl.plus_amount)
	pl.plus.visible = true


func bump_falls() -> void:
	_falls_bump = 0.0


func _res_visible(r: String) -> bool:
	if core.state.res(r) > 0.0 or r == "gears" or r == "blueprints":
		return true
	var reg: int = int(core.data.economy["resources"][r].get("region", -1))
	return reg >= 0 and core.mods.is_region_unlocked(reg)


# --- goal bar ----------------------------------------------------------------------

func _build_goal() -> void:
	_goal = PanelContainer.new()
	_goal.theme_type_variation = &"PlainPanel"
	_goal.position = Vector2(294, 46)
	_goal.size = Vector2(_field_w - 294 - 6, 48)
	_goal.custom_minimum_size = _goal.size
	_goal.mouse_filter = Control.MOUSE_FILTER_STOP
	_goal.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_goal.gui_input.connect(_on_goal_input)
	add_child(_goal)
	var h := kit.hbox(10)
	_goal.add_child(h)
	_goal_icon = kit.icon("res_blueprints", 32)
	h.add_child(_goal_icon)
	_goal_text = kit.label("", "", true)
	h.add_child(_goal_text)
	_goal_cost_icon = kit.icon("res_blueprints", 32)
	h.add_child(_goal_cost_icon)
	_goal_cost = kit.label("", "PriceLabel")
	h.add_child(_goal_cost)
	_goal_gauge = ProgressBar.new()
	_goal_gauge.custom_minimum_size = Vector2(112, 20)
	_goal_gauge.show_percentage = false
	_goal_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_goal_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_goal_gauge)


func _on_goal_input(ev: InputEvent) -> void:
	var mb: InputEventMouseButton = ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		goal_clicked.emit(_goal_id)


func _update_goal() -> void:
	var g: Dictionary = core.next_goal()
	_goal_id = str(g["id"])
	var args: Array = (g["args"] as Array).map(func(a: Variant) -> String: return tr(str(a)))
	var key: String = str(g["text_key"])
	_goal_text.text = tr(key) % args if not args.is_empty() else tr(key)
	var cost: Dictionary = g["cost"]
	var prog: float = float(g["progress"])
	_goal_gauge.value = prog * 100.0
	_goal_cost.visible = not cost.is_empty()
	_goal_cost_icon.visible = not cost.is_empty()
	if not cost.is_empty():
		var r: String = str(cost.keys()[0])
		_goal_cost_icon.texture = SpriteLib.texture(kit.res_icon(r))
		_goal_cost.text = Fmt.num(float(cost[r]))
		_goal_cost.theme_type_variation = &"GoodLabel" if prog >= 1.0 else &"PriceLabel"
	var icon_name: String = "res_blueprints"
	if _goal_id.begins_with("boss:"):
		icon_name = "boss_walk"
	elif _goal_id.begins_with("node:"):
		for k: Variant in core.novelty_of(_goal_id):
			icon_name = kit.behaviour_icon(str(k))
			break
	_goal_icon.texture = SpriteLib.texture(icon_name)
	_goal_ready = prog >= 1.0 and _goal_id.begins_with("node:")
	_goal.tooltip_text = tr("UI_GOAL_TIP")


# --- boss bar --------------------------------------------------------------------------

func _build_boss() -> void:
	_boss_panel = PanelContainer.new()
	_boss_panel.theme_type_variation = &"PlainPanel"
	_boss_panel.position = Vector2(294, 98)
	_boss_panel.custom_minimum_size = Vector2(_field_w - 294 - 6, 0)
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.visible = false
	add_child(_boss_panel)
	var v := kit.vbox(2)
	_boss_panel.add_child(v)
	var h := kit.hbox(8)
	v.add_child(h)
	h.add_child(kit.icon("boss_walk", 32))
	_boss_name = kit.label("", "BoldLabel", true)
	_boss_name.add_theme_color_override("font_color", kit.col("ember_2"))
	h.add_child(_boss_name)
	_boss_hp = kit.label("", "CounterLabel")
	h.add_child(_boss_hp)
	_boss_gauge = ProgressBar.new()
	_boss_gauge.custom_minimum_size = Vector2(0, 20)
	_boss_gauge.show_percentage = false
	_boss_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_boss_gauge)


func _update_boss() -> void:
	var be: Battle.Enemy = core.battle.boss_enemy
	_boss_panel.visible = be != null
	if be == null:
		return
	var bid: String = core.battle.boss_id
	_boss_name.text = tr(str(core.data.bosses[bid]["name"]))
	_boss_hp.text = "%s / %s" % [Fmt.num(maxf(0.0, be.hp)), Fmt.num(be.max_hp)]
	_boss_gauge.value = clampf(be.hp / be.max_hp, 0.0, 1.0) * 100.0
	# the goal bar shows the same fight: keep only the boss bar
	_goal.visible = false


# --- toasts & banners ---------------------------------------------------------------------

func _build_toasts() -> void:
	_toast_box = kit.vbox(6)
	_toast_box.position = Vector2(296, 0)
	_toast_box.custom_minimum_size = Vector2(_field_w - 300 - 8, 0)
	_toast_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(_toast_box)


## Parchment toast: icon + title + short text (novelty, unlocks, milestones).
func toast(icon_sprite: String, title: String, text: String) -> void:
	_toast_queue.append([icon_sprite, title, text])


func _spawn_toast(icon_sprite: String, title: String, text: String) -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = &"TooltipLikePanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := kit.hbox(10)
	p.add_child(h)
	var box := PanelContainer.new()
	box.theme_type_variation = &"InsetPanel"
	box.custom_minimum_size = Vector2(44, 44)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(kit.sprite_box(icon_sprite, Vector2(40, 40)))
	h.add_child(box)
	var v := kit.vbox(0)
	h.add_child(v)
	var tl := kit.label(title, "InkLabel")
	tl.add_theme_font_override("font", ViewKit.FONT_BOLD)
	tl.add_theme_color_override("font_color", kit.col("copper_1"))
	v.add_child(tl)
	if text != "":
		var bl := kit.label(text, "InkLabel")
		if text.length() > 34:
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bl.custom_minimum_size = Vector2(400, 0)
		v.add_child(bl)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_toast_box.add_child(p)
	var t := Toast.new()
	t.node = p
	t.life = kit.f("toast.time", 3.2)
	_toasts.append(t)
	p.modulate = Color(1, 1, 1, 0)


func banner(title: String, sub: String, color_name: String = "copper_1") -> void:
	_banner_queue.append([title, sub, color_name])
	if not _banner.visible:
		_next_banner()


func _next_banner() -> void:
	if _banner_queue.is_empty():
		return
	var q: Array = _banner_queue.pop_front()
	var title: String = str(q[0])
	var sub: String = str(q[1])
	var color_name: String = str(q[2])
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", kit.col(color_name))
	_banner_sub.text = sub
	_banner_sub.visible = sub != ""
	_banner_t = 0.0
	_banner_life = kit.f("banner.time", 2.6)
	_banner.visible = true
	_banner.reset_size()


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.theme_type_variation = &"TooltipLikePanel"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)
	var v := kit.vbox(4)
	_banner.add_child(v)
	_banner_title = kit.label("", "HeaderLabel")
	_banner_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_banner_title)
	_banner_sub = kit.label("", "InkLabel")
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_banner_sub)


# --- enemy tooltip -----------------------------------------------------------------------

func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.theme_type_variation = &"TooltipLikePanel"
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	add_child(_tip)
	_tip_box = kit.vbox(2)
	_tip.add_child(_tip_box)


func show_enemy_tip(e: Battle.Enemy, at: Vector2) -> void:
	if e == null:
		_tip.visible = false
		_tip_uid = -1
		return
	if _tip_uid != e.uid or not _tip.visible:
		_tip_uid = e.uid
		_fill_tip(e)
	_tip.visible = true
	_tip.reset_size()
	var p: Vector2 = at + Vector2(24, 18)
	if p.x + _tip.size.x > _field_w - 4:
		p.x = at.x - _tip.size.x - 24
	if p.y + _tip.size.y > 716:
		p.y = 716 - _tip.size.y
	_tip.position = p.round()


func _ink(text: String, bold: bool = false) -> Label:
	var l := kit.label(text, "InkLabel")
	if bold:
		l.add_theme_font_override("font", ViewKit.FONT_BOLD)
	return l


func _fill_tip(e: Battle.Enemy) -> void:
	for c: Node in _tip_box.get_children():
		c.queue_free()
	var d: Dictionary = core.data.enemies[e.type]
	var es: Dictionary = core.mods.enemy_stats.get(e.type, {})
	var head := kit.hbox(8)
	head.add_child(_ink(kit.enemy_name(e.type), true))
	_tip_box.add_child(head)
	_tip_box.add_child(_ink(tr("TIP_HP") % [Fmt.num(maxf(0.0, e.hp)), Fmt.num(e.max_hp)]))
	var traits: PackedStringArray = []
	var spd: float = float(d["speed"])
	if spd >= kit.f("traits.fast_speed", 45.0):
		traits.append(tr("TRAIT_FAST"))
	elif spd <= kit.f("traits.slow_speed", 18.0):
		traits.append(tr("TRAIT_SLOW"))
	if not (d.get("burrow", {}) as Dictionary).is_empty():
		traits.append(tr("TRAIT_BURROW"))
	if str(d["role"]) == "boss":
		traits.append(tr("TRAIT_BOSS"))
	if not traits.is_empty():
		_tip_box.add_child(_ink(" · ".join(traits)))
	var resist: Dictionary = d.get("resist", {})
	for dt: String in resist:
		var v: float = float(resist[dt])
		var row := kit.hbox(4)
		row.add_child(kit.icon(kit.dmg_icon(dt), 24))
		var key: String = "TIP_RESIST" if v > 0.0 else "TIP_WEAK"
		var l := _ink(tr(key) % [kit.dmg_type_name(dt), Fmt.num(absf(v) * 100.0)])
		l.add_theme_color_override("font_color", kit.col("copper_1") if v > 0.0 else kit.col("verdigris_0"))
		row.add_child(l)
		_tip_box.add_child(row)
	var loot: Dictionary = es.get("loot", d["loot"])
	_tip_box.add_child(_ink(tr("TIP_LOOT") % kit.loot_text(loot)))
	# damage-type legend: icon + the colour its numbers use
	var leg := kit.hbox(6)
	for dt2: String in ["impact", "steam", "spark", "blast"]:
		leg.add_child(kit.icon(kit.dmg_icon(dt2), 24))
		var ll := kit.label(kit.dmg_type_name(dt2), "BoldLabel")
		ll.add_theme_color_override("font_color", kit.num_color(dt2))
		leg.add_child(ll)
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_box.add_child(sep)
	_tip_box.add_child(_ink(tr("TIP_LEGEND")))
	var inset := PanelContainer.new()
	inset.theme_type_variation = &"InsetPanel"
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(leg)
	_tip_box.add_child(inset)


func refresh_tip_hp(e: Battle.Enemy) -> void:
	if _tip.visible and e != null and e.uid == _tip_uid and _tip_box.get_child_count() > 1:
		var l: Label = _tip_box.get_child(1) as Label
		if l != null:
			l.text = tr("TIP_HP") % [Fmt.num(maxf(0.0, e.hp)), Fmt.num(e.max_hp)]


# --- update ---------------------------------------------------------------------------------

## Slow refresh (every visual.game_view.ui_refresh s): texts and visibility.
func refresh() -> void:
	for r: String in plates:
		var pl: Plate = plates[r]
		var vis: bool = _res_visible(r)
		pl.panel.visible = vis
		if not vis:
			continue
		pl.value.text = Fmt.num(core.state.res(r))
		var inc: float = float(core.income.get(r, 0.0))
		pl.income.text = ("+%s/%s" % [Fmt.num(inc), tr("UI_SEC")]) if inc > 0.0 else ""
		pl.panel.tooltip_text = "%s\n%s" % [tr(str(core.data.economy["resources"][r]["name"])),
			tr("UI_INCOME_TIP") % [Fmt.num(inc), tr("UI_SEC")]]
	_falls.text = tr("UI_FALLS_N") % int(core.state.stats.get("falls", 0))
	var call_id: String = ""
	for bid: String in core.data.bosses:
		if core.can_call_boss(bid):
			call_id = bid
	_boss_btn.visible = call_id != ""
	if call_id != "":
		_boss_btn.text = tr("UI_BOSS_CALL") % tr(str(core.data.bosses[call_id]["name"]))
	_goal.visible = true
	_update_goal()
	_update_boss()


func _process(delta: float) -> void:
	_time += delta
	var bt: float = kit.f("loot.bump_time", 0.18)
	var bs: float = kit.f("loot.bump_scale", 1.3)
	for r: String in plates:
		var pl: Plate = plates[r]
		pl.bump_t += delta
		var k: float = clampf(pl.bump_t / bt, 0.0, 1.0)
		var s: float = lerpf(bs, 1.0, k) if pl.bump_t < bt else 1.0
		pl.icon.scale = Vector2(s, s)
		pl.plus_t += delta
		if pl.plus.visible:
			var win: float = kit.f("loot.plus_window", 0.8)
			var r0: Rect2 = pl.value.get_global_rect()
			pl.plus.position = Vector2(r0.position.x + 4.0, 40.0 + minf(pl.plus_t, 0.2) * 20.0).round()
			pl.plus.modulate.a = clampf((win + 0.4 - pl.plus_t) / 0.4, 0.0, 1.0)
			if pl.plus_t > win + 0.4:
				pl.plus.visible = false
				pl.plus_amount = 0.0
	_falls_bump += delta
	_falls.modulate = Color(1.4, 1.4, 1.4) if _falls_bump < 0.15 else Color.WHITE
	# goal ready: a gentle brass pulse
	if _goal_ready:
		var pulse: float = 0.5 + 0.5 * sin(_time * 5.0)
		_goal.modulate = Color(1.0 + 0.25 * pulse, 1.0 + 0.2 * pulse, 1.0)
	else:
		_goal.modulate = Color.WHITE
	_update_toasts(delta)
	_update_banner(delta)


func _update_toasts(delta: float) -> void:
	var maxn: int = int(kit.f("toast.max", 3))
	while not _toast_queue.is_empty() and _toasts.size() < maxn:
		var q: Array = _toast_queue.pop_front()
		_spawn_toast(str(q[0]), str(q[1]), str(q[2]))
	var slide: float = kit.f("toast.slide", 0.25)
	var i: int = _toasts.size() - 1
	while i >= 0:
		var t: Toast = _toasts[i]
		t.t += delta
		var a: float = clampf(t.t / slide, 0.0, 1.0)
		var out: float = clampf((t.life - t.t) / slide, 0.0, 1.0)
		t.node.modulate.a = minf(a, out)
		if t.t >= t.life:
			t.node.queue_free()
			_toasts.remove_at(i)
		i -= 1
	_toast_box.reset_size()
	_toast_box.position = Vector2(296, 716 - _toast_box.size.y)


func _update_banner(delta: float) -> void:
	if not _banner.visible:
		return
	_banner_t += delta
	var k_in: float = clampf(_banner_t / 0.18, 0.0, 1.0)
	var k_out: float = clampf((_banner_life - _banner_t) / 0.4, 0.0, 1.0)
	_banner.modulate.a = minf(k_in, k_out)
	_banner.reset_size()
	var c := Vector2((_field_w + 220.0) * 0.5, 250.0)
	_banner.position = (c - _banner.size * 0.5 + Vector2(0, (1.0 - k_in) * -20.0)).round()
	if _banner_t >= _banner_life:
		_banner.visible = false
		_next_banner()
