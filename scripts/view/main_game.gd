class_name MainGame
extends Control
## The game screen (scenes/main_game.tscn). Starts the core (autoload Game),
## builds the view layers and routes core events to juicy feedback:
##   Shake (Node2D, shaken as a whole) ─ BattleView (art ×2: scenery, wall,
##   units; FxLayer + DecalLayer) ─ PopupLayer (numbers, screen px)
##   Hud (resource bar, goal, boss bar, toasts, banners, enemy tooltip)
##   ShopPanel (right tabs)   LootFly (flying loot + UI sparks, topmost)
## Reads the core every frame and drains its events; never changes game rules.
## Debug args: --debug-view (old debug scene), --stress (keep ~150 enemies and
## ~300 projectiles alive), --perf=<sec> (print frame-time stats and quit),
## --give=gears:500,blueprints:40 (add resources at start), --buy=id,id,...
## with --buy-at=<sec> (press those shop buttons at that game time; screenshots),
## --tab=<0|1> (open a panel tab), --mouse=enemy (cursor follows an enemy).

const THEME: Theme = preload("res://themes/main_theme.tres")
const DEBUG_SCENE: String = "res://scenes/battle_debug.tscn"

var kit: ViewKit
var core: GameCore
var bv: BattleView
var popups: PopupLayer
var loot: LootFly
var hud: Hud
var shop: ShopPanel
var _shake_root: Node2D
var _shake_amp: float = 0.0
var _refresh_t: float = 0.0
var _base_timescale: float = 1.0
var _slowmo_until: int = 0
var _milestone_towers: Dictionary = {}
var _stress: bool = false
var _fx_demo: bool = false
var _fx_demo_t: float = 0.0
var _perf_secs: float = -1.0
var _perf_start: int = 0
var _perf_last: int = 0
var _perf_frames: Array[float] = []
var _perf_max: Dictionary = {}
var _perf_acc: Dictionary = {}      ## ms spent per section (summed), for --perf
var _perf_warm: bool = false
var _field_w: float = 900.0
var _boss_pos: Vector2 = Vector2(560, 380)
var _mods_frame: Mods = null       ## core.mods at the end of the last frame ("было" for purchase popups)
var _shown_ids: Dictionary = {}
var _purchases_in_frame: int = 0
var _frame_keys: Dictionary = {}     ## behaviour keys unlocked this frame (toast de-duplication)
var _mouse_follow: bool = false
var _tip_mouse: Vector2 = Vector2.ZERO
var _tip_rest: float = 0.0
var _follow_t: float = 0.0
var _tip_uid: int = -1
var choice: ChoiceOverlay
var map: MapScreen
var _label_at: Dictionary = {}     ## label kind -> view time it was last shown (global rate limit)
var _armor_blocked: float = 0.0    ## damage the boss's frontal armour soaked this fight (retreat hint)
var _buy_list: PackedStringArray = []
var _map_at: float = -1.0
var _buy_at: float = 1.0


func _ready() -> void:
	if DevTools.has_arg("debug-view"):
		get_tree().change_scene_to_file.call_deferred(DEBUG_SCENE)
		return
	theme = THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	core = Game.start()
	kit = ViewKit.new(core)
	_field_w = 1280.0 - kit.f("panel_width", 380)
	var bg := ColorRect.new()
	bg.color = kit.col("soot_1")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_shake_root = Node2D.new()
	_shake_root.name = "Shake"
	add_child(_shake_root)
	bv = BattleView.new()
	bv.name = "Battle"
	_shake_root.add_child(bv)
	bv.setup(kit)
	bv.shake_cb = shake
	popups = PopupLayer.new()
	popups.name = "Popups"
	_shake_root.add_child(popups)
	popups.setup(kit)
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(kit)
	shop = ShopPanel.new()
	shop.name = "Shop"
	add_child(shop)
	shop.setup(kit)
	map = MapScreen.new()
	map.name = "Map"
	add_child(map)
	choice = ChoiceOverlay.new()
	choice.name = "Choice"
	add_child(choice)
	choice.setup(kit, shop)
	shop.compare_requested.connect(choice.open)
	map.setup(kit, shop, choice, int(DevTools.get_arg("map-dummy", "0")))
	shop.map_requested.connect(map.open)
	# the battle keeps ticking under the map, but nothing of it is visible: skip drawing it
	map.visibility_changed.connect(func() -> void:
		_shake_root.visible = not map.visible
		shop.visible = not map.visible)
	loot = LootFly.new()
	loot.name = "LootFly"
	add_child(loot)
	loot.setup(kit)
	loot.target_cb = hud.plate_target
	loot.arrive_cb = hud.bump
	hud.goal_clicked.connect(_on_goal_clicked)
	hud.boss_call_pressed.connect(_on_boss_call)
	shop.bought.connect(_on_shop_bought)
	_base_timescale = Engine.time_scale
	for pair: String in DevTools.get_arg("give", "").split(",", false):
		var kv: PackedStringArray = pair.split(":")
		if kv.size() == 2:
			# debug money is not loot: it must not show up as income
			core.state.resources[kv[0]] = core.state.res(kv[0]) + kv[1].to_float()
	_buy_list = DevTools.get_arg("buy", "").split(",", false)
	_buy_at = DevTools.get_arg("buy-at", "1").to_float()
	_stress = DevTools.has_arg("stress")
	_fx_demo = DevTools.has_arg("fx-demo")
	_mouse_follow = DevTools.get_arg("mouse", "") == "enemy"
	_perf_secs = DevTools.get_arg("perf", "-1").to_float()
	hud.refresh()
	shop.refresh()
	if DevTools.has_arg("tab"):
		shop.current_tab = clampi(DevTools.get_arg("tab").to_int(), 0, shop.get_tab_count() - 1)
	_map_at = DevTools.get_arg("open-map", "-1").to_float()
	if DevTools.has_arg("map-zoom"):
		map.call_deferred("_set_zoom", DevTools.get_arg("map-zoom").to_int(), Vector2(640, 340))
	print("Main scene ready: MainGame (locale %s, t=%.0fs)" % [TranslationServer.get_locale(), core.state.time])


# --- frame ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if core == null:
		return
	if _mouse_follow and Game.bot == null:
		_follow_t -= delta
		if _follow_t <= 0.0:
			_follow_t = 1.2   # warp, then rest: the tooltip needs a resting mouse
			_follow_enemy()
	if Game.bot == null:
		var mp: Vector2 = get_global_mouse_position()
		var over: bool = not choice.visible and not map.visible and mp.x < _field_w and mp.y > kit.f("bar_height", 40) and core.battle.in_field(mp) \
			and get_viewport().get_visible_rect().has_point(get_viewport().get_mouse_position())
		core.set_cursor(mp, over)
	if _stress:
		_stress_fill()
	if _fx_demo:
		_fx_demo_tick(delta)
	if _map_at >= 0.0 and DevTools.game_time >= _map_at:
		_map_at = -1.0
		map.open()
		map.recentre()
		if DevTools.has_arg("map-focus"):
			var fp: PackedStringArray = DevTools.get_arg("map-focus").split(",")
			map.focus_art(Vector2(fp[0].to_float(), fp[1].to_float()))
		if DevTools.get_arg("mouse", "") == "map-hint":
			_warp_to_hint.call_deferred()
	if not _buy_list.is_empty() and DevTools.game_time >= _buy_at:
		for id: String in _buy_list:
			if id.begins_with("compare:"):
				_on_goal_clicked(id.substr(8))   # opens the choice overlay for that node
			else:
				shop.press(id)
		_buy_list = PackedStringArray()
	_milestone_towers.clear()
	_shown_ids.clear()
	if _mods_frame == null:
		_mods_frame = core.mods
	var t0: int = Time.get_ticks_usec()
	var events: Array = core.drain_events()
	_purchases_in_frame = 0
	_frame_keys.clear()
	for ev: Dictionary in events:
		if str(ev["type"]) == "purchased":
			_purchases_in_frame += 1
		elif str(ev["type"]) == "unlocked":
			_frame_keys[str(ev["id"])] = true
	for ev: Dictionary in events:
		_on_event(ev)
	var t1: int = Time.get_ticks_usec()
	bv.update_view(delta)
	_update_tooltip(delta)
	_update_shake(delta)
	_update_slowmo()
	var t2: int = Time.get_ticks_usec()
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = kit.f("ui_refresh", 0.15)
		hud.refresh()
		shop.refresh()
	if _perf_secs > 0.0 and _perf_warm:
		_perf_acc["events"] = float(_perf_acc.get("events", 0.0)) + (t1 - t0) / 1000.0
		_perf_acc["view"] = float(_perf_acc.get("view", 0.0)) + (t2 - t1) / 1000.0
		_perf_acc["ui"] = float(_perf_acc.get("ui", 0.0)) + (Time.get_ticks_usec() - t2) / 1000.0
		_perf_acc["draw_fx"] = float(_perf_acc.get("draw_fx", 0.0)) + bv.fx.draw_ms
		_perf_acc["draw_pop"] = float(_perf_acc.get("draw_pop", 0.0)) + popups.draw_ms
		_perf_acc["draw_decal"] = float(_perf_acc.get("draw_decal", 0.0)) + bv.decals.draw_ms
		_perf_acc["draw_loot"] = float(_perf_acc.get("draw_loot", 0.0)) + loot.draw_ms
		_perf_acc["core_tick"] = float(_perf_acc.get("core_tick", 0.0)) + Game.last_tick_ms
		_perf_acc["n_events"] = float(_perf_acc.get("n_events", 0.0)) + events.size()
	_mods_frame = core.mods
	if _perf_secs > 0.0:
		_perf_sample()


func _unhandled_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo:
		if k.keycode == KEY_M:
			map.toggle()
		elif k.keycode == KEY_ESCAPE and map.visible:
			map.close()
		elif k.keycode == KEY_1:
			shop.current_tab = 0
		elif k.keycode == KEY_2:
			shop.current_tab = 1


## --mouse=map-hint (screenshots): the cursor rests on the suggested node, so its tooltip shows.
func _warp_to_hint() -> void:
	if map._hint != null:
		get_viewport().warp_mouse(map.global_position + map.screen_of(map._hint))


# --- events -> feedback ------------------------------------------------------------------

func _head_screen(uid: int, pos: Vector2) -> Vector2:
	var ev: BattleView.EnemyView = bv.enemy_view(uid)
	var head: float = bv.fx._head_of(ev.type) if ev != null else 12.0
	return pos + Vector2(0, -head * kit.art_scale)


func _on_event(ev: Dictionary) -> void:
	var fx: FxLayer = bv.fx
	match str(ev["type"]):
		"enemy_hit":
			var src: String = str(ev["source"])
			var uid: int = int(ev["uid"])
			var pos: Vector2 = ev["pos"]
			if src == "lens":
				return
			var crit: bool = bool(ev["crit"])
			bv.flash_enemy(uid, crit)
			var ev_v: BattleView.EnemyView = bv.enemy_view(uid)
			var mid: Vector2 = kit.to_art(pos) + Vector2(0, -(fx._head_of(ev_v.type) if ev_v != null else 10.0) * 0.5)
			fx.hit_sparks(mid, str(ev["dmg_type"]), crit)
			popups.damage(uid, _head_screen(uid, pos), float(ev["amount"]), str(ev["dmg_type"]), crit)
			if bool(ev.get("armored", false)):
				_on_armored_hit(ev, mid)
			elif bool(ev.get("shielded", false)):
				fx.shield_spark(mid + Vector2(-2, -4))
				if bv.label_ok(uid, kit.f("fx.helmet_label_every", 5.0)) and _label_free("helmet"):
					popups.text(_head_screen(uid, pos) + Vector2(-34, 4), tr("UI_HELMET"), kit.col("copper_3"), 24, 0.7, 14.0)
		"enemy_dot":
			# scalding shows as steam on the enemy; numbers only for the moat curtain and puddles
			if str(ev["source"]) == "scald":
				return
			var uid2: int = int(ev["uid"])
			popups.damage(uid2, _head_screen(uid2, ev["pos"]), float(ev["amount"]), "steam", false, kit.f("popup.dot_every", 1.0))
		"enemy_killed":
			_on_kill(ev)
		"enemy_fell_in_moat":
			var p: Vector2 = ev["pos"]
			var fev: BattleView.EnemyView = bv.enemy_view(int(ev["uid"]))
			var fsp: Dictionary = kit.enemy_sprites(str(ev["enemy"]))
			var bare: bool = fev != null and fsp.has("bare_walk") and fev.anim_name == str(fsp["bare_walk"])
			fx.fall(kit.to_art(p), str(ev["enemy"]), str(fsp.get("bare_fall", "")) if bare else "")
			popups.text(Vector2(p.x - 22.0, p.y - 26.0), tr("UI_BLUB"), kit.col("steam_2"), 24, 0.9, 16.0)
			hud.bump_falls()
		"projectile_fired":
			bv.on_tower_fired(str(ev["tower"]), int(ev["tower_index"]))
		"cone_fired":
			bv.on_tower_fired(str(ev["tower"]), int(ev["tower_index"]))
			fx.cone(ev["from"], ev["dir"], float(ev["length"]), float(ev["angle"]))
		"shell_exploded":
			var frag: bool = bool(ev["fragment"])
			fx.explosion(kit.to_art(ev["pos"]), float(ev["radius"]) / kit.art_scale, bool(ev["crit"]), frag,
				str(kit.v("explosion_sprites." + kit.tower_base(str(ev["tower"])), "explosion")))
			if not frag:
				shake(kit.f("shake.mortar_crit" if bool(ev["crit"]) else "shake.mortar", 1.2))
		"bullet_burst":
			fx.explosion(kit.to_art(ev["pos"]), float(ev["radius"]) / kit.art_scale, false, true)
		"crit_chain":
			fx.chain(ev["from"], ev["to"])
		"zone_created":
			fx.steam_burst(kit.to_art(ev["pos"]), 2)
		"ability_fired":
			bv.king_tea()
			fx.kettle_arc(bv.king_pos() + Vector2(5, -14), ev["pos"])
		"lens_tick":
			fx.lens_tick(ev["pos"], int(ev["hits"]))
			if float(ev["damage"]) > 0.0:
				var r: float = float(ev["radius"])
				popups.damage(-100 - int(ev["index"]), ev["pos"] + Vector2(0, -r * 0.7), float(ev["damage"]), "steam", false,
					kit.f("popup.lens_every", 0.5))
		"enemy_status":
			match str(ev["status"]):
				"scald":
					fx.anim("steam_puff", kit.to_art(_head_screen(int(ev["uid"]), ev["pos"])))
				"stun":
					fx.burst(kit.to_art(_head_screen(int(ev["uid"]), ev["pos"])), ["brass_3", "parchment_2"], 4, 22.0, 0.3)
		"enemy_emerge":
			if bool(ev["forced"]):
				var ep: Vector2 = ev["pos"]
				fx.burst(kit.to_art(ep), ["dust_2", "dust_0", "soot_2", "brass_3"], 10, 40.0, 0.5, 90.0, 1.0, 30.0)
				if bv.label_ok(int(ev["uid"]), kit.f("fx.label_every", 0.7)) and _label_free("dug"):
					popups.text(ep + Vector2(0, -30), tr("UI_DUG_OUT"), kit.col("dust_2"), 24, 0.8, 16.0)
		"enemy_charge":
			var cp: Vector2 = ev["pos"]
			fx.dust(kit.to_art(cp) + Vector2(14, -2), 14)
			popups.text(_head_screen(int(ev["uid"]), cp) + Vector2(0, -10), tr("UI_CHARGE"), kit.num_color("bad"), 24, 0.9, 18.0, true)
			shake(kit.f("shake.charge", 1.5))
		"enemy_split":
			pass   # the golem's own split animation plays on its enemy_killed (game_view.enemy_sprites.*.death)
		"enemy_shield_broken":
			var hp2: Vector2 = ev["pos"]
			var hsp: Dictionary = kit.enemy_sprites(str(bv.enemy_view(int(ev["uid"])).type) if bv.enemy_view(int(ev["uid"])) != null else "diver")
			fx.helmet_break(kit.to_art(hp2), str(hsp.get("shield_break", "diver_helmet_break")))
			popups.text(_head_screen(int(ev["uid"]), hp2) + Vector2(0, -8), tr("UI_HELMET_BROKEN"), kit.col("copper_3"), 24, 1.0, 18.0, true)
		"chain_fired":
			bv.on_tower_fired(str(ev["tower"]), int(ev["tower_index"]))
			fx.bolt(ev["from"], ev["points"])
		"ricochet":
			fx.ricochet(ev["from"], ev["to"], int(ev["bounce"]))
		"geyser":
			fx.geyser(ev["pos"], float(ev["radius"]))
			bv.flare_furnaces()
			shake(kit.f("shake.geyser", 1.5))
		"drill_ram":
			var rp: Vector2 = ev["pos"]
			fx.drill_ram(rp.y, rp.x, float(ev["x_end"]))
			shake(kit.f("shake.drill_ram", 3.0))
		"producer_output":
			_on_producer(ev)
		"enemy_burrow":
			var bsp: Dictionary = kit.enemy_sprites(str(bv.enemy_view(int(ev["uid"])).type) if bv.enemy_view(int(ev["uid"])) != null else "")
			var banim: String = str(bsp.get("burrow" if bool(ev["under"]) else "emerge", ""))
			if banim != "":
				fx.anim(banim, kit.to_art(ev["pos"]))
			fx.burst(kit.to_art(ev["pos"]), ["dust_2", "dust_0", "soot_2"], 8, 26.0, 0.4, 80.0, 1.0, 18.0)
		"purchased":
			_on_purchased(ev)
		"milestone":
			_on_milestone(ev)
		"unlocked":
			_on_unlocked(ev)
		"boss_spawned":
			_armor_blocked = 0.0
			var bn: String = tr(str(core.data.bosses[str(ev["boss"])]["name"]))
			hud.banner(tr("UI_BOSS_COMING") % bn, tr("UI_BOSS_COMING_SUB"), "ember_1")
			shake(kit.f("shake.boss_spawn", 4.0))
		"boss_retreated":
			var bp: Vector2 = kit.to_art(ev["pos"])
			var bsp2: Dictionary = kit.enemy_sprites(str(core.data.bosses[str(ev["boss"])]["enemy"]))
			if bsp2.has("retreat"):
				# backs off to the right, nose up, smoking (its own sprite already faces the retreat)
				fx.loop_anim(str(bsp2["retreat"]), bp, kit.f("fx.retreat_time", 1.6), Vector2(kit.f("fx.retreat_speed", 46.0), 0))
			else:
				fx.anim(str(bsp2.get("walk", "boss_walk")), bp, true, Color(1, 1, 1, 0.8), Vector2(40, 0))
			fx.steam_burst(bp, 4)
			var sub: String = ""
			if _armor_blocked >= 1.0:
				sub = tr("UI_BOSS_RETREAT_ARMOR") % Fmt.num(roundf(_armor_blocked))
			hud.banner(tr("UI_BOSS_RETREATED"), sub, "copper_1")
			_armor_blocked = 0.0
			shake(kit.f("shake.fall_boss", 3.0))
		"boss_defeated":
			_boss_pos = ev["pos"]
			var bp2: Vector2 = kit.to_art(_boss_pos)
			fx.explosion(bp2, 24.0, true, false)
			fx.kill(bp2, "boss", true)
			fx.steam_burst(bp2, 6)
			var bn2: String = tr(str(core.data.bosses[str(ev["boss"])]["name"]))
			hud.banner(tr("UI_BOSS_DEFEATED_T") % bn2, tr("UI_BOSS_DEFEATED_SUB"), "verdigris_0")
			shake(kit.f("shake.boss_defeated", 6.0))
			_slowmo()
		"boss_reward":
			var rew: Dictionary = ev["loot"]
			for r: String in rew:
				loot.fountain(_boss_pos, r, float(rew[r]), 24 if r == "gears" else 14)


func _on_kill(ev: Dictionary) -> void:
	var p: Vector2 = ev["pos"]
	var etype: String = str(ev["enemy"])
	var role: String = str(core.data.enemies.get(etype, {}).get("role", "normal"))
	var death: String = str(kit.enemy_sprites(etype).get("death", ""))
	if death != "":
		bv.fx.split(kit.to_art(p), death)
	else:
		bv.fx.kill(kit.to_art(p) + Vector2(0, -4), etype, role != "normal")
	var lt: Dictionary = ev["loot"]
	if role == "boss":
		return
	popups.loot(_head_screen(int(ev["uid"]), p), lt)
	if map.visible:
		return   # loot is already counted; coins flying out of a hidden battle would cross the map
	var cmax: int = int(kit.f("loot.coins_per_kill_max", 3))
	for r: String in lt:
		var amt: float = float(lt[r])
		if amt <= 0.0:
			continue
		var n: int = clampi(1 + int(floor(log(maxf(1.0, amt)) / log(10.0))), 1, cmax)
		loot.fly(p + Vector2(0, -16), r, amt, n)


## Direct fire on frontal armour (Бур-Великан): plate-hit frames, a hard spark off the plate, a rate-limited
## «броня» label, and the damage the plate soaked is tallied for the retreat banner's hint.
## Short field labels of one kind ("выбит!", "шлем") at most every fx.label_global_every s: a crowd of moles
## dug out by one blast is one label, not ten.
func _label_free(kind: String) -> bool:
	var now: float = bv.view_time()
	if now - float(_label_at.get(kind, -99.0)) < kit.f("fx.label_global_every", 1.5):
		return false
	_label_at[kind] = now
	return true


func _on_armored_hit(ev: Dictionary, mid_art: Vector2) -> void:
	var uid: int = int(ev["uid"])
	var e: Battle.Enemy = bv.enemy_by_uid(uid)
	bv.armor_hit(uid)
	bv.fx.armor_spark(mid_art + Vector2(-kit.f("fx.plate_dx", 12.0), 0), bool(ev["crit"]))
	if e != null:
		var src: String = str(ev.get("source", ""))
		var ap: float = 0.0
		if src.begins_with("tower:") and core.mods.tower_stats.has(src.substr(6)):
			ap = float(core.mods.tower_stats[src.substr(6)].get("armor_pierce", 0.0))
		var block: float = e.front_armor * (1.0 - ap) * (0.5 if core.mods.scald_shred and e.scald_t > 0.0 else 1.0)
		if block > 0.0 and block < 1.0:
			_armor_blocked += float(ev["amount"]) * block / (1.0 - block)
	if bv.label_ok(uid, kit.f("fx.armor_label_every", 1.2)):
		popups.text(_head_screen(uid, ev["pos"]) + Vector2(-60, 26), tr("UI_ARMOR"), kit.col("iron_3"), 24, 0.7, 12.0, true)


## A workshop delivered a batch: coal hops out of the building, «+3 уголь» / «+150 шест.» over it, and the
## goods fly to their counters (the reference hid its farm output — ours is loud).
func _on_producer(ev: Dictionary) -> void:
	var pid: String = str(ev["id"])
	if map.visible:
		return
	var at: Vector2 = bv.building_pos(pid)
	bv.fx.producer_burst(at)
	var top: Vector2 = kit.to_screen(at + Vector2(0, -kit.f("producer.popup_dy", 62.0)))
	var amt: Dictionary = ev["amount"]
	var dy: float = 0.0
	for r: String in amt:
		if float(amt[r]) <= 0.0:
			continue
		popups.produce(top + Vector2(kit.f("producer.popup_dx", 40.0), 0), r, float(amt[r]), dy)
		dy -= 30.0
		loot.fly(top + Vector2(0, 30), r, float(amt[r]), clampi(1 + int(log(maxf(1.0, float(amt[r]))) / log(10.0)), 1, 4))


func _on_purchased(ev: Dictionary) -> void:
	var id: String = str(ev["id"])
	if _shown_ids.has(id):
		return
	_shown_ids[id] = true
	var p: PackedStringArray = GameCore.split_id(id)
	var summary: String = ""
	if p[0] != "tower":
		if _purchases_in_frame == 1:
			var d: Array = kit.diff_lines(id, core.mods, _mods_frame)
			if not d.is_empty():
				summary = str((d[0] as Dictionary)["text"])
		elif p[0] == "upg":
			summary = tr(kit.name_key(id)) + " ↑"
	match p[0]:
		"upg":
			var t: String = str(core.data.upgrades[p[1]]["tower"])
			var tvs: Array[BattleView.TowerView] = bv.towers_of(t)
			for tv in tvs:
				bv.fx.sparkle(tv.feet + Vector2(0, -18), 6)
				tv.flash_t = 0.06
			if not tvs.is_empty() and summary != "":
				# short caption on a backing plate right of the upgraded towers
				var mid_tv: BattleView.TowerView = tvs[tvs.size() / 2]
				var at: Vector2 = kit.to_screen(mid_tv.feet + Vector2(0, -24))
				popups.text(Vector2(at.x + 140.0, at.y), summary, kit.num_color("good"), 24, 1.8, 14.0, true)
		"node":
			# numbers-only map node: a toast with the short "было → станет" (novelties toast themselves)
			if _frame_keys.is_empty() and summary != "":
				hud.toast(kit.node_icon(id), tr(kit.name_key(id)), summary)


func _on_milestone(ev: Dictionary) -> void:
	var t: String = str(ev["tower"])
	_milestone_towers[t] = true
	var name_key: String = str(ev["name"])
	var tvs: Array[BattleView.TowerView] = bv.towers_of(t)
	for tv in tvs:
		bv.fx.tier_ring(tv.feet + Vector2(0, -16))
	if not tvs.is_empty():
		var mid_tv: BattleView.TowerView = tvs[tvs.size() / 2]
		var at2: Vector2 = kit.to_screen(mid_tv.feet + Vector2(0, -30))
		popups.text(Vector2(at2.x + 170.0, at2.y), tr(name_key) + "!", kit.num_color("label"), 36, 2.0, 24.0, true)
	hud.toast(kit.tower_sprite(t, core.tower_tier(t)), tr(name_key), tr(name_key + "_DESC"))


func _on_unlocked(ev: Dictionary) -> void:
	var what: String = str(ev["what"])
	var id: String = str(ev["id"])
	if what == "region":
		hud.banner(tr("UI_REGION_OPEN") % tr("REGION_" + id), tr("UI_REGION_OPEN_SUB"), "copper_1")
		return
	if what != "behavior":
		return
	var p: PackedStringArray = id.split(":")
	if p[0] == "tier" or p[0] == "region":
		return
	if p.size() > 1 and _milestone_towers.has(p[1]):
		return
	# a new tower / mechanism brings its base behaviours: one toast for it
	if p.size() > 1 and p[0] != "tower" and p[0] != "ability" and p[0] != "enemy" \
			and (_frame_keys.has("tower:" + p[1]) or _frame_keys.has("ability:" + p[1])):
		return
	hud.toast(kit.behaviour_icon(id), tr("UI_NEW_TITLE"), kit.behaviour_text(id))


# --- input from UI ---------------------------------------------------------------------------

func _on_shop_bought(_id: String, at: Vector2) -> void:
	loot.burst(at, ["brass_3", "parchment_2", "brass_2"], 18)


func _on_goal_clicked(goal_id: String) -> void:
	if goal_id.begins_with("node:"):
		var ex: Array = core.data.node_excludes(goal_id.substr(5))
		if not ex.is_empty():
			var group: Array = [goal_id]
			for x: Variant in ex:
				if core.node_status(str(x)) == "available":
					group.append("node:" + str(x))
			choice.open(group)
			return
		if core.can_buy(goal_id):
			if core.buy(goal_id):
				loot.burst(Vector2(560, 70), ["brass_3", "parchment_2", "brass_2"], 22)
				shop.refresh()
				hud.refresh()
		else:
			# not affordable yet: show it where it lies on the conquest map
			map.show_node(goal_id.substr(5))
	elif goal_id.begins_with("boss:"):
		_on_boss_call()


func _on_boss_call() -> void:
	for bid: String in core.data.bosses:
		if core.can_call_boss(bid):
			core.call_boss(bid)
	hud.refresh()


## The cursor is a weapon and is almost always over enemies: the tooltip appears only after the
## mouse rests (hud.tip.delay) or while Alt is held, and hides as soon as the mouse moves.
func _update_tooltip(delta: float) -> void:
	var mp: Vector2 = get_global_mouse_position()
	if mp.distance_to(_tip_mouse) > kit.f("hud.tip.move_px", 4.0):
		_tip_mouse = mp
		_tip_rest = 0.0
	else:
		_tip_rest += delta
	var want: bool = _tip_rest >= kit.f("hud.tip.delay", 0.6) or Input.is_key_pressed(KEY_ALT)
	if not want:
		_tip_uid = -1
	if not want or (Game.bot != null and not _mouse_follow) or mp.x >= _field_w or mp.y < kit.f("bar_height", 40) \
			or choice.visible or map.visible:
		hud.show_enemy_tip(null, mp)
		return
	# pick the enemy once (generous radius: it keeps walking), then follow it while the mouse rests
	var e: Battle.Enemy = bv.enemy_by_uid(_tip_uid) if _tip_uid >= 0 else null
	if e == null:
		e = bv.enemy_at(mp, kit.f("hud.tip.pick_px", 30.0))
	_tip_uid = e.uid if e != null else -1
	if e == null:
		hud.show_enemy_tip(null, mp)
		return
	hud.show_enemy_tip(e, e.pos + Vector2(e.radius, -e.radius * 2.0))
	hud.refresh_tip_hp(e)


# --- shake / slow-mo ---------------------------------------------------------------------------

func shake(amount: float) -> void:
	var k: float = kit.f("shake.scale", 1.0)
	_shake_amp = minf(kit.f("shake.max", 6.0), maxf(_shake_amp, amount * k))


func _update_shake(delta: float) -> void:
	if _shake_amp <= 0.05:
		_shake_amp = 0.0
		_shake_root.position = Vector2.ZERO
		return
	var o := Vector2(randf_range(-_shake_amp, _shake_amp), randf_range(-_shake_amp, _shake_amp))
	_shake_root.position = (o * 0.5).round() * 2.0
	_shake_amp *= exp(-kit.f("shake.decay", 9.0) * delta)


func _slowmo() -> void:
	Engine.time_scale = _base_timescale * kit.f("boss_slowmo.scale", 0.35)
	_slowmo_until = Time.get_ticks_msec() + int(kit.f("boss_slowmo.time", 0.9) * 1000.0)


func _update_slowmo() -> void:
	if _slowmo_until > 0 and Time.get_ticks_msec() >= _slowmo_until:
		_slowmo_until = 0
		Engine.time_scale = _base_timescale


# --- stress & perf (debug args) -------------------------------------------------------------

## --mouse=enemy: the OS cursor follows the enemy closest to the field centre
## (screenshots of the manual lens and the enemy tooltip).
func _follow_enemy() -> void:
	var best: Battle.Enemy = null
	for e: Battle.Enemy in core.battle.enemies:
		if e.alive and not e.underground and e.pos.x < 760.0 and e.speed < 35.0 \
				and (best == null or absf(e.pos.x - 560.0) < absf(best.pos.x - 560.0)):
			best = e
	if best != null:
		get_viewport().warp_mouse(best.pos + Vector2(0, -best.radius))


## --fx-demo: replays every R2/R3 effect (lightning, ricochet, geyser, drill ram, workshop output, armour,
## helmet, dash, dug-out) on the live field every second, for screenshots of rare moments.
func _fx_demo_tick(delta: float) -> void:
	_fx_demo_t -= delta
	if _fx_demo_t > 0.0:
		return
	_fx_demo_t = 1.0
	var es: Array[Battle.Enemy] = []
	for e: Battle.Enemy in core.battle.enemies:
		if e.alive and not e.underground:
			es.append(e)
	var tw: Vector2 = core.battle.towers[0].pos if not core.battle.towers.is_empty() else Vector2(180, 360)
	var pts: Array = []
	for e: Battle.Enemy in es.slice(0, 4):
		pts.append(e.pos)
	if pts.is_empty():
		pts = [Vector2(450, 300), Vector2(500, 340)]
	var any: int = es[0].uid if not es.is_empty() else -1
	for ev: Dictionary in [
			{"type": "chain_fired", "tower": "tesla", "tower_index": 0, "from": tw, "points": pts, "hits": pts.size(), "crit": false},
			{"type": "ricochet", "uid": 1, "tower": "ricochet", "from": pts[0], "to": pts[pts.size() - 1], "bounce": 1},
			{"type": "geyser", "id": "geyser", "pos": Vector2(340, 250 + randf() * 250.0), "radius": 60.0, "hits": 0, "damage": 0.0, "shape": "splash"},
			{"type": "drill_ram", "id": "drill_ram", "pos": Vector2(290, 200 + randf() * 300.0), "x_end": 720.0, "width": 30.0,
				"hits": 0, "damage": 0.0, "shape": "line"},
			{"type": "producer_output", "id": core.data.producers.keys()[0], "amount": {"coal": 6.0, "gears": 300.0}, "level": 1},
			{"type": "enemy_emerge", "uid": any, "pos": pts[0], "forced": true}]:
		if str(ev["type"]) == "producer_output" and bv.buildings.is_empty():
			continue
		_on_event(ev)


func _stress_fill() -> void:
	var b: Battle = core.battle
	var want_e: int = int(kit.f("stress.enemies", 150))
	var types: Array[String] = core.mods.unlocked_enemies
	var guard: int = 0
	while b.alive_count() < want_e and guard < 40:
		guard += 1
		var t: String = types[randi() % types.size()]
		b.spawn_enemy_at(t, Vector2(randf_range(480.0, 900.0), randf_range(b.y_min, b.y_max)))
	var want_p: int = int(kit.f("stress.projectiles", 300))
	guard = 0
	while b.projectiles.size() < want_p and guard < 60 and not b.towers.is_empty() and not b.enemies.is_empty():
		guard += 1
		var tw: Battle.Tower = b.towers[randi() % b.towers.size()]
		var tgt: Battle.Enemy = b.enemies[randi() % b.enemies.size()]
		var p := Battle.Projectile.new()
		var roll: float = randf()
		p.kind = "bullet" if roll < 0.75 else ("rivet" if roll < 0.9 else "shell")
		p.tower = tw.type
		p.pos = tw.pos
		p.start = tw.pos
		p.dest = tgt.pos
		p.target = tgt if p.kind == "bullet" else null
		p.speed = 500.0
		p.dmg = 0.0
		p.dir = (tgt.pos - tw.pos).normalized()
		p.flight = 1.5
		p.pierce_left = 0
		b.projectiles.append(p)


func _perf_sample() -> void:
	var now: int = Time.get_ticks_usec()
	if _perf_start == 0:
		_perf_start = now
		_perf_last = now
		return
	var dt_ms: float = (now - _perf_last) / 1000.0
	_perf_last = now
	if (now - _perf_start) < 2_000_000:
		return   # warm-up
	_perf_warm = true
	_perf_frames.append(dt_ms)
	var counts: Dictionary = {"enemies": core.battle.alive_count(), "projectiles": core.battle.projectiles.size(),
		"popups": popups.pops.size(), "anims": bv.fx.anims.size(), "particles": bv.fx.particles.size(),
		"coins": loot.coins.size()}
	for k: String in counts:
		_perf_max[k] = maxi(int(_perf_max.get(k, 0)), int(counts[k]))
	if (now - _perf_start) / 1_000_000.0 >= _perf_secs + 2.0:
		var arr: Array[float] = _perf_frames.duplicate()
		arr.sort()
		var sum: float = 0.0
		for x in arr:
			sum += x
		var avg: float = sum / maxf(1.0, arr.size())
		var p95: float = arr[int(arr.size() * 0.95)] if not arr.is_empty() else 0.0
		var per_frame: Dictionary = {}
		for k: String in _perf_acc:
			per_frame[k] = snappedf(float(_perf_acc[k]) / maxf(1.0, float(_perf_frames.size())), 0.01)
		print("PERF frames=%d avg=%.2fms p95=%.2fms max=%.2fms fps=%.1f process=%.2fms view_ms_per_frame=%s max_counts=%s" % [
			arr.size(), avg, p95, arr[arr.size() - 1] if not arr.is_empty() else 0.0, 1000.0 / maxf(0.001, avg),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, str(per_frame), str(_perf_max)])
		_perf_secs = -1.0
		get_tree().quit(0)
