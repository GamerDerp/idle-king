class_name MapScreen
extends Control
## «Карта завоеваний» — the full-screen conquest map (M / «Карта» tab). An old parchment map of the valley
## (artist's kit: map_bg, node_<kind> markers whose frames are states, map_road_dot roads, fog per region,
## burn-away, ink splat + wax stamp, road sparks, progress cartouche; layout in config/map_layout.json).
## Reads the core (node_status, level_of, price, can_buy, next_goal) and buys only through ShopPanel.buy /
## ChoiceOverlay; the battle keeps running underneath (the resource bar stays visible above the map).
##
## Layers (world = Node2D scaled by an integer zoom 1..3, panned in whole screen pixels):
##   map_bg → roads (_draw, redrawn only when a road changes) → markers (_draw every frame: 250 textures)
##   → fog sprites + wisps → region labels (Kotel title) → fx (_draw: splats, stamps, burn, sparks, hint).
## Screen UI: back / recentre / zoom buttons, progress cartouche, tooltip card, region banner, live strip.
## `dummy` > 0 (debug --map-dummy=250, tests): builds that many fake nodes over 8 regions instead of the
## core's map, to check readability and performance of a full late-game map.

class MNode:
	var id: String = ""
	var region: int = 0
	var kind: String = ""
	var sprite: String = ""
	var pos: Vector2 = Vector2.ZERO        ## art px on map_bg
	var parents: Array[String] = []
	var excludes: Array[String] = []
	var status: String = "locked"          ## hidden / locked / excluded / available / maxed
	var level: int = 0
	var max_level: int = 1
	var afford: bool = false
	var ttl: float = INF
	var seen_level: int = 0                ## level the player has already seen stamped on the map
	var reward_of: String = ""             ## boss id for trophy nodes


class Fx:
	var sprite: String = ""
	var pos: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO          ## spark: travels pos -> b
	var t: float = 0.0
	var delay: float = 0.0
	var dur: float = 0.6
	var loop: bool = false
	var mod: Color = Color.WHITE


class DrawLayer extends Node2D:
	var fn: Callable

	func _draw() -> void:
		fn.call(self)


signal closed

const HOLD_DELAY: float = 0.35
const HOLD_EVERY: float = 0.12

var kit: ViewKit
var core: GameCore
var shop: ShopPanel
var choice: ChoiceOverlay
var dummy: int = 0
var nodes: Dictionary = {}               ## id -> MNode
var order: Array[MNode] = []
var lay: Dictionary = {}
var zoom: int = 1
var draw_ms: float = 0.0               ## last _process cost (perf readout)
var marker_ms: float = 0.0             ## last marker _draw cost
var world: Node2D
var _roads: DrawLayer
var _markers: DrawLayer
var _fx_layer: DrawLayer
var _fog: Dictionary = {}                ## region -> Sprite2D
var _fog_fade: Dictionary = {}           ## region -> seconds into its burn
var _wisps: Array = []                   ## [AnimatedSprite2D, region, phase]
var _labels: Dictionary = {}             ## region -> {name: Label, count: Label, unknown: Label, sil: Sprite2D}
var _fx: Array[Fx] = []
var _road_sig: String = ""
var _origin: Vector2 = Vector2(200, 150)
var _scale: float = 2.0
var _hover: MNode = null
var _hint: MNode = null
var _press_at: Vector2 = Vector2.ZERO
var _pressed: bool = false
var _dragging: bool = false
var _press_node: MNode = null
var _hold_t: float = 0.0
var _time: float = 0.0
var _refresh_t: float = 0.0
var _tip: PanelContainer
var _tip_box: VBoxContainer
var _tip_id: String = ""
var _progress_fill: TextureRect
var _progress_label: Label
var _banner: PanelContainer
var _banner_label: Label
var _banner_t: float = 0.0
var _live: Label
var _view: Vector2 = Vector2(1280, 680)
var _c: Dictionary = {}
var _regions_open: Dictionary = {}      ## region -> unlocked (as last seen by the map)
var _fork_mid: Array = []               ## [Vector2 art, String a, String b, bool sign]


func setup(view_kit: ViewKit, shop_panel: ShopPanel, choice_overlay: ChoiceOverlay, dummy_nodes: int = 0) -> void:
	kit = view_kit
	core = kit.core
	shop = shop_panel
	choice = choice_overlay
	dummy = dummy_nodes
	var top: float = kit.f("bar_height", 40)
	position = Vector2(0, top)
	size = Vector2(1280, 720.0 - top)
	_view = size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	visible = false
	for n: String in ["soot_0", "soot_1", "copper_0", "copper_1", "parchment_0", "parchment_1", "parchment_2", "brass_1",
			"brass_2", "brass_3", "ember_0", "ember_1", "verdigris_0", "iron_1"]:
		_c[n] = kit.col(n)
	lay = Config.get_cfg("map_layout") if Config.names().has("map_layout") else {}
	if lay.is_empty():
		var f := FileAccess.open("res://config/map_layout.json", FileAccess.READ)
		if f != null:
			lay = JSON.parse_string(f.get_as_text())
	var o: Array = lay.get("origin", [200, 150])
	_origin = Vector2(float(o[0]), float(o[1]))
	_scale = float(lay.get("scale", 2))
	var bgc := ColorRect.new()
	bgc.color = kit.col("soot_1")
	bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
	bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bgc)
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	var bg := Sprite2D.new()
	bg.texture = SpriteLib.texture("map_bg")
	bg.centered = false
	world.add_child(bg)
	_roads = _layer("Roads", _draw_roads)
	_markers = _layer("Markers", _draw_markers)
	_build_model()
	_build_fog()
	_build_labels()
	_fx_layer = _layer("Fx", _draw_fx)
	_build_ui()
	_refresh(false)
	for m: MNode in order:
		m.seen_level = m.level
	for r: int in _fog:
		_regions_open[r] = _region_open(r)
		(_fog[r] as Sprite2D).visible = not _regions_open[r]
	_set_zoom(int(kit.f("map.zoom", 1)), _view * 0.5)
	recentre()


func _layer(layer_name: String, fn: Callable) -> DrawLayer:
	var l := DrawLayer.new()
	l.name = layer_name
	l.fn = fn
	world.add_child(l)
	return l


func art_of(map_pos: Vector2) -> Vector2:
	return (_origin + map_pos * _scale).round()


# --- model -----------------------------------------------------------------------

func _node_sprite(id: String, kind: String) -> String:
	var over: Dictionary = kit.v("map.effect_sprites", {})
	for ef: Dictionary in core.data.node_effects(id):
		var ty: String = str(ef["type"])
		if over.has(ty):
			return str(over[ty])
	var sp: String = "node_" + kind
	return sp if SpriteLib.info(sp).size() > 0 else "node_spine"


func _build_model() -> void:
	nodes.clear()
	order.clear()
	if dummy > 0:
		_build_dummy()
	else:
		for id: String in core.data.node_order:
			var d: Dictionary = core.data.nodes[id]
			var m := MNode.new()
			m.id = id
			m.region = int(d["region"])
			m.kind = str(d.get("kind", "spine"))
			m.sprite = _node_sprite(id, m.kind)
			var p: Array = d["pos"]
			m.pos = art_of(Vector2(float(p[0]), float(p[1])))
			for x: Variant in d.get("parents", []):
				m.parents.append(str(x))
			for x: Variant in d.get("excludes", []):
				m.excludes.append(str(x))
			m.max_level = int(d["max"])
			m.reward_of = str((d.get("requires", {}) as Dictionary).get("boss", ""))
			nodes[id] = m
			order.append(m)
	# choice pairs: a forked sign between them (or a small «или» when another marker is too close)
	_fork_mid.clear()
	var done: Dictionary = {}
	for m: MNode in order:
		for x: String in m.excludes:
			if not nodes.has(x) or done.has(x + "|" + m.id):
				continue
			done[m.id + "|" + x] = true
			var mid: Vector2 = ((m.pos + (nodes[x] as MNode).pos) * 0.5).round()
			var clear: bool = true
			for o: MNode in order:
				if o.pos.distance_to(mid) < kit.f("map.fork_clear", 26.0):
					clear = false
					break
			_fork_mid.append([mid, m.id, x, clear])


## Fake late-game map: `dummy` nodes spread over the 8 regions of the layout (readability / perf check).
func _build_dummy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var kinds: Array = ["spine", "tower", "bait", "lens", "mechanism", "synergy", "global", "moat", "producer"]
	var regs: Array = lay.get("regions", [])
	var per: int = maxi(1, dummy / maxi(1, regs.size()))
	var i: int = 0
	for r: Dictionary in regs:
		var bb: Array = r["bbox"]
		var c: Array = r["center"]
		var placed: Array[MNode] = []
		var guard: int = 0
		var spine: MNode = null
		while placed.size() < per and guard < 4000:
			guard += 1
			var p := Vector2(rng.randf_range(float(bb[0]) + 40, float(bb[2]) - 40), rng.randf_range(float(bb[1]) + 40, float(bb[3]) - 40))
			if placed.is_empty():
				p = art_of(Vector2(float(c[0]), float(c[1])))
			var ok: bool = true
			for q: MNode in placed:
				if q.pos.distance_to(p) < 44.0:
					ok = false
					break
			if not ok:
				continue
			var m := MNode.new()
			m.id = "dummy_%d" % i
			i += 1
			m.region = int(r["id"])
			m.kind = "spine" if placed.is_empty() else str(kinds[rng.randi() % kinds.size()])
			if placed.size() == per - 1:
				m.kind = "boss"
			m.sprite = "node_" + m.kind
			m.pos = p.round()
			var best: MNode = spine
			for q: MNode in placed:
				if best == null or q.pos.distance_to(p) < best.pos.distance_to(p):
					best = q
			if best != null:
				m.parents.append(best.id)
			m.max_level = 1 + rng.randi() % 4
			var roll: float = rng.randf()
			m.level = m.max_level if roll < 0.35 else (1 if roll < 0.5 else 0)
			m.status = "maxed" if m.level >= m.max_level else ("available" if roll < 0.75 else "locked")
			if roll > 0.95:
				m.status = "excluded"
				m.level = 0
			m.afford = roll < 0.62
			m.ttl = 0.0 if m.afford else rng.randf_range(10.0, 400.0)
			if spine == null:
				spine = m
			nodes[m.id] = m
			order.append(m)
			placed.append(m)


func _region_open(r: int) -> bool:
	if dummy > 0:
		return r < 6
	return core.mods.is_region_unlocked(r)


## Re-reads every node's state from the core; with `juice`, newly bought levels get the splat + stamp,
## roads spark toward freshly opened nodes and opened regions burn their fog.
func _refresh(juice: bool) -> void:
	if dummy == 0:
		for m: MNode in order:
			var pid: String = "node:" + m.id
			m.status = core.node_status(m.id)
			m.level = core.level_of(pid)
			m.afford = core.can_buy(pid)
			m.ttl = kit.time_to_afford(core.price(pid)) if m.status == "available" else INF
	if juice:
		var k: int = 0
		for m: MNode in order:
			if m.level > m.seen_level:
				_stamp(m, k * kit.f("map.stamp_stagger", 0.18))
				k += 1
				m.seen_level = m.level
	for r: int in _fog:
		var open: bool = _region_open(r)
		if open and not bool(_regions_open.get(r, false)):
			_regions_open[r] = true
			if juice:
				_burn(r)
			else:
				(_fog[r] as Sprite2D).visible = false
	_hint = _pick_hint()
	_update_labels()
	_update_progress()
	var sig: String = ""
	for m: MNode in order:
		sig += "%s%d," % [m.status.left(2), m.level]
	if sig != _road_sig:
		_road_sig = sig
		_roads.queue_redraw()


func _pick_hint() -> MNode:
	if dummy > 0:
		return null
	var g: Dictionary = core.next_goal()
	var gid: String = str(g.get("id", ""))
	if gid.begins_with("node:") and nodes.has(gid.substr(5)) and (nodes[gid.substr(5)] as MNode).status == "available":
		return nodes[gid.substr(5)]
	var best: MNode = null
	for m: MNode in order:
		if m.status == "available" and _region_open(m.region) and (best == null or m.ttl < best.ttl):
			best = m
	return best


# --- fog, labels -------------------------------------------------------------------

func _build_fog() -> void:
	for r: Dictionary in lay.get("regions", []):
		if r.get("fog") == null:
			continue
		var id: int = int(r["id"])
		var fog := Sprite2D.new()
		fog.texture = SpriteLib.texture(str(r["fog"]))
		fog.centered = false
		var fp: Array = r["fog_pos"]
		fog.position = Vector2(float(fp[0]), float(fp[1]))
		world.add_child(fog)
		_fog[id] = fog
		var bb: Array = r["bbox"]
		for k in int(kit.f("map.wisps_per_region", 5)):
			var w := SpriteLib.make("map_fog_wisp", (k + id) % 4)
			w.position = Vector2(lerpf(float(bb[0]), float(bb[2]), 0.15 + 0.7 * fmod(k * 0.37 + id * 0.21, 1.0)),
				lerpf(float(bb[1]), float(bb[3]), 0.2 + 0.6 * fmod(k * 0.61 + id * 0.13, 1.0))).round()
			fog.add_child(w)
			w.position -= fog.position
			_wisps.append([w, id, k * 1.3 + id])


func _build_labels() -> void:
	var sil_cfg: Dictionary = kit.v("map.region_silhouettes", {})
	for r: Dictionary in lay.get("regions", []):
		var id: int = int(r["id"])
		var lp: Array = r["label"]
		var at := Vector2(float(lp[0]), float(lp[1]))
		var box := Node2D.new()
		box.position = at
		world.add_child(box)
		var sil: Sprite2D = null
		var sname: String = str(sil_cfg.get(str(id), ""))
		if sname != "" and SpriteLib.info(sname).size() > 0:
			# what lies beyond the fog: the region's own creature drawn as an ink silhouette
			sil = Sprite2D.new()
			sil.texture = SpriteLib.texture(sname)
			sil.centered = false
			sil.position = (-SpriteLib.anchor(sname) + Vector2(0, -14)).round()
			sil.modulate = Color(_c["copper_0"], 0.7)
			box.add_child(sil)
		var name_l := _world_label(tr("REGION_%d" % id), ViewKit.FONT_TITLE, 16, "copper_0")
		name_l.position = Vector2(-160, -10)
		box.add_child(name_l)
		var cnt := _world_label("", ViewKit.FONT_BOLD, 12, "copper_1")
		cnt.position = Vector2(-160, 8)
		box.add_child(cnt)
		var unk := _world_label(tr("UI_MAP_UNKNOWN"), ViewKit.FONT_REGULAR, 12, "copper_1")
		unk.position = Vector2(-160, 8)
		box.add_child(unk)
		_labels[id] = {"name": name_l, "count": cnt, "unknown": unk, "sil": sil}
	var tb: Array = lay.get("title_box", [1004, 40, 392, 44])
	var title := _world_label(tr("UI_MAP_TITLE"), ViewKit.FONT_TITLE, 16, "copper_0")
	title.size = Vector2(float(tb[2]), float(tb[3]))
	title.position = Vector2(float(tb[0]), float(tb[1]))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	world.add_child(title)


func _world_label(text: String, font: FontFile, font_size: int, color: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", kit.col(color))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(320, 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _update_labels() -> void:
	for id: int in _labels:
		var d: Dictionary = _labels[id]
		var open: bool = _region_open(id) or not _fog.has(id)
		var total: int = 0
		var got: int = 0
		for m: MNode in order:
			if m.region == id:
				total += 1
				if m.level > 0:
					got += 1
		(d["count"] as Label).text = (tr("UI_MAP_REGION_COUNT") % [got, total]) if total > 0 else ""
		(d["count"] as Label).visible = open and total > 0
		(d["unknown"] as Label).visible = not open
		if d["sil"] != null:
			(d["sil"] as Sprite2D).visible = not open
		(d["name"] as Label).add_theme_color_override("font_color", kit.col("copper_0" if open else "parchment_0"))
		(d["unknown"] as Label).add_theme_color_override("font_color", kit.col("parchment_1"))


# --- UI ---------------------------------------------------------------------------

func _build_ui() -> void:
	var row := kit.hbox(6)
	row.position = Vector2(8, 8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)
	var back := Button.new()
	back.text = tr("UI_MAP_BACK")
	back.pressed.connect(close)
	row.add_child(back)
	var home := Button.new()
	home.text = tr("UI_MAP_HOME")
	home.pressed.connect(recentre)
	row.add_child(home)
	var zin := Button.new()
	zin.text = "+"
	zin.custom_minimum_size = Vector2(40, 0)
	zin.pressed.connect(func() -> void: _set_zoom(zoom + 1, _view * 0.5))
	row.add_child(zin)
	var zout := Button.new()
	zout.text = "−"
	zout.custom_minimum_size = Vector2(40, 0)
	zout.pressed.connect(func() -> void: _set_zoom(zoom - 1, _view * 0.5))
	row.add_child(zout)
	# progress cartouche «Долина покорена на N%» (art ×2)
	var fr := TextureRect.new()
	fr.texture = SpriteLib.texture("map_progress_frame")
	fr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fr.scale = Vector2(2, 2)
	var fsz: Vector2i = SpriteLib.frame_size("map_progress_frame")
	fr.position = Vector2(roundf((_view.x - fsz.x * 2) * 0.5), _view.y - fsz.y * 2 - 6)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fr)
	var bar: Array = kit.v("map.progress_bar", [36, 31, 188, 8])
	_progress_fill = TextureRect.new()
	_progress_fill.texture = SpriteLib.texture("map_progress_fill")
	_progress_fill.stretch_mode = TextureRect.STRETCH_TILE
	_progress_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_progress_fill.position = fr.position + Vector2(float(bar[0]), float(bar[1])) * 2
	_progress_fill.size = Vector2(0, float(bar[3]) * 2)
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_fill)
	var txt: Array = kit.v("map.progress_text", [34, 10, 192, 16])
	_progress_label = kit.label("", "InkLabel")
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.position = fr.position + Vector2(float(txt[0]), float(txt[1])) * 2
	_progress_label.size = Vector2(float(txt[2]), float(txt[3])) * 2
	add_child(_progress_label)
	# live strip: the battle does not pause under the map
	var live := PanelContainer.new()
	live.theme_type_variation = &"ResourcePlate"
	live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live.position = Vector2(8, _view.y - 44)
	add_child(live)
	_live = kit.label("", "DimLabel")
	live.add_child(_live)
	_banner = PanelContainer.new()
	_banner.theme_type_variation = &"MapCard"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)
	_banner_label = kit.label("", "InkLabel")
	_banner_label.add_theme_font_override("font", ViewKit.FONT_TITLE)
	_banner_label.add_theme_font_size_override("font_size", 32)
	_banner.add_child(_banner_label)
	_tip = PanelContainer.new()
	_tip.theme_type_variation = &"MapCard"
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	add_child(_tip)
	_tip_box = kit.vbox(0)
	_tip.add_child(_tip_box)


func _update_progress() -> void:
	var total: int = 0
	var done: int = 0
	for m: MNode in order:
		total += 1
		if m.level > 0 or m.status == "excluded":
			done += 1
	var k: float = float(done) / maxf(1.0, float(total))
	var bar: Array = kit.v("map.progress_bar", [36, 31, 188, 8])
	_progress_fill.size.x = roundf(float(bar[2]) * k) * 2.0
	_progress_label.text = tr("UI_MAP_PROGRESS") % int(floorf(k * 100.0))
	if dummy > 0:
		_live.text = "dummy: %d" % order.size()
	else:
		_live.text = tr("UI_MAP_LIVE") % [core.battle.alive_count(), int(core.state.stats.get("falls", 0))]


func banner(text: String) -> void:
	_banner_label.text = text
	_banner.visible = true
	_banner.reset_size()
	_banner.position = Vector2(roundf((_view.x - _banner.size.x) * 0.5), 60)
	_banner_t = kit.f("map.banner_time", 2.8)


# --- open / camera ------------------------------------------------------------------

func open() -> void:
	if visible:
		return
	visible = true
	if choice != null:
		choice.close()
		choice.full_width = true
	_hover = null
	_refresh(true)


func close() -> void:
	if not visible:
		return
	visible = false
	_tip.visible = false
	_pressed = false
	if choice != null:
		choice.full_width = false
		choice.close()
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Centre on the fortress — or on the frontier (the suggested node) when there is one.
func recentre() -> void:
	var f: Array = lay.get("fortress", [500, 370])
	var at: Vector2 = art_of(Vector2(float(f[0]), float(f[1])))
	if _hint != null:
		at = (at + _hint.pos) * 0.5 if zoom == 1 else _hint.pos
	world.position = (_view * 0.5 - at * zoom).round()
	_clamp_pan()


## Opens the map centred on a node (goal bar click) and rings it with a spark.
func show_node(id: String) -> void:
	open()
	var m: MNode = nodes.get(id, null)
	if m == null:
		return
	focus_art(m.pos)
	var s := _fx_add("map_spark", m.pos, 0.0)
	s.loop = true
	s.dur = 1.2


func focus_art(at: Vector2) -> void:
	world.position = (_view * 0.5 - at * zoom).round()
	_clamp_pan()


func _set_zoom(z: int, anchor_screen: Vector2) -> void:
	z = clampi(z, 1, int(kit.f("map.zoom_max", 3)))
	var art_at: Vector2 = (anchor_screen - world.position) / float(zoom)
	zoom = z
	world.scale = Vector2(zoom, zoom)
	world.position = (anchor_screen - art_at * zoom).round()
	_clamp_pan()


func _clamp_pan() -> void:
	var sz: Vector2 = Vector2(SpriteLib.frame_size("map_bg")) * zoom
	var p: Vector2 = world.position
	p.x = clampf(p.x, _view.x - sz.x, 0.0) if sz.x > _view.x else roundf((_view.x - sz.x) * 0.5)
	p.y = clampf(p.y, _view.y - sz.y, 0.0) if sz.y > _view.y else roundf((_view.y - sz.y) * 0.5)
	world.position = p.round()


func screen_of(m: MNode) -> Vector2:
	return world.position + m.pos * zoom


func _node_at(local: Vector2) -> MNode:
	var a: Vector2 = (local - world.position) / float(zoom)
	var best: MNode = null
	var best_d: float = kit.f("map.pick_px", 13.0)
	for m: MNode in order:
		if not _region_open(m.region) and _fog.has(m.region):
			continue
		var d: float = m.pos.distance_to(a)
		if d < best_d:
			best_d = d
			best = m
	return best


# --- input ------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_zoom(zoom + 1, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom(zoom - 1, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press_at = mb.position
				_press_node = _node_at(mb.position)
				_hold_t = 0.0
			else:
				if _pressed and not _dragging and _press_node != null and _hold_t < HOLD_DELAY:
					click(_press_node)
				_pressed = false
				_press_node = null
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _pressed:
		if not _dragging and mm.position.distance_to(_press_at) > kit.f("map.drag_px", 5.0):
			_dragging = true
		if _dragging:
			world.position += mm.relative
			_clamp_pan()
		accept_event()


## Click on a marker: a choice opens the comparison (warning: the other branch closes until the Remelt);
## an available node is bought; anything else just flashes its tooltip.
func click(m: MNode) -> bool:
	if dummy > 0 or m.status != "available":
		return false
	var id: String = "node:" + m.id
	if not m.excludes.is_empty() and m.level == 0:
		var group: Array = [id]
		for x: String in m.excludes:
			if core.node_status(x) == "available":
				group.append("node:" + x)
		if group.size() > 1 and choice != null:
			choice.open(group)
			return false
	if not core.can_buy(id):
		_fx_add("map_ink_splat", m.pos, 0.0, Color(1, 1, 1, 0.35))
		return false
	var ok: bool = shop.buy(id, global_position + screen_of(m))
	if ok:
		_refresh(true)
	return ok


func _process(delta: float) -> void:
	if not visible:
		return
	var t0: int = Time.get_ticks_usec()
	_time += delta
	_pan_keys(delta)
	if _pressed and not _dragging and _press_node != null:
		_hold_t += delta
		# hold to buy several levels
		if _hold_t >= HOLD_DELAY:
			var steps: int = int((_hold_t - HOLD_DELAY) / HOLD_EVERY)
			if steps > int((_hold_t - delta - HOLD_DELAY) / HOLD_EVERY) or _hold_t - delta < HOLD_DELAY:
				click(_press_node)
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = kit.f("ui_refresh", 0.15)
		_refresh(true)
	var mp: Vector2 = get_local_mouse_position()
	var h: MNode = _node_at(mp) if Rect2(Vector2.ZERO, _view).has_point(mp) and not _dragging else null
	if h != _hover:
		_hover = h
		_tip_id = ""
	_update_tip(mp)
	_step_fx(delta)
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.visible = _banner_t > 0.0
		_banner.modulate.a = clampf(_banner_t / 0.4, 0.0, 1.0)
	_markers.queue_redraw()
	_fx_layer.queue_redraw()
	draw_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _pan_keys(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x += 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x -= 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y -= 1
	var mp: Vector2 = get_local_mouse_position()
	var e: float = kit.f("map.edge_px", 6.0)
	if Rect2(Vector2.ZERO, _view).has_point(mp) and DisplayServer.window_is_focused() and not DevTools.has_arg("bot"):
		if mp.x < e:
			v.x += 1
		elif mp.x > _view.x - e:
			v.x -= 1
		if mp.y > _view.y - e:
			v.y -= 1
	if v != Vector2.ZERO:
		world.position += (v * kit.f("map.pan_speed", 700.0) * delta).round()
		_clamp_pan()


# --- tooltip -------------------------------------------------------------------------

func _ink(text: String, color: String = "", bold: bool = false) -> Label:
	var l := kit.label(text, "InkLabel")
	if color != "":
		l.add_theme_color_override("font_color", kit.col(color))
	if bold:
		l.add_theme_font_override("font", ViewKit.FONT_BOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(kit.f("map.tip_w", 360), 0)
	return l


func _update_tip(mp: Vector2) -> void:
	if _hover == null:
		_tip.visible = false
		return
	var m: MNode = _hover
	var sig: String = "%s|%s|%d|%s|%d" % [m.id, m.status, m.level, str(m.afford), int(m.ttl)]
	if sig != _tip_id:
		_tip_id = sig
		_fill_tip(m)
	_tip.visible = true
	_tip.reset_size()
	var p: Vector2 = mp + Vector2(22, 18)
	if p.x + _tip.size.x > _view.x - 6:
		p.x = mp.x - _tip.size.x - 16
	p.y = clampf(p.y, 6.0, _view.y - _tip.size.y - 6)
	_tip.position = p.round()


func _fill_tip(m: MNode) -> void:
	for c: Node in _tip_box.get_children():
		_tip_box.remove_child(c)
		c.queue_free()
	var id: String = "node:" + m.id
	var head := kit.hbox(8)
	head.add_child(kit.icon(m.sprite, 32, _frame_of(m)))
	var nm := _ink(tr(kit.name_key(id)) if dummy == 0 else m.id, "", true)
	nm.custom_minimum_size = Vector2(kit.f("map.tip_w", 360) - 40, 0)
	head.add_child(nm)
	_tip_box.add_child(head)
	var lvl: String = tr("UI_MAP_LEVEL") % [m.level, m.max_level] if m.max_level > 1 else ""
	var kind_line: String = tr("MAP_KIND_" + m.kind.to_upper())
	if not m.excludes.is_empty():
		kind_line += " · " + tr("UI_MAP_CHOICE")
	_tip_box.add_child(_ink(kind_line + ("  ·  " + lvl if lvl != "" else ""), "copper_1"))
	if dummy > 0:
		return
	if m.status == "available" or m.status == "locked" or (m.status == "hidden" and m.reward_of != ""):
		for line: String in kit.novelty_lines(id):
			_tip_box.add_child(_ink("• " + line, "ember_0"))
		var n: int = 0
		for d: Dictionary in kit.diff_lines(id):
			if n >= int(kit.f("map.tip_rows", 4)):
				break
			_tip_box.add_child(_ink(str(d["text"]), "verdigris_0" if bool(d["good"]) else "ember_1"))
			n += 1
		if kit.novelty_lines(id).is_empty() and n == 0:
			_tip_box.add_child(_ink(tr(kit.desc_key(id)), "soot_1"))
	else:
		_tip_box.add_child(_ink(tr(kit.desc_key(id)), "soot_1"))
	match m.status:
		"available":
			var cost: Dictionary = core.price(id)
			var row := kit.hbox(4)
			for r: String in cost:
				row.add_child(kit.icon(kit.res_icon(r), 24))
				var ok: bool = core.state.res(r) >= float(cost[r])
				var cl := _ink(Fmt.num(float(cost[r])) + "  ", "copper_0" if ok else "ember_1", true)
				cl.custom_minimum_size = Vector2.ZERO
				cl.autowrap_mode = TextServer.AUTOWRAP_OFF
				row.add_child(cl)
			if not m.afford and m.ttl < INF:
				var tl := _ink("~" + Fmt.time(maxf(1.0, m.ttl)), "copper_1")
				tl.custom_minimum_size = Vector2.ZERO
				tl.autowrap_mode = TextServer.AUTOWRAP_OFF
				row.add_child(tl)
			_tip_box.add_child(row)
			if not m.excludes.is_empty() and m.level == 0:
				_tip_box.add_child(_ink(tr("UI_MAP_CHOICE_WARN"), "ember_1", true))
			else:
				_tip_box.add_child(_ink(tr("UI_MAP_CLICK" if m.max_level > 1 else "UI_MAP_CLICK1"), "copper_1"))
		"locked":
			var names: PackedStringArray = []
			for p: String in m.parents:
				names.append("«%s»" % tr(kit.name_key("node:" + p)))
			_tip_box.add_child(_ink(tr("UI_MAP_LOCKED") % " / ".join(names), "copper_1"))
		"excluded":
			_tip_box.add_child(_ink(tr("UI_MAP_EXCLUDED"), "ember_1"))
		"maxed":
			_tip_box.add_child(_ink(tr("UI_MAP_MAXED"), "verdigris_0"))
		"hidden":
			if m.reward_of != "":
				var bn: String = str(core.data.bosses.get(m.reward_of, {}).get("name", m.reward_of))
				_tip_box.add_child(_ink(tr("UI_MAP_REWARD") % tr(bn), "copper_1"))


# --- drawing ---------------------------------------------------------------------------

func _state_of(m: MNode) -> String:
	if m.status == "excluded":
		return "excluded"
	if m.status == "maxed":
		return "maxed"
	if m.level > 0:
		return "purchased"
	if m.status == "available":
		return "available"
	return "locked"


func _frame_of(m: MNode) -> int:
	var states: Dictionary = SpriteLib.info(m.sprite).get("states", {})
	var st: String = _state_of(m)
	if st == "available":
		if not m.afford:
			return 1
		var fr: Array = states.get("available", [1, 2, 3])
		return int(fr[int(_time * kit.f("map.pulse_fps", 6.0) + m.pos.x * 0.01) % fr.size()])
	return int(states.get(st, 0))


func _road_frame(a: MNode, b: MNode) -> int:
	if a.level > 0 and b.level > 0:
		return 2
	if a.level > 0 and (b.status == "available" or b.status == "excluded"):
		return 1 if b.status == "available" else 0
	return 0


func _draw_roads(l: Node2D) -> void:
	var step: float = kit.f("map.road_step", 7.0)
	var gap: float = kit.f("map.road_gap", 10.0)
	var anc: Vector2 = SpriteLib.anchor("map_road_dot")
	var tex: Array = [SpriteLib.texture("map_road_dot", 0), SpriteLib.texture("map_road_dot", 1), SpriteLib.texture("map_road_dot", 2)]
	for m: MNode in order:
		for pid: String in m.parents:
			var p: MNode = nodes.get(pid, null)
			if p == null:
				continue
			var fr: int = _road_frame(p, m)
			var ln: float = p.pos.distance_to(m.pos)
			var d: float = gap
			while d < ln - gap:
				l.draw_texture(tex[fr], (p.pos.lerp(m.pos, d / ln) - anc).round())
				d += step
	# choice pairs: a dashed ink tie between the two options
	for f: Array in _fork_mid:
		var a: MNode = nodes[str(f[1])]
		var b: MNode = nodes[str(f[2])]
		var ln2: float = a.pos.distance_to(b.pos)
		var d2: float = 14.0
		while d2 < ln2 - 14.0:
			l.draw_rect(Rect2(a.pos.lerp(b.pos, d2 / ln2).round(), Vector2(2, 1)), Color(_c["ember_0"], 0.55))
			d2 += 5.0


func _draw_markers(l: Node2D) -> void:
	var t0: int = Time.get_ticks_usec()
	_draw_markers_body(l)
	marker_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _draw_markers_body(l: Node2D) -> void:
	var font: FontFile = ViewKit.FONT_BOLD
	for m: MNode in order:
		var tex: Texture2D = SpriteLib.texture(m.sprite, _frame_of(m))
		var anc: Vector2 = SpriteLib.anchor(m.sprite)
		var mod := Color.WHITE
		if m.status == "available" and not m.afford and m.level == 0:
			mod = Color(0.82, 0.78, 0.74)
		l.draw_texture(tex, (m.pos - anc).round(), mod)
		# level pips under multi-level nodes that are bought but not finished
		if m.max_level > 1 and m.level > 0 and m.status != "maxed":
			var w: float = float(m.max_level) * 3.0 - 1.0
			var x0: float = roundf(m.pos.x - w * 0.5)
			var y0: float = m.pos.y + anc.y + 2.0
			l.draw_rect(Rect2(x0 - 1, y0 - 1, w + 2, 4), Color(_c["parchment_2"], 0.9))
			for i in m.max_level:
				l.draw_rect(Rect2(x0 + i * 3, y0, 2, 2), _c["brass_2"] if i < m.level else _c["copper_1"])
		# a node that can be bought (again): a brass glint that walks around it
		if m.status == "available" and m.afford:
			var ang: float = _time * 3.0 + m.pos.y * 0.05
			var r: float = anc.x + 3.0
			l.draw_rect(Rect2((m.pos + Vector2(cos(ang), sin(ang)) * r).round() - Vector2(1, 1), Vector2(3, 3)), _c["brass_3"])
		elif m.status == "available" and m.ttl < INF and m.ttl > 0.0 and m.level == 0:
			var t: String = "~" + Fmt.time(maxf(1.0, m.ttl))
			var tw: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var tp := Vector2(roundf(m.pos.x - tw * 0.5), m.pos.y + anc.y + 11.0)
			l.draw_rect(Rect2(tp + Vector2(-2, -10), Vector2(tw + 4, 12)), Color(_c["parchment_2"], 0.85))
			l.draw_string(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _c["copper_1"])
	for f: Array in _fork_mid:
		var a: MNode = nodes[str(f[1])]
		if not _region_open(a.region) and _fog.has(a.region):
			continue
		var mid: Vector2 = f[0]
		if bool(f[3]):
			var b: MNode = nodes[str(f[2])]
			var st: String = "excluded" if a.status == "excluded" or b.status == "excluded" else ("available" if a.status == "available" else "locked")
			var states: Dictionary = SpriteLib.info("node_choice").get("states", {})
			var fr: int = int(states.get("purchased", 4)) if st == "excluded" else (1 if st == "available" else 0)
			l.draw_texture(SpriteLib.texture("node_choice", fr), (mid - SpriteLib.anchor("node_choice")).round())
		else:
			var t2: String = tr("UI_MAP_OR")
			var w2: float = font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			l.draw_rect(Rect2(mid + Vector2(-w2 * 0.5 - 2, -7), Vector2(w2 + 4, 12)), Color(_c["parchment_2"], 0.9))
			l.draw_string(font, mid + Vector2(roundf(-w2 * 0.5), 3), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _c["ember_0"])
	if _hover != null:
		var ra: float = SpriteLib.anchor(_hover.sprite).x + 4.0
		l.draw_arc(_hover.pos, ra, 0.0, TAU, 24, _c["soot_1"], 1.0)
		l.draw_arc(_hover.pos, ra + 1.0, 0.0, TAU, 24, Color(_c["brass_3"], 0.8), 1.0)


func _draw_fx(l: Node2D) -> void:
	for f: Fx in _fx:
		if f.t < f.delay:
			continue
		var tt: float = f.t - f.delay
		var info: Dictionary = SpriteLib.info(f.sprite)
		var n: int = int(info.get("frames", 1))
		var fps: float = maxf(1.0, float(info.get("fps", 10.0)))
		var fr: int = (int(tt * fps) % n) if f.loop else mini(int(tt * fps), n - 1)
		var p: Vector2 = f.pos.lerp(f.b, clampf(tt / f.dur, 0.0, 1.0)) if f.loop else f.pos
		l.draw_texture(SpriteLib.texture(f.sprite, fr), (p - SpriteLib.anchor(f.sprite)).round(), f.mod)
	# «что купить»: a brass pointer bobbing over the suggested node
	if _hint != null and visible:
		var bob: float = roundf(sin(_time * 4.0) * 2.0)
		var top: Vector2 = _hint.pos + Vector2(0, -SpriteLib.anchor(_hint.sprite).y - 6 + bob)
		var pts := PackedVector2Array([top + Vector2(-5, -6), top + Vector2(5, -6), top])
		l.draw_colored_polygon(PackedVector2Array([pts[0] + Vector2(-1, -1), pts[1] + Vector2(1, -1), pts[2] + Vector2(0, 2)]), _c["soot_1"])
		l.draw_colored_polygon(pts, _c["brass_3"])
		var t: String = tr("UI_MAP_HINT_BUY")
		var w: float = ViewKit.FONT_BOLD.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tp := Vector2(roundf(top.x - w * 0.5), top.y - 10)
		l.draw_rect(Rect2(tp + Vector2(-3, -10), Vector2(w + 6, 13)), _c["soot_1"])
		l.draw_string(ViewKit.FONT_BOLD, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _c["brass_3"])


# --- juice -----------------------------------------------------------------------------

func _fx_add(sprite: String, pos: Vector2, delay: float, mod: Color = Color.WHITE) -> Fx:
	var f := Fx.new()
	f.sprite = sprite
	f.pos = pos
	f.b = pos
	f.delay = delay
	f.mod = mod
	var info: Dictionary = SpriteLib.info(sprite)
	f.dur = float(info.get("frames", 1)) / maxf(1.0, float(info.get("fps", 10.0)))
	if _fx.size() < int(kit.f("map.max_fx", 160)):
		_fx.append(f)
	return f


## Bought: ink splat, then the wax stamp; a spark runs along every road to the node's children.
func _stamp(m: MNode, delay: float) -> void:
	var sp := _fx_add("map_ink_splat", m.pos, delay)
	_fx_add("map_stamp", m.pos, delay + sp.dur * 0.6)
	for c: MNode in order:
		if c.parents.has(m.id) and (c.status == "available" or c.level > 0):
			var s := _fx_add("map_spark", m.pos, delay + 0.25)
			s.b = c.pos
			s.loop = true
			s.dur = maxf(0.25, m.pos.distance_to(c.pos) / kit.f("map.spark_speed", 160.0))


## A region opens: its fog burns away in puffs, wisps go, a banner names the land.
func _burn(r: int) -> void:
	var fog: Sprite2D = _fog[r]
	var bb: Array = []
	for rr: Dictionary in lay.get("regions", []):
		if int(rr["id"]) == r:
			bb = rr["bbox"]
	if bb.size() == 4:
		# a burning front sweeps across the region from the side nearest the fortress
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + r
		var f: Array = lay.get("fortress", [500, 370])
		var home: Vector2 = art_of(Vector2(float(f[0]), float(f[1])))
		var far: float = 1.0
		var pts: Array[Vector2] = []
		for i in int(kit.f("map.burn_puffs", 46)):
			var p := Vector2(rng.randf_range(float(bb[0]), float(bb[2])), rng.randf_range(float(bb[1]), float(bb[3])))
			pts.append(p.round())
			far = maxf(far, p.distance_to(home))
		var near: float = far
		for p: Vector2 in pts:
			near = minf(near, p.distance_to(home))
		var sweep: float = kit.f("map.burn_sweep", 0.9)
		for p: Vector2 in pts:
			_fx_add("map_fog_burn", p, sweep * (p.distance_to(home) - near) / maxf(1.0, far - near) + rng.randf() * 0.15)
	_fog_fade[r] = 0.0
	banner(tr("UI_REGION_OPEN") % tr("REGION_%d" % r))
	if fog != null:
		fog.visible = true


func _step_fx(delta: float) -> void:
	var i: int = _fx.size() - 1
	while i >= 0:
		var f: Fx = _fx[i]
		f.t += delta
		if f.t >= f.delay + f.dur:
			_fx.remove_at(i)
		i -= 1
	for r: int in _fog_fade.keys():
		_fog_fade[r] = float(_fog_fade[r]) + delta
		var fog: Sprite2D = _fog[r]
		var k: float = float(_fog_fade[r])
		# the fog holds while the first puffs flare (frame 3 of map_fog_burn), then thins out
		fog.modulate.a = clampf(1.0 - (k - 0.3) / 0.9, 0.0, 1.0)
		if k > 1.25:
			fog.visible = false
			fog.modulate.a = 1.0
			_fog_fade.erase(r)
	for w: Array in _wisps:
		var spr: AnimatedSprite2D = w[0]
		var ph: float = float(w[2]) + _time * 0.15
		spr.offset = Vector2(roundf(sin(ph) * 10.0), roundf(cos(ph * 0.7) * 4.0))
