class_name Hud
extends Control
## Screen overlay: the resource bar (resource plates: icon, value via Fmt.num, +income/с; a big loot
## portion shows as a "+N" chip with the resource icon hanging under the plate — the goal from core.next_goal(), the boss call button and a
## "?" glossary), the thin boss strip, the moat counter, one toast at a time, banners and the
## compact parchment enemy tooltip. All positions come from config/visual.json → game_view.hud.
## Pure view: purchases go through MainGame.

signal goal_clicked(goal_id: String)
signal boss_call_pressed

class Plate:
	var res: String = ""
	var panel: PanelContainer
	var icon: TextureRect
	var value: Label
	var income: Label
	var plus: Label                   ## text of the "+N" chip
	var chip: PanelContainer          ## "+N" chip under the plate (own colour + icon, income stays)
	var plus_amount: float = 0.0
	var plus_t: float = 9.0
	var bump_t: float = 9.0

var kit: ViewKit
var core: GameCore
var plates: Dictionary = {}       ## res -> Plate
var _bar_row: HBoxContainer
var _falls: Label
var _falls_bump: float = 9.0
var _boss_btn: Button
var _help_btn: Button
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
var _toast: PanelContainer
var _toast_t: float = 0.0
var _toast_life: float = 0.0
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
var _glossary: PanelContainer
var _time: float = 0.0
var _field_w: float = 900.0


func setup(view_kit: ViewKit) -> void:
	kit = view_kit
	core = kit.core
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_w = 1280.0 - kit.f("panel_width", 380)
	_build_bar()
	_build_boss()
	_build_falls()
	_build_toast()
	_build_banner()
	_build_tip()
	_build_glossary()
	for r: String in plates:   # loot chips above the boss strip
		move_child((plates[r] as Plate).chip, -1)


func _xy(key: String) -> Vector2:
	return Vector2(kit.f("hud.%s.x" % key), kit.f("hud.%s.y" % key))


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
	for r: String in core.data.resource_ids:
		var pl := Plate.new()
		pl.res = r
		pl.panel = PanelContainer.new()
		pl.panel.theme_type_variation = &"ResourcePlate"
		pl.panel.mouse_filter = Control.MOUSE_FILTER_PASS
		var h := kit.hbox(6)
		pl.icon = kit.icon(kit.res_icon(r), 32)
		pl.icon.pivot_offset = Vector2(16, 16)
		h.add_child(pl.icon)
		pl.value = kit.label("0", "CounterLabel")
		pl.value.custom_minimum_size = Vector2(kit.f("hud.plate_value_w", 64), 0)
		h.add_child(pl.value)
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(kit.f("hud.plate_income_w", 88), 32)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pl.income = kit.label("", "GoodLabel")
		pl.income.position = Vector2(0, 2)
		slot.add_child(pl.income)
		h.add_child(slot)
		# a big loot portion: a dark chip with the resource icon hanging under the plate, in the
		# resource's colour — never in the place / style of the green "+X/с" income
		pl.chip = PanelContainer.new()
		pl.chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(kit.col("soot_0"), 0.92)
		sb.border_color = kit.col("brass_1")
		sb.set_border_width_all(2)
		sb.content_margin_left = 4
		sb.content_margin_right = 8
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		pl.chip.add_theme_stylebox_override("panel", sb)
		var ch := kit.hbox(4)
		ch.add_child(kit.icon(kit.res_icon(r), 24))
		pl.plus = kit.label("", "BoldLabel")
		pl.plus.add_theme_color_override("font_color", kit.num_color(r))
		ch.add_child(pl.plus)
		pl.chip.add_child(ch)
		pl.chip.visible = false
		add_child(pl.chip)
		pl.panel.add_child(h)
		pl.panel.visible = false
		_bar_row.add_child(pl.panel)
		plates[r] = pl
	_goal = PanelContainer.new()
	_goal.theme_type_variation = &"ResourcePlate"
	_goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goal.mouse_filter = Control.MOUSE_FILTER_STOP
	_goal.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_goal.gui_input.connect(_on_goal_input)
	_bar_row.add_child(_goal)
	var gh := kit.hbox(8)
	_goal.add_child(gh)
	_goal_icon = kit.icon("res_blueprints", 32)
	gh.add_child(_goal_icon)
	_goal_text = kit.label("", "", true)
	gh.add_child(_goal_text)
	_goal_cost_icon = kit.icon("res_blueprints", 32)
	gh.add_child(_goal_cost_icon)
	_goal_cost = kit.label("", "PriceLabel")
	gh.add_child(_goal_cost)
	_goal_gauge = ProgressBar.new()
	_goal_gauge.custom_minimum_size = Vector2(kit.f("hud.goal_gauge_w", 110), 20)
	_goal_gauge.show_percentage = false
	_goal_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_goal_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gh.add_child(_goal_gauge)
	_boss_btn = Button.new()
	_boss_btn.visible = false
	_boss_btn.pressed.connect(func() -> void: boss_call_pressed.emit())
	_bar_row.add_child(_boss_btn)
	_help_btn = Button.new()
	_help_btn.text = "?"
	_help_btn.tooltip_text = tr("UI_HELP_TIP")
	_help_btn.toggle_mode = true
	_help_btn.toggled.connect(func(on: bool) -> void: _glossary.visible = on)
	_bar_row.add_child(_help_btn)


func plate_target(res: String) -> Vector2:
	var pl: Plate = plates.get(res, null)
	if pl == null or not pl.panel.visible:
		pl = plates.get("gears", null)
	if pl == null:
		return Vector2(30, 20)
	return pl.icon.get_global_rect().get_center()


## Loot arrived at a counter: bump the icon, show "+N" right of the number.
func bump(res: String, amount: float) -> void:
	var pl: Plate = plates.get(res, null)
	if pl == null:
		return
	pl.bump_t = 0.0
	if pl.plus_t > kit.f("loot.plus_window", 0.8):
		pl.plus_amount = 0.0
	pl.plus_amount += amount
	pl.plus_t = 0.0
	# steady loot is already the "+X/с" income; a "+N" appears only for an unusual chunk
	var inc: float = float(core.income.get(res, 0.0))
	if pl.plus_amount >= maxf(kit.f("hud.plus_min", 2.0), inc * kit.f("hud.plus_income_k", 2.5)):
		pl.plus.text = "+" + Fmt.num(ViewKit.shown(pl.plus_amount))
		if not pl.chip.visible:
			pl.chip.visible = true
			pl.chip.reset_size()
		_place_chip(pl)


## The "+N" chip hangs under its plate, left-aligned with the counter (slides down as it appears).
func _place_chip(pl: Plate) -> void:
	var r: Rect2 = pl.panel.get_global_rect()
	var drop: float = clampf(pl.plus_t / 0.12, 0.0, 1.0)
	var y: float = r.end.y + kit.f("hud.chip.dy", -2.0)
	var x: float = r.position.x + kit.f("hud.chip.dx", 4.0)
	# never over the boss strip's name: hang under the strip instead
	if _boss_panel.visible and Rect2(Vector2(x, y), pl.chip.size).intersects(_boss_panel.get_global_rect()):
		y = _boss_panel.get_global_rect().end.y + 2.0
	pl.chip.position = Vector2(roundf(x), roundf(y - 6.0 * (1.0 - drop)))


func bump_falls() -> void:
	_falls_bump = 0.0


func _res_visible(r: String) -> bool:
	if core.state.res(r) > 0.0 or r == "gears" or r == "blueprints":
		return true
	var reg: int = int(core.data.economy["resources"][r].get("region", -1))
	return reg >= 0 and core.mods.is_region_unlocked(reg)


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
	var show_cost: bool = not cost.is_empty() and float(cost.values()[0]) > 0.0
	_goal_cost.visible = show_cost
	_goal_cost_icon.visible = show_cost
	if show_cost:
		var r: String = str(cost.keys()[0])
		_goal_cost_icon.texture = SpriteLib.texture(kit.res_icon(r))
		_goal_cost.text = Fmt.num(float(cost[r]))
		_goal_cost.theme_type_variation = &"GoodLabel" if prog >= 1.0 else &"PriceLabel"
	var icon_name: String = "res_blueprints"
	if _goal_id.begins_with("boss:"):
		icon_name = str(kit.enemy_sprites(str(core.data.bosses[_goal_id.substr(5)]["enemy"])).get("walk", "boss_walk"))
	elif _goal_id.begins_with("node:"):
		icon_name = kit.node_icon(_goal_id)
	_goal_icon.texture = SpriteLib.texture(icon_name)
	_goal_ready = prog >= 1.0 and _goal_id.begins_with("node:")
	_goal.tooltip_text = _goal_text.text + "\n" + tr("UI_GOAL_TIP")


# --- boss strip, moat counter -----------------------------------------------------------

func _build_boss() -> void:
	_boss_panel = PanelContainer.new()
	_boss_panel.theme_type_variation = &"ResourcePlate"
	_boss_panel.position = _xy("boss_bar")
	_boss_panel.custom_minimum_size = Vector2(kit.f("hud.boss_bar.w", 596), 0)
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.visible = false
	add_child(_boss_panel)
	var h := kit.hbox(8)
	_boss_panel.add_child(h)
	_boss_name = kit.label("", "BoldLabel")
	_boss_name.add_theme_color_override("font_color", kit.col("ember_2"))
	h.add_child(_boss_name)
	_boss_gauge = ProgressBar.new()
	_boss_gauge.custom_minimum_size = Vector2(0, 20)
	_boss_gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boss_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_boss_gauge.show_percentage = false
	_boss_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_boss_gauge)
	_boss_hp = kit.label("", "CounterLabel")
	h.add_child(_boss_hp)


func _update_boss() -> void:
	var be: Battle.Enemy = core.battle.boss_enemy
	_boss_panel.visible = be != null
	if be == null:
		return
	_boss_name.text = tr(str(core.data.bosses[core.battle.boss_id]["name"]))
	_boss_hp.text = "%s / %s" % [Fmt.num(ViewKit.shown(maxf(0.0, be.hp))), Fmt.num(be.max_hp)]
	_boss_gauge.value = clampf(be.hp / be.max_hp, 0.0, 1.0) * 100.0


func _build_falls() -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = &"ResourcePlate"
	p.position = _xy("falls")
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.tooltip_text = tr("UI_FALLS_TIP")
	var h := kit.hbox(6)
	h.add_child(kit.icon("dmg_steam", 24))
	_falls = kit.label("", "DimLabel")
	h.add_child(_falls)
	p.add_child(h)
	add_child(p)


# --- toast (one at a time), banners -----------------------------------------------------

## Parchment toast: icon + title + short text. Queued; one on screen at a time.
func toast(icon_sprite: String, title: String, text: String) -> void:
	for q: Array in _toast_queue:
		if str(q[1]) == title and str(q[2]) == text:
			return
	_toast_queue.append([icon_sprite, title, text])


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.theme_type_variation = &"TooltipLikePanel"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)


func _show_toast(icon_sprite: String, title: String, text: String) -> void:
	for c: Node in _toast.get_children():
		_toast.remove_child(c)
		c.queue_free()
	var h := kit.hbox(8)
	_toast.add_child(h)
	var box := PanelContainer.new()
	box.theme_type_variation = &"InsetPanel"
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(kit.sprite_box(icon_sprite, Vector2(32, 32)))
	h.add_child(box)
	var v := kit.vbox(0)
	h.add_child(v)
	var tl := kit.label(title, "InkLabel")
	tl.add_theme_font_override("font", ViewKit.FONT_BOLD)
	tl.add_theme_color_override("font_color", kit.col("copper_1"))
	v.add_child(tl)
	if text != "":
		var bl := kit.label(text, "InkLabel")
		var w: float = kit.f("hud.toast.text_w", 300)
		if ViewKit.FONT_REGULAR.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x > w:
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bl.custom_minimum_size = Vector2(w, 0)
		v.add_child(bl)
	_toast.reset_size()
	_toast_t = 0.0
	_toast_life = kit.f("hud.toast.time", 3.0)
	_toast.visible = true


func _update_toast(delta: float) -> void:
	if not _toast.visible:
		if _toast_queue.is_empty():
			return
		var q: Array = _toast_queue.pop_front()
		_show_toast(str(q[0]), str(q[1]), str(q[2]))
	_toast_t += delta
	# shorter while more are waiting
	var life: float = _toast_life * (0.6 if not _toast_queue.is_empty() else 1.0)
	var slide: float = kit.f("hud.toast.slide", 0.2)
	var a: float = minf(clampf(_toast_t / slide, 0.0, 1.0), clampf((life - _toast_t) / slide, 0.0, 1.0))
	_toast.modulate.a = a
	_toast.reset_size()
	_toast.position = Vector2(kit.f("hud.toast.right", 892) - _toast.size.x + (1.0 - a) * 16.0,
		kit.f("hud.toast.bottom", 676) - _toast.size.y).round()
	if _toast_t >= life:
		_toast.visible = false


func banner(title: String, sub: String, color_name: String = "copper_1") -> void:
	_banner_queue.append([title, sub, color_name])
	if not _banner.visible:
		_next_banner()


func _next_banner() -> void:
	if _banner_queue.is_empty():
		return
	var q: Array = _banner_queue.pop_front()
	_banner_title.text = str(q[0])
	_banner_title.add_theme_color_override("font_color", kit.col(str(q[2])))
	_banner_sub.text = str(q[1])
	_banner_sub.visible = str(q[1]) != ""
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


func _update_banner(delta: float) -> void:
	if not _banner.visible:
		return
	_banner_t += delta
	var k_in: float = clampf(_banner_t / 0.18, 0.0, 1.0)
	var k_out: float = clampf((_banner_life - _banner_t) / 0.4, 0.0, 1.0)
	_banner.modulate.a = minf(k_in, k_out)
	_banner.reset_size()
	_banner.position = (_xy("banner") - _banner.size * 0.5 + Vector2(0, (1.0 - k_in) * -20.0)).round()
	if _banner_t >= _banner_life:
		_banner.visible = false
		_next_banner()


# --- enemy tooltip (compact; MainGame shows it after the mouse rests) and the glossary -------

func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.theme_type_variation = &"TooltipLikePanel"
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	add_child(_tip)
	_tip_box = kit.vbox(0)
	_tip.add_child(_tip_box)


func _ink(text: String, bold: bool = false) -> Label:
	var l := kit.label(text, "InkLabel")
	if bold:
		l.add_theme_font_override("font", ViewKit.FONT_BOLD)
	return l


func tip_visible() -> bool:
	return _tip.visible


func show_enemy_tip(e: Battle.Enemy, at: Vector2) -> void:
	if e == null:
		_tip.visible = false
		_tip_uid = -1
		return
	if _tip_uid != e.uid or not _tip.visible:
		_tip_uid = e.uid
		_tip.visible = true
		_fill_tip(e)
	_tip.reset_size()
	var off: Array = kit.v("hud.tip.offset", [22, 14])
	var p: Vector2 = at + Vector2(float(off[0]), float(off[1]))
	var m: float = kit.f("hud.tip.margin", 4)
	if p.x + _tip.size.x > _field_w - m:
		p.x = at.x - _tip.size.x - float(off[0])
	p.y = clampf(p.y, kit.f("hud.tip.min_y", 44), 720.0 - m - _tip.size.y)
	_tip.position = p.round()


func _fill_tip(e: Battle.Enemy) -> void:
	for c: Node in _tip_box.get_children():
		_tip_box.remove_child(c)
		c.queue_free()
	var d: Dictionary = core.data.enemies[e.type]
	var es: Dictionary = core.mods.enemy_stats.get(e.type, {})
	var traits: PackedStringArray = []
	var spd: float = float(d["speed"])
	if spd >= kit.f("traits.fast_speed", 45.0):
		traits.append(tr("TRAIT_FAST"))
	elif spd <= kit.f("traits.slow_speed", 18.0):
		traits.append(tr("TRAIT_SLOW"))
	if not (d.get("burrow", {}) as Dictionary).is_empty():
		traits.append(tr("TRAIT_BURROW_SHORT"))
	var traits2: PackedStringArray = []
	if e.front_armor > 0.0:
		traits2.append(tr("TRAIT_ARMOR") % Fmt.num(roundf(e.front_armor * 100.0)))
	if e.shield_hp > 0.0:
		traits2.append(tr("TRAIT_SHIELD"))
	if e.immune.has("slow") and e.immune.has("knockback") and e.role != "boss":
		traits2.append(tr("TRAIT_IMMUNE"))
	if not e.split.is_empty():
		traits2.append(tr("TRAIT_SPLIT"))
	if not e.charge.is_empty():
		traits2.append(tr("TRAIT_CHARGE"))
	var head := kit.hbox(8)
	head.add_child(_ink(kit.enemy_name(e.type), true))
	var hp := _ink("")
	hp.name = "Hp"
	head.add_child(hp)
	_tip_box.add_child(head)
	var row := kit.hbox(4)
	var resist: Dictionary = d.get("resist", {})
	for dt: String in resist:
		var v: float = float(resist[dt])
		row.add_child(kit.icon(kit.dmg_icon(dt), 24))
		var l := _ink(("−" if v > 0.0 else "+") + Fmt.num(absf(v) * 100.0) + "%")
		l.add_theme_color_override("font_color", kit.col("copper_1") if v > 0.0 else kit.col("verdigris_0"))
		row.add_child(l)
	if not traits.is_empty():
		row.add_child(_ink(" · ".join(traits)))
	if row.get_child_count() > 0:
		_tip_box.add_child(row)
	for t2: String in traits2:
		var tl := _ink("• " + t2)
		tl.add_theme_color_override("font_color", kit.col("copper_0"))
		_tip_box.add_child(tl)
	var loot: Dictionary = es.get("loot", d["loot"])
	_tip_box.add_child(_ink(tr("TIP_LOOT") % kit.loot_text(loot)))
	refresh_tip_hp(e)


func refresh_tip_hp(e: Battle.Enemy) -> void:
	if not _tip.visible or e == null or e.uid != _tip_uid:
		return
	var hp: Label = _tip_box.find_child("Hp", true, false) as Label
	if hp != null:
		hp.text = "%s/%s" % [Fmt.num(ViewKit.shown(maxf(0.0, e.hp))), Fmt.num(e.max_hp)]


func _build_glossary() -> void:
	_glossary = PanelContainer.new()
	_glossary.theme_type_variation = &"TooltipLikePanel"
	_glossary.mouse_filter = Control.MOUSE_FILTER_STOP
	_glossary.visible = false
	add_child(_glossary)
	var v := kit.vbox(4)
	_glossary.add_child(v)
	var t := _ink(tr("HELP_TITLE"), true)
	t.add_theme_color_override("font_color", kit.col("copper_1"))
	v.add_child(t)
	v.add_child(_ink(tr("TIP_LEGEND")))
	var leg := kit.hbox(6)
	for dt: String in ["impact", "steam", "spark", "blast"]:
		leg.add_child(kit.icon(kit.dmg_icon(dt), 24))
		var ll := kit.label(kit.dmg_type_name(dt), "BoldLabel")
		ll.add_theme_color_override("font_color", kit.num_color(dt))
		leg.add_child(ll)
	var inset := PanelContainer.new()
	inset.theme_type_variation = &"InsetPanel"
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(leg)
	v.add_child(inset)
	var w: float = kit.f("hud.glossary.w", 420)
	for key: String in ["HELP_CRIT", "HELP_LENS", "HELP_TIP", "HELP_MOAT", "HELP_KEYS"]:
		var l := _ink(tr(key))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(w, 0)
		v.add_child(l)
	_glossary.reset_size()
	_glossary.position = Vector2(kit.f("hud.glossary.right", 892) - _glossary.size.x, kit.f("hud.glossary.y", 44))


func show_glossary(on: bool) -> void:
	_help_btn.button_pressed = on
	_glossary.visible = on


# --- update ---------------------------------------------------------------------------------

## Slow refresh (every visual.game_view.ui_refresh s): texts and visibility.
func refresh() -> void:
	for r: String in plates:
		var pl: Plate = plates[r]
		var vis: bool = _res_visible(r)
		pl.panel.visible = vis
		if not vis:
			continue
		pl.value.text = Fmt.num(ViewKit.shown(core.state.res(r)))
		var inc: float = float(core.income.get(r, 0.0))
		pl.income.text = income_text(inc)
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
	_update_goal()
	_update_boss()


## "+X/с" for the plate; a trickle below `hud.income_min` (0.05/с) is hidden rather than shown as "+0/с",
## below 0.1/с it gets two decimals so a slow resource does not read as zero.
func income_text(inc: float) -> String:
	if inc < kit.f("hud.income_min", 0.05):
		return ""
	var n: String = Fmt.num(inc) if inc >= 0.1 else String.num(snappedf(inc, 0.01), 2)
	return "+%s/%s" % [n, tr("UI_SEC")]


func _process(delta: float) -> void:
	_time += delta
	var bt: float = kit.f("loot.bump_time", 0.18)
	var bs: float = kit.f("loot.bump_scale", 1.3)
	var win: float = kit.f("loot.plus_window", 0.8)
	for r: String in plates:
		var pl: Plate = plates[r]
		pl.bump_t += delta
		var k: float = clampf(pl.bump_t / bt, 0.0, 1.0)
		var s: float = lerpf(bs, 1.0, k) if pl.bump_t < bt else 1.0
		pl.icon.scale = Vector2(s, s)
		pl.plus_t += delta
		if pl.chip.visible:
			if pl.plus_t > win:
				pl.chip.visible = false
				pl.plus_amount = 0.0
			else:
				_place_chip(pl)
	_falls_bump += delta
	_falls.modulate = Color(1.4, 1.4, 1.4) if _falls_bump < 0.15 else Color.WHITE
	if _goal_ready:
		var pulse: float = 0.5 + 0.5 * sin(_time * 5.0)
		_goal.modulate = Color(1.0 + 0.25 * pulse, 1.0 + 0.2 * pulse, 1.0)
	else:
		_goal.modulate = Color.WHITE
	_update_toast(delta)
	_update_banner(delta)
