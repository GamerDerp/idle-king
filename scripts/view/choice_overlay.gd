class_name ChoiceOverlay
extends Control
## Wide comparison card for a mutually exclusive choice (map nodes with `excludes`): both options
## side by side with distinct icons, description, what is new and "было → станет", price and a
## «Выбрать» button each, plus the warning that the other branch closes until the Great Remelt.
## Opened from the compact choice card in ShopPanel; buying goes through ShopPanel.buy().

signal chosen(id: String, at: Vector2)

var kit: ViewKit
var shop: ShopPanel
var ids: Array = []
var _card: PanelContainer
var _cols: HBoxContainer
var _buttons: Dictionary = {}


func setup(view_kit: ViewKit, shop_panel: ShopPanel) -> void:
	kit = view_kit
	shop = shop_panel
	var field_w: float = 1280.0 - kit.f("panel_width", 380)
	var top: float = kit.f("bar_height", 40)
	position = Vector2(0, top)
	size = Vector2(field_w, 720.0 - top)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(kit.col("soot_0"), kit.f("choice.dim_alpha", 0.6))
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)


func open(group: Array) -> void:
	ids = group.duplicate()
	for c: Node in _card.get_children():
		_card.remove_child(c)
		c.queue_free()
	_buttons.clear()
	var v := kit.vbox(8)
	_card.add_child(v)
	var title := kit.label(tr("UI_CHOICE_TITLE"), "HeaderLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var warn := kit.label(tr("UI_CHOICE_WARN"), "BadLabel")
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(kit.f("choice.width", 760) - 40.0, 0)
	v.add_child(warn)
	_cols = kit.hbox(10)
	v.add_child(_cols)
	var col_w: float = (kit.f("choice.width", 760) - 40.0 - 10.0 * (ids.size() - 1)) / ids.size()
	for i in ids.size():
		if i > 0:
			var vs := VSeparator.new()
			vs.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_cols.add_child(vs)
		_cols.add_child(_column(str(ids[i]), col_w))
	var later := Button.new()
	later.text = tr("UI_LATER")
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	later.pressed.connect(close)
	v.add_child(later)
	_card.custom_minimum_size = Vector2(kit.f("choice.width", 760), 0)
	visible = true
	refresh()
	_center.call_deferred()


func _center() -> void:
	_card.reset_size()
	_card.position = ((size - _card.size) * 0.5).round()


func _column(id: String, w: float) -> Control:
	var col := PanelContainer.new()
	col.theme_type_variation = &"CardPanel"
	col.custom_minimum_size = Vector2(w, 0)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	col.tooltip_text = tr(kit.desc_key(id))
	var v := kit.vbox(4)
	col.add_child(v)
	var head := kit.hbox(10)
	var box := PanelContainer.new()
	box.theme_type_variation = &"InsetPanel"
	box.custom_minimum_size = Vector2(76, 88)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(kit.sprite_box(kit.node_icon(id), Vector2(72, 84)))
	head.add_child(box)
	var nl := kit.label(tr(kit.name_key(id)), "BoldLabel")
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nl)
	v.add_child(head)
	var desc := kit.label(tr(kit.desc_key(id)).get_slice(".", 0) + ".", "DimLabel")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(w - 24.0, 0)
	v.add_child(desc)
	for d: Dictionary in shop.effect_lines(id, 6):
		var l := kit.label(str(d["text"]), str(d["style"]))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(w - 24.0, 0)
		v.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var row := kit.hbox(6)
	var cost: Dictionary = kit.core.price(id)
	for r: String in cost:
		row.add_child(kit.icon(kit.res_icon(r), 32))
		row.add_child(kit.label(Fmt.num(float(cost[r])), "PriceLabel"))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp2)
	var b := Button.new()
	b.text = tr("UI_CHOOSE")
	b.pressed.connect(_choose.bind(id))
	row.add_child(b)
	_buttons[id] = b
	v.add_child(row)
	return col


func _choose(id: String) -> void:
	var b: Button = _buttons[id]
	var at: Vector2 = b.get_global_rect().get_center()
	if shop.buy(id, at):
		chosen.emit(id, at)
		close()


func close() -> void:
	visible = false


func refresh() -> void:
	if not visible:
		return
	for id: String in _buttons:
		var st: String = kit.core.node_status(GameCore.split_id(id)[1])
		if st != "available":
			close()
			return
		(_buttons[id] as Button).disabled = not kit.core.can_buy(id)


func _process(_delta: float) -> void:
	if not visible:
		return
	if Engine.get_process_frames() % 8 == 0:
		refresh()
		_center()
