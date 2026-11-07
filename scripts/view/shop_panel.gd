class_name ShopPanel
extends TabContainer
## Right panel (~380 px): «Цеха» — towers (count / limit, buy) and their gear upgrades;
## «Карта» — available map nodes (cost, icon, effect) and mutually exclusive choices (a compact card
## that opens the wide ChoiceOverlay). Cards show "было → станет" from core.preview_mods, are sorted
## (affordable / new first, maxed towers collapsed to one line at the bottom), highlighted when
## affordable, dimmed when not, and show time-to-afford when it is long. The order is frozen while
## the mouse is over the panel, so a card never jumps away from the cursor.
## Buying goes through core.buy(); the juicy feedback is driven by core events (MainGame).

signal bought(id: String, at: Vector2)
signal compare_requested(ids: Array)
signal map_requested

class Card:
	var id: String = ""
	var kind: String = ""             ## tower / upg / node / choice
	var panel: PanelContainer
	var pic: Control
	var slot: Control
	var level: Label
	var effects: VBoxContainer
	var buy_row: Control
	var price_icon: TextureRect
	var price: Label
	var price_col: VBoxContainer      ## price line (+ the wait under it when the price has several resources)
	var price_more: HBoxContainer     ## further resources of the price: icon + amount each (never cut)
	var price_sig: String = ""
	var ttl: Label
	var button: Button
	var affordable: int = -1
	var compact: int = -1
	var diff_sig: String = ""
	var group: Array = []             ## choice: all ids of the group

var kit: ViewKit
var core: GameCore
var cards: Dictionary = {}           ## id -> Card (a choice card is stored under every id of its group)
var _shop_list: VBoxContainer
var _map_list: VBoxContainer
var _shop_scroll: ScrollContainer
var _map_scroll: ScrollContainer
var _shop_sig: String = ""
var _map_sig: String = ""
var _diff_cache: Dictionary = {}
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
	tab_changed.connect(func(_t: int) -> void: refresh())


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


func _mouse_inside() -> bool:
	return get_global_rect().has_point(get_global_mouse_position())


# --- building ------------------------------------------------------------------------

func _clear(list: VBoxContainer, kinds: Array) -> void:
	var drop: Array = []
	for id: String in cards:
		if kinds.has((cards[id] as Card).kind):
			drop.append(id)
	for id: String in drop:
		cards.erase(id)
	for c: Node in list.get_children():
		list.remove_child(c)
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


## A card text that wraps to a second line instead of being cut with "…".
func _wrap(text: String, variation: String = "") -> Label:
	var l := kit.label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _card_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"CardPanel"
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _buy_row(c: Card, button_text: String) -> HBoxContainer:
	var row := kit.hbox(4)
	# price column: icon + amounts on top; a long wait drops under them when the price has several resources
	c.price_col = kit.vbox(0)
	c.price_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.price_col.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := kit.hbox(4)
	c.price_icon = kit.icon("res_gears", 32)
	top.add_child(c.price_icon)
	c.price = kit.label("", "PriceLabel")
	top.add_child(c.price)
	c.price_more = kit.hbox(2)
	top.add_child(c.price_more)
	c.ttl = kit.label("", "DimLabel")
	c.ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	c.ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(c.ttl)
	c.price_col.add_child(top)
	row.add_child(c.price_col)
	c.button = Button.new()
	c.button.text = button_text
	c.button.mouse_filter = Control.MOUSE_FILTER_PASS
	c.button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.button.pressed.connect(_on_buy.bind(c.id))
	row.add_child(c.button)
	c.buy_row = row
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
	c.slot = slot
	h.add_child(slot)
	var v := kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_row := kit.hbox(4)
	name_row.add_child(kit.icon(kit.dmg_icon(str(core.mods.tower_stats[t]["dmg_type"])), 24))
	name_row.add_child(_wrap(kit.tower_name(t), "BoldLabel"))
	v.add_child(name_row)
	c.level = _wrap("", "DimLabel")
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
	top.add_child(_wrap(tr(str(core.data.upgrades[u]["name"])), "BoldLabel"))
	v.add_child(top)
	c.level = _wrap("", "DimLabel")
	v.add_child(c.level)
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
	c.pic = kit.sprite_box(kit.node_icon(id), Vector2(44, 44))
	box.add_child(c.pic)
	top.add_child(box)
	var tv := kit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nl := _wrap(tr(kit.name_key(id)), "BoldLabel")
	if _node_kind(id) == "boss":
		nl.add_theme_color_override("font_color", kit.col("ember_2"))
	tv.add_child(nl)
	c.level = _wrap("", "DimLabel")
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


## Compact choice card in the list: both options (icon, name, price) + "compare and choose".
func _choice_card(ids: Array) -> PanelContainer:
	var p := _card_panel()
	p.theme_type_variation = &"CardAffordable"
	var v := kit.vbox(4)
	p.add_child(v)
	var hl := kit.label(tr("UI_CHOICE_TITLE"), "BoldLabel")
	hl.add_theme_color_override("font_color", kit.col("brass_3"))
	v.add_child(hl)
	var c := Card.new()
	c.kind = "choice"
	c.panel = p
	c.group = ids.duplicate()
	c.id = str(ids[0])
	for id: Variant in ids:
		var row := kit.hbox(6)
		var box := PanelContainer.new()
		box.theme_type_variation = &"InsetPanel"
		box.custom_minimum_size = Vector2(40, 40)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(kit.sprite_box(kit.node_icon(str(id)), Vector2(36, 36)))
		row.add_child(box)
		row.add_child(_wrap(tr(kit.name_key(str(id)))))
		var pr := kit.label(Fmt.num(GameCore._cost_sum(core.price(str(id)))), "PriceLabel")
		row.add_child(pr)
		v.add_child(row)
		cards[str(id)] = c
	var b := Button.new()
	b.text = tr("UI_COMPARE")
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.pressed.connect(func() -> void: compare_requested.emit(c.group))
	c.button = b
	v.add_child(b)
	p.tooltip_text = tr("UI_CHOICE_HINT")
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
	# the conquest map itself: a big brass button on top of the list
	var open_btn := Button.new()
	open_btn.text = tr("UI_MAP_OPEN")
	open_btn.icon = SpriteLib.texture("node_spine", 4)
	open_btn.expand_icon = false
	open_btn.pressed.connect(func() -> void: map_requested.emit())
	_map_list.add_child(open_btn)
	var nodes: Array = []
	for id in ids:
		if id.begins_with("node:"):
			nodes.append(id)
	var done: Dictionary = {}
	for id: String in nodes:
		if done.has(id):
			continue
		var group: Array = [id]
		for x: Variant in core.data.node_excludes(GameCore.split_id(id)[1]):
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


# --- ordering ------------------------------------------------------------------------

## Sort key: affordable+new, affordable, new, the rest by time to afford; maxed / limit at the bottom.
func _order_key(c: Card) -> float:
	if c.kind == "choice":
		return -1e9
	if not core.is_available(c.id):
		return 1e12
	var cost: Dictionary = core.price(c.id)
	var can: bool = core.can_afford(cost)
	var novel: bool = not core.novelty_of(c.id).is_empty()
	if c.kind == "node" and _node_kind(c.id) == "boss":
		novel = true
	var base: float = 0.0 if can and novel else (1.0 if can else (2.0 if novel else 3.0))
	var ttl: float = kit.time_to_afford(cost)
	return base * 1e9 + (minf(ttl, 1e8) if not can else GameCore._cost_sum(cost) * 1e-6)


func _reorder(list: VBoxContainer, kinds: Array) -> void:
	var seen: Dictionary = {}
	var arr: Array = []
	for id: String in cards:
		var c: Card = cards[id]
		if kinds.has(c.kind) and not seen.has(c.panel) and c.panel.get_parent() == list:
			seen[c.panel] = true
			arr.append([_order_key(c), c.panel])
	arr.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var first: int = list.get_child_count() - arr.size()   # headers stay on top
	for i in arr.size():
		list.move_child(arr[i][1], first + i)


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
	var hover: bool = _mouse_inside()
	var ssig: String = ",".join(shop_ids) + "|" + ",".join(tiers)
	if ssig != _shop_sig and not hover:
		_shop_sig = ssig
		_rebuild_shop(ids)
	var msig: String = ",".join(map_ids)
	if msig != _map_sig and not hover:
		_map_sig = msig
		_rebuild_map(ids)
	var n_shop: int = 0
	var n_map: int = 0
	var done: Dictionary = {}
	for id: String in cards:
		var c: Card = cards[id]
		if done.has(c):
			continue
		done[c] = true
		if (c.kind == "node" or c.kind == "choice") == (current_tab == 1):
			_update_card(c)   # the hidden tab only needs its badge count
	for id in ids:
		if core.can_buy(id):
			if id.begins_with("node:"):
				n_map += 1
			else:
				n_shop += 1
	if not hover:
		_reorder(_shop_list, ["tower", "upg"])
		_reorder(_map_list, ["node", "choice"])
	set_tab_title(0, tr("UI_TAB_SHOP") + (" (%d)" % n_shop if n_shop > 0 else ""))
	set_tab_title(1, tr("UI_TAB_MAP") + (" (%d)" % n_map if n_map > 0 else ""))


func _update_card(c: Card) -> void:
	if c.kind == "choice":
		var any: bool = false
		for id: Variant in c.group:
			any = any or core.can_buy(str(id))
		c.button.disabled = false
		c.panel.theme_type_variation = &"CardAffordable" if any else &"CardPanel"
		return
	var cost: Dictionary = core.price(c.id)
	var avail: bool = core.is_available(c.id)
	var can: bool = avail and core.can_afford(cost)
	# a tower at its wall limit collapses to one line at the bottom
	var compact: int = 1 if (c.kind == "tower" and not avail) else 0
	if compact != c.compact:
		c.compact = compact
		if c.slot != null:
			c.slot.visible = compact == 0
		c.effects.visible = compact == 0
		c.buy_row.visible = compact == 0
		c.diff_sig = ""
	c.button.disabled = not can
	_update_price(c, cost, can)
	c.ttl.text = ttl_text(cost) if avail and not can else ""
	var p: PackedStringArray = GameCore.split_id(c.id)
	match c.kind:
		"tower":
			c.level.text = tr("UI_ON_WALL") % [core.level_of(c.id), core.max_of(c.id)]
			if not avail:
				c.level.text += " · " + tr("UI_LIMIT")
		"upg":
			c.level.text = "%s · %d/%d" % [kit.tower_name(str(core.data.upgrades[p[1]]["tower"])),
				core.level_of(c.id), core.max_of(c.id)]
		"node":
			var mx: int = core.max_of(c.id)
			var reg: String = tr("REGION_%d" % int(core.data.nodes[p[1]]["region"]))
			c.level.text = reg + (" · %d/%d" % [core.level_of(c.id), mx] if mx > 1 else "")
	var aff: int = 1 if can else 0
	if aff != c.affordable:
		c.affordable = aff
		c.panel.theme_type_variation = &"CardAffordable" if can else &"CardPanel"
		c.pic.modulate = Color.WHITE if can or not avail else Color(1, 1, 1, 0.45)
	var sig: String = _diff_state + "#" + str(core.level_of(c.id)) + str(avail)
	if sig != c.diff_sig:
		c.diff_sig = sig
		_fill_effects(c)
		c.panel.tooltip_text = _tooltip(c.id)


## Price row: every resource of the cost as icon + full amount (a second resource is never cut off).
func _update_price(c: Card, cost: Dictionary, can: bool) -> void:
	var first: String = ""
	var sig: String = ""
	for r: String in cost:
		if first == "":
			first = r
		else:
			sig += r + ","
	if sig != c.price_sig:
		c.price_sig = sig
		# several resources leave no room for "~1м 03с" beside them: the wait goes under the price
		var want_parent: Node = c.price_col if sig != "" else c.price_icon.get_parent()
		if c.ttl.get_parent() != want_parent:
			c.ttl.get_parent().remove_child(c.ttl)
			want_parent.add_child(c.ttl)
			c.ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if sig != "" else HORIZONTAL_ALIGNMENT_RIGHT
		for ch: Node in c.price_more.get_children():
			c.price_more.remove_child(ch)
			ch.queue_free()
		for r: String in cost:
			if r == first:
				continue
			c.price_more.add_child(kit.icon(kit.res_icon(r), 24))
			c.price_more.add_child(kit.label("", "PriceLabel"))
	if first != "":
		c.price_icon.texture = SpriteLib.texture(kit.res_icon(first))
		c.price.text = Fmt.num(float(cost[first]))
	var style: StringName = &"PriceLabel" if can else &"BadLabel"
	c.price.theme_type_variation = style
	var i: int = 1
	for r: String in cost:
		if r == first:
			continue
		var l: Label = c.price_more.get_child(i) as Label
		l.text = Fmt.num(float(cost[r]))
		l.theme_type_variation = &"PriceLabel" if core.state.res(r) >= float(cost[r]) else &"BadLabel"
		i += 2


## "~14с" until affordable at the current income; before there is any income (the very first
## tower) — "ещё 3": how much is missing, so every card that cannot be bought says how far it is.
func ttl_text(cost: Dictionary) -> String:
	var ttl: float = kit.time_to_afford(cost)
	if ttl <= 0.0:
		return ""
	if ttl < INF:
		return "~" + Fmt.time(maxf(kit.f("time_to_afford_min", 1.0), ttl))
	for r: String in cost:
		var need: float = float(cost[r]) - core.state.res(r)
		if need > 0.0:
			return tr("UI_NEED_MORE") % Fmt.num(ceilf(need))
	return ""


func _effect_line(text: String, good: bool, icon_name: String) -> HBoxContainer:
	var row := kit.hbox(4)
	if icon_name != "":
		row.add_child(kit.icon(icon_name, 24))
	var l := kit.label(text, "GoodLabel" if good else "BadLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


## Effect lines of a card: what is new, then "было → станет" (a risk line is never cut off).
func effect_lines(id: String, max_lines: int) -> Array:
	var out: Array = []
	if id.begins_with("node:"):
		for line: String in kit.novelty_lines(id):
			out.append({"text": "• " + line, "style": "PriceLabel"})
		for ef: Dictionary in core.data.node_effects(GameCore.split_id(id)[1]):
			var tgt: String = str(ef.get("target", ""))
			if str(ef["type"]) == "unlock_tower" and core.data.towers.has(tgt):
				out.append({"text": kit.tower_summary(tgt), "style": "DimLabel"})
			elif str(ef["type"]) == "unlock_enemy" and core.data.enemies.has(tgt):
				out.append({"text": kit.enemy_summary(tgt), "style": "DimLabel"})
	var lines: Array = diff(id).duplicate()
	var room: int = maxi(0, max_lines - out.size())
	if lines.size() > room and room > 0:
		var bad_idx: int = -1
		for i in lines.size():
			if not bool((lines[i] as Dictionary)["good"]):
				bad_idx = i
				break
		if bad_idx >= room:
			lines[room - 1] = lines[bad_idx]
	for d: Dictionary in lines:
		out.append({"text": str(d["text"]), "style": "GoodLabel" if bool(d["good"]) else "BadLabel", "icon": str(d["icon"])})
	return out.slice(0, max_lines)


func _fill_effects(c: Card) -> void:
	for ch: Node in c.effects.get_children():
		c.effects.remove_child(ch)
		ch.queue_free()
	if c.compact == 1:
		return
	var lines: Array = effect_lines(c.id, 3 if c.kind == "node" else 2)
	for d: Dictionary in lines:
		if str(d["style"]) == "GoodLabel" or str(d["style"]) == "BadLabel":
			c.effects.add_child(_effect_line(str(d["text"]), str(d["style"]) == "GoodLabel", str(d.get("icon", ""))))
		else:
			var l := kit.label(str(d["text"]), str(d["style"]))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.effects.add_child(l)
	if lines.is_empty() and c.id.begins_with("node:"):
		var dl := kit.label(tr(kit.desc_key(c.id)), "DimLabel")
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.effects.add_child(dl)
	if c.kind == "upg":
		var u: String = GameCore.split_id(c.id)[1]
		var lvl: int = core.level_of(c.id)
		for ms: Dictionary in core.data.upgrades[u].get("milestones", []):
			if int(ms["level"]) > lvl:
				var ml := _wrap(tr("UI_NEXT_MILESTONE") % [int(ms["level"]), tr(str(ms["name"]))], "DimLabel")
				if int(ms["level"]) == lvl + 1:
					ml.theme_type_variation = &"PriceLabel"
					ml.text = "• " + ml.text
				c.effects.add_child(ml)
				break


func _tooltip(id: String) -> String:
	var lines: PackedStringArray = [tr(kit.name_key(id)), tr(kit.desc_key(id))]
	if id.begins_with("node:"):
		for n: String in kit.novelty_lines(id):
			lines.append("• " + n)
	for d: Dictionary in diff(id):
		lines.append(("+ " if bool(d["good"]) else "− ") + str(d["text"]))
	if id.begins_with("tower:"):
		lines.append(kit.tower_summary(GameCore.split_id(id)[1]))
	return "\n".join(lines)


func _on_buy(id: String) -> void:
	var c: Card = cards.get(id, null)
	var at: Vector2 = c.button.get_global_rect().get_center() if c != null and c.button != null else Vector2(1090, 360)
	buy(id, at)


## Buys `id` (cards, the choice overlay, the goal bar). Returns true on success.
func buy(id: String, at: Vector2) -> bool:
	if not core.buy(id):
		return false
	var c: Card = cards.get(id, null)
	if c != null:
		var tw := c.panel.create_tween()
		c.panel.modulate = Color(1.6, 1.5, 1.2)
		tw.tween_property(c.panel, "modulate", Color.WHITE, 0.25)
	bought.emit(id, at)
	refresh()
	return true


## Presses the buy button of `id` as if clicked (debug --buy, tests).
func press(id: String) -> void:
	if not cards.has(id):
		refresh()
	var c: Card = cards.get(id, null)
	if c != null and c.kind == "choice":
		buy(id, c.button.get_global_rect().get_center())
		return
	_on_buy(id)


## Map tab with a node highlighted (goal bar click).
func show_node(id: String) -> void:
	current_tab = 1
	refresh()
	var c: Card = cards.get(id, null)
	if c != null:
		_map_scroll.ensure_control_visible(c.panel)
		var tw := c.panel.create_tween()
		c.panel.modulate = Color(1.5, 1.4, 1.1)
		tw.tween_property(c.panel, "modulate", Color.WHITE, 0.5)
