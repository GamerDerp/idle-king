class_name ShopPanel
extends TabContainer
## Right panel (~380 px): «Цеха» — towers (count / limit, buy) with their gear
## upgrades; «Карта» — available map nodes (cost, kind icon, effect text) and
## mutually exclusive choices shown side by side with both options' stats.
## Every card shows "было → станет" from core.preview_mods, is highlighted when
## affordable, dimmed when not, and shows time-to-afford when it is long.
## Buying goes through core.buy(); the juicy feedback is driven by core events
## (MainGame), the panel adds the button sparks.

signal bought(id: String, at: Vector2)

class Card:
	var id: String = ""
	var kind: String = ""             ## tower / upg / node / choice
	var panel: PanelContainer
	var pic: Control
	var level: Label
	var effects: VBoxContainer
	var price_icon: TextureRect
	var price: Label
	var ttl: Label
	var button: Button
	var affordable: int = -1
	var diff_sig: String = ""
	var flash_t: float = 9.0

var kit: ViewKit
var core: GameCore
var cards: Dictionary = {}           ## id -> Card (choice columns are cards too)
var _shop_list: VBoxContainer
var _map_list: VBoxContainer
var _shop_scroll: ScrollContainer
var _map_scroll: ScrollContainer
var _shop_sig: String = ""
var _map_sig: String = ""
var _diff_cache: Dictionary = {}     ## id -> Array of diff lines (for the current state)
var _diff_state: String = ""


func setup(view_kit: ViewKit) -> void:
	kit = view_kit
	core = kit.core
	clip_contents = true
	position = Vector2(1280.0 - kit.f("panel_width", 380), kit.f("bar_height", 40))
	size = Vector2(kit.f("panel_width", 380), 720.0 - kit.f("bar_height", 40))
	_shop_scroll = _make_page("Shop")
	_shop_list = _shop_scroll.get_child(0) as VBoxContainer
	_map_scroll = _make_page("Map")
	_map_list = _map_scroll.get_child(0) as VBoxContainer
	set_tab_title(0, tr("UI_TAB_SHOP"))
	set_tab_title(1, tr("UI_TAB_MAP"))
	tab_changed.connect(_on_tab_changed)


func _on_tab_changed(_tab: int) -> void:
	for id: String in cards:
		_update_card(cards[id])


func _make_page(page_name: String) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = page_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := kit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	add_child(sc)
	return sc


# --- data --------------------------------------------------------------------------

## "было → станет" lines, cached until the next purchase / boss victory.
func diff(id: String) -> Array:
	var sig: String = "%d:%d" % [int(core.state.stats.get("purchases", 0)), core.mods.era]
	if sig != _diff_state:
		_diff_state = sig
		_diff_cache.clear()
	if not _diff_cache.has(id):
		_diff_cache[id] = kit.diff_lines(id)
	return _diff_cache[id]


func _node_kind(id: String) -> String:
	return str(core.data.nodes[GameCore.split_id(id)[1]].get("kind", ""))


func _node_icon(id: String) -> String:
	var nid: String = GameCore.split_id(id)[1]
	var kind: String = _node_kind(id)
	var icon_name: String = str(kit.v("node_kind_icons." + kind, "res_blueprints"))
	var effects: Array = core.data.node_effects(nid)
	if icon_name == "enemy" or icon_name == "tower":
		for ef: Dictionary in effects:
			var tgt: String = str(ef.get("target", ""))
			if core.data.enemies.has(tgt):
				return str(kit.enemy_sprites(tgt).get("walk", "scavenger_walk"))
			if core.data.towers.has(tgt):
				return kit.tower_sprite(tgt, core.tower_tier(tgt))
		return "res_blueprints"
	return icon_name


# --- building ------------------------------------------------------------------------

func _clear(list: VBoxContainer, kinds: Array) -> void:
	var drop: Array = []
	for id: String in cards:
		if kinds.has((cards[id] as Card).kind):
			drop.append(id)
	for id: String in drop:
		cards.erase(id)
	for c: Node in list.get_children():
		c.queue_free()


func _header(list: VBoxContainer, text: String, hint: String = "") -> void:
	list.add_child(kit.label(text, "HeaderLabel"))
	if hint != "":
		var h := kit.label(hint, "DimLabel")
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(h)
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(sep)


func _card_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"CardPanel"
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _buy_row(c: Card, button_text: String) -> HBoxContainer:
	var row := kit.hbox(4)
	c.price_icon = kit.icon("res_gears", 32)
	row.add_child(c.price_icon)
	c.price = kit.label("", "PriceLabel", true)
	c.price.custom_minimum_size = Vector2(64, 0)
	row.add_child(c.price)
	c.ttl = kit.label("", "DimLabel")
	c.ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(c.ttl)
	c.button = Button.new()
	c.button.text = button_text
	c.button.mouse_filter = Control.MOUSE_FILTER_PASS
	c.button.pressed.connect(_on_buy.bind(c.id))
	row.add_child(c.button)
	return row


func _tower_card(t: String) -> Card:
	var c := Card.new()
	c.id = "tower:" + t
	c.kind = "tower"
	c.panel = _card_panel()
	var outer := kit.vbox(2)
	c.panel.add_child(outer)
	var h := kit.hbox(8)
	outer.add_child(h)
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"InsetPanel"
	slot.custom_minimum_size = Vector2(68, 84)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.pic = kit.sprite_box(kit.tower_sprite(t, core.tower_tier(t)), Vector2(64, 80))
	slot.add_child(c.pic)
	h.add_child(slot)
	var v := kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_row := kit.hbox(4)
	name_row.add_child(kit.label(kit.tower_name(t), "BoldLabel", true))
	name_row.add_child(kit.icon(kit.dmg_icon(str(core.mods.tower_stats[t]["dmg_type"])), 24))
	v.add_child(name_row)
	c.level = kit.label("", "DimLabel", true)
	v.add_child(c.level)
	c.effects = kit.vbox(0)
	v.add_child(c.effects)
	outer.add_child(_buy_row(c, tr("UI_BUY")))
	cards[c.id] = c
	return c


func _upg_card(u: String) -> Card:
	var c := Card.new()
	c.id = "upg:" + u
	c.kind = "upg"
	c.panel = _card_panel()
	var v := kit.vbox(0)
	c.panel.add_child(v)
	var top := kit.hbox(6)
	var t: String = str(core.data.upgrades[u]["tower"])
	var eff_type: String = ""
	for ef: Dictionary in core.data.upgrades[u]["effects"]:
		eff_type = str(ef["type"])
	c.pic = kit.icon(kit.dmg_icon(str(core.mods.tower_stats[t]["dmg_type"])) if eff_type == "tower_dmg_mult" else "gear_coin", 24)
	top.add_child(c.pic)
	top.add_child(kit.label(tr(str(core.data.upgrades[u]["name"])), "BoldLabel", true))
	c.level = kit.label("", "DimLabel")
	top.add_child(c.level)
	v.add_child(top)
	c.effects = kit.vbox(0)
	v.add_child(c.effects)
	v.add_child(_buy_row(c, tr("UI_UPGRADE")))
	cards[c.id] = c
	return c


func _node_card(id: String) -> Card:
	var c := Card.new()
	c.id = id
	c.kind = "node"
	c.panel = _card_panel()
	var v := kit.vbox(2)
	c.panel.add_child(v)
	var top := kit.hbox(8)
	var box := PanelContainer.new()
	box.theme_type_variation = &"InsetPanel"
	box.custom_minimum_size = Vector2(48, 48)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.pic = kit.sprite_box(_node_icon(id), Vector2(44, 44))
	box.add_child(c.pic)
	top.add_child(box)
	var tv := kit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nl := kit.label(tr(kit.name_key(id)), "BoldLabel", true)
	if _node_kind(id) == "boss":
		nl.add_theme_color_override("font_color", kit.col("ember_2"))
	tv.add_child(nl)
	c.level = kit.label("", "DimLabel", true)
	tv.add_child(c.level)
	top.add_child(tv)
	v.add_child(top)
	c.effects = kit.vbox(0)
	v.add_child(c.effects)
	var btn_text: String = tr("UI_BUY")
	if _node_kind(id) == "boss":
		btn_text = tr("UI_CALL")
	elif core.price(id).values().all(func(x: Variant) -> bool: return float(x) <= 0.0):
		btn_text = tr("UI_TAKE")
	v.add_child(_buy_row(c, btn_text))
	cards[c.id] = c
	return c


func _choice_card(ids: Array) -> PanelContainer:
	var p := _card_panel()
	p.theme_type_variation = &"CardAffordable"
	var v := kit.vbox(4)
	p.add_child(v)
	var hl := kit.label(tr("UI_CHOICE_TITLE"), "BoldLabel")
	hl.add_theme_color_override("font_color", kit.col("brass_3"))
	v.add_child(hl)
	var hint := kit.label(tr("UI_CHOICE_HINT"), "DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var cols := kit.hbox(6)
	v.add_child(cols)
	for i in ids.size():
		var id: String = str(ids[i])
		if i > 0:
			var vs := VSeparator.new()
			vs.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cols.add_child(vs)
		var c := Card.new()
		c.id = id
		c.kind = "choice"
		c.panel = p
		var col := kit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_PASS
		col.tooltip_text = _tooltip(id)
		cols.add_child(col)
		var top := kit.hbox(4)
		c.pic = kit.sprite_box(_node_icon(id), Vector2(44, 44))
		top.add_child(c.pic)
		col.add_child(top)
		var nl := kit.label(tr(kit.name_key(id)), "BoldLabel")
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(nl)
		c.level = kit.label("", "DimLabel")
		c.level.visible = false
		col.add_child(c.level)
		c.effects = kit.vbox(0)
		col.add_child(c.effects)
		var row := kit.vbox(2)
		c.price_icon = kit.icon("res_blueprints", 32)
		var pr := kit.hbox(4)
		pr.add_child(c.price_icon)
		c.price = kit.label("", "PriceLabel")
		pr.add_child(c.price)
		row.add_child(pr)
		c.ttl = kit.label("", "DimLabel")
		row.add_child(c.ttl)
		c.button = Button.new()
		c.button.text = tr("UI_CHOOSE")
		c.button.mouse_filter = Control.MOUSE_FILTER_PASS
		c.button.pressed.connect(_on_buy.bind(c.id))
		row.add_child(c.button)
		col.add_child(row)
		cards[c.id] = c
	return p


func _rebuild_shop(ids: Array[String]) -> void:
	_clear(_shop_list, ["tower", "upg"])
	_header(_shop_list, tr("UI_SHOP_HEADER"))
	for t: String in core.data.towers:
		if not core.mods.unlocked_towers.has(t):
			continue
		_shop_list.add_child(_tower_card(t).panel)
		for u: String in core.data.upgrades:
			if str(core.data.upgrades[u]["tower"]) == t and ids.has("upg:" + u):
				_shop_list.add_child(_upg_card(u).panel)


func _rebuild_map(ids: Array[String]) -> void:
	_clear(_map_list, ["node", "choice"])
	_header(_map_list, tr("UI_MAP_HEADER"), tr("UI_MAP_HINT"))
	var nodes: Array = []
	for id in ids:
		if id.begins_with("node:"):
			nodes.append(id)
	# choices first (they are decisions), then by cost
	nodes.sort_custom(func(a: String, b: String) -> bool:
		var ca: bool = not core.data.node_excludes(GameCore.split_id(a)[1]).is_empty()
		var cb: bool = not core.data.node_excludes(GameCore.split_id(b)[1]).is_empty()
		if ca != cb:
			return ca
		return GameCore._cost_sum(core.price(a)) < GameCore._cost_sum(core.price(b)))
	var done: Dictionary = {}
	for id: String in nodes:
		if done.has(id):
			continue
		var nid: String = GameCore.split_id(id)[1]
		var group: Array = [id]
		for x: Variant in core.data.node_excludes(nid):
			var xid: String = "node:" + str(x)
			if nodes.has(xid):
				group.append(xid)
		for g: Variant in group:
			done[str(g)] = true
		if group.size() > 1:
			_map_list.add_child(_choice_card(group))
		else:
			_map_list.add_child(_node_card(id).panel)
	if nodes.is_empty():
		var l := kit.label(tr("UI_MAP_EMPTY"), "DimLabel")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_map_list.add_child(l)


# --- refresh --------------------------------------------------------------------------

func refresh() -> void:
	var ids: Array[String] = core.offer_ids()
	var shop_ids: PackedStringArray = []
	var map_ids: PackedStringArray = []
	for id in ids:
		if id.begins_with("node:"):
			map_ids.append(id)
		else:
			shop_ids.append(id)
	var tiers: PackedStringArray = []
	for t: String in core.mods.unlocked_towers:
		tiers.append(str(core.tower_tier(t)))
	var ssig: String = ",".join(shop_ids) + "|" + ",".join(tiers)
	if ssig != _shop_sig:
		_shop_sig = ssig
		_rebuild_shop(ids)
	var msig: String = ",".join(map_ids)
	if msig != _map_sig:
		_map_sig = msig
		_rebuild_map(ids)
	var n_shop: int = 0
	var n_map: int = 0
	for id: String in cards:
		var c: Card = cards[id]
		var on_map: bool = id.begins_with("node:")
		if on_map == (current_tab == 1):
			_update_card(c)   # the hidden tab only needs its badge count
		if core.can_buy(id):
			if id.begins_with("node:"):
				n_map += 1
			else:
				n_shop += 1
	set_tab_title(0, tr("UI_TAB_SHOP") + (" (%d)" % n_shop if n_shop > 0 else ""))
	set_tab_title(1, tr("UI_TAB_MAP") + (" (%d)" % n_map if n_map > 0 else ""))


func _update_card(c: Card) -> void:
	var cost: Dictionary = core.price(c.id)
	var avail: bool = core.is_available(c.id)
	var can: bool = avail and core.can_afford(cost)
	c.button.disabled = not can
	var first: String = ""
	var extra: PackedStringArray = []
	for r: String in cost:
		if first == "":
			first = r
		else:
			extra.append("+%s %s" % [Fmt.num(float(cost[r])), kit.res_short(r)])
	if first != "":
		c.price_icon.texture = SpriteLib.texture(kit.res_icon(first))
		c.price.text = Fmt.num(float(cost[first])) + (" " + " ".join(extra) if not extra.is_empty() else "")
	c.price_icon.visible = first != "" and avail
	if not avail:
		c.price.text = tr("UI_LIMIT")
	c.price.theme_type_variation = &"PriceLabel" if can or not avail else &"BadLabel"
	var ttl: float = kit.time_to_afford(cost) if avail and not can else 0.0
	c.ttl.text = ("~" + Fmt.time(ttl)) if ttl > kit.f("time_to_afford_min", 10.0) and ttl < INF else ""
	var p: PackedStringArray = GameCore.split_id(c.id)
	match c.kind:
		"tower":
			c.level.text = tr("UI_ON_WALL") % [core.level_of(c.id), core.max_of(c.id)]
		"upg":
			c.level.text = "%d/%d" % [core.level_of(c.id), core.max_of(c.id)]
		"node":
			var mx: int = core.max_of(c.id)
			var reg: String = tr("REGION_%d" % int(core.data.nodes[p[1]]["region"]))
			c.level.text = reg + (" · %d/%d" % [core.level_of(c.id), mx] if mx > 1 else "")
	var aff: int = 1 if can else 0
	if aff != c.affordable:
		c.affordable = aff
		if c.kind != "choice":
			c.panel.theme_type_variation = &"CardAffordable" if can else &"CardPanel"
		c.pic.modulate = Color.WHITE if can or not avail else Color(1, 1, 1, 0.45)
	var sig: String = _diff_state + "#" + str(core.level_of(c.id)) + str(avail)
	if sig != c.diff_sig:
		c.diff_sig = sig
		_fill_effects(c)
		if c.kind != "choice":
			c.panel.tooltip_text = _tooltip(c.id)


func _effect_line(text: String, good: bool, icon_name: String) -> HBoxContainer:
	var row := kit.hbox(4)
	if icon_name != "":
		row.add_child(kit.icon(icon_name, 24))
	var l := kit.label(text, "GoodLabel" if good else "BadLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _fill_effects(c: Card) -> void:
	for ch: Node in c.effects.get_children():
		ch.queue_free()
	var narrow: bool = c.kind == "choice"
	var max_lines: int = 2 if c.kind != "choice" else 4
	var n: int = 0
	if c.id.begins_with("node:"):
		for line: String in kit.novelty_lines(c.id):
			var nl := kit.label("• " + line, "PriceLabel")
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.effects.add_child(nl)
			n += 1
			if n >= max_lines:
				return
		# a new tower or enemy: show what it is (choices compare these side by side)
		var nid: String = GameCore.split_id(c.id)[1]
		for ef: Dictionary in core.data.node_effects(nid):
			var tgt: String = str(ef.get("target", ""))
			var line2: String = ""
			if str(ef["type"]) == "unlock_tower" and core.data.towers.has(tgt):
				line2 = kit.tower_summary(tgt)
			elif str(ef["type"]) == "unlock_enemy" and core.data.enemies.has(tgt):
				line2 = kit.enemy_summary(tgt)
			if line2 != "":
				var sl := kit.label(line2, "DimLabel")
				sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				c.effects.add_child(sl)
				n += 1
	if c.kind == "tower" and not core.is_available(c.id):
		return
	# show the risk too: if a "bad" line (bait: more health) would be cut, it replaces the last good one
	var lines: Array = diff(c.id).duplicate()
	var room: int = maxi(0, max_lines - n)
	if lines.size() > room and room > 0:
		var bad_idx: int = -1
		for i in lines.size():
			if not bool((lines[i] as Dictionary)["good"]):
				bad_idx = i
				break
		if bad_idx >= room:
			lines[room - 1] = lines[bad_idx]
	for d: Dictionary in lines:
		if n >= max_lines:
			break
		c.effects.add_child(_effect_line(str(d["text"]), bool(d["good"]), "" if narrow else str(d["icon"])))
		n += 1
	if n == 0 and c.id.begins_with("node:"):
		# nothing measurable yet (e.g. affects a tower you do not own): say what it does
		var dl := kit.label(tr(kit.desc_key(c.id)), "DimLabel")
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.effects.add_child(dl)
	if c.kind == "upg":
		var u: String = GameCore.split_id(c.id)[1]
		var lvl: int = core.level_of(c.id)
		for ms: Dictionary in core.data.upgrades[u].get("milestones", []):
			if int(ms["level"]) > lvl:
				var ml := kit.label(tr("UI_NEXT_MILESTONE") % [int(ms["level"]), tr(str(ms["name"]))], "DimLabel")
				ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				if int(ms["level"]) == lvl + 1:
					ml.theme_type_variation = &"PriceLabel"
					ml.text = "• " + ml.text
				c.effects.add_child(ml)
				break


func _tooltip(id: String) -> String:
	var lines: PackedStringArray = [tr(kit.name_key(id)), tr(kit.desc_key(id))]
	var nov: PackedStringArray = kit.novelty_lines(id) if id.begins_with("node:") else PackedStringArray()
	for n: String in nov:
		lines.append("• " + n)
	for d: Dictionary in diff(id):
		lines.append(("+ " if bool(d["good"]) else "− ") + str(d["text"]))
	if id.begins_with("tower:"):
		var t: String = GameCore.split_id(id)[1]
		lines.append(kit.tower_summary(t))
	return "\n".join(lines)


func _on_buy(id: String) -> void:
	var c: Card = cards.get(id, null)
	var at: Vector2 = c.button.get_global_rect().get_center() if c != null else Vector2(1090, 360)
	if core.buy(id):
		if c != null:
			c.flash_t = 0.0
			var tw := c.panel.create_tween()
			c.panel.modulate = Color(1.6, 1.5, 1.2)
			tw.tween_property(c.panel, "modulate", Color.WHITE, 0.25)
		bought.emit(id, at)
		refresh()


## Presses the buy button of `id` as if clicked (debug --buy, tests).
func press(id: String) -> void:
	if not cards.has(id):
		refresh()
	_on_buy(id)


## Map tab with a node highlighted (goal bar click).
func show_node(id: String) -> void:
	current_tab = 1
	var c: Card = cards.get(id, null)
	if c != null:
		_map_scroll.ensure_control_visible(c.panel)
		var tw := c.panel.create_tween()
		c.panel.modulate = Color(1.5, 1.4, 1.1)
		tw.tween_property(c.panel, "modulate", Color.WHITE, 0.5)
