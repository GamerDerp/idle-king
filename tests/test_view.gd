extends "res://tests/test_case.gd"
## Game screen (scripts/view): every enemy/tower has its sprites, player-facing
## texts are translated, and the whole scene survives a scripted session
## (kills, falls, purchases, a milestone/tier-up, a boss fight and victory)
## without engine errors.

const SCENE := "res://scenes/main_game.tscn"


func _core() -> GameCore:
	var cfg: Dictionary = {}
	for n: String in Config.names():
		cfg[n] = Config.get_cfg(n)
	return GameCore.create(1, GameData.new(cfg))


func _has_sprite(n: String) -> bool:
	return (SpriteLib.manifest().get("sprites", {}) as Dictionary).has(n)


func test_every_enemy_and_tower_has_sprites() -> void:
	var kit := ViewKit.new(_core())
	for e: String in kit.core.data.enemies:
		var sp: Dictionary = (kit.v("enemy_sprites", {}) as Dictionary).get(e, {})
		assert_false(sp.is_empty(), "visual mapping for enemy %s" % e)
		for k: String in ["walk", "fall", "shadow"]:
			assert_true(_has_sprite(str(sp.get(k, ""))), "%s.%s sprite" % [e, k])
	for t: String in kit.core.data.towers:
		assert_true((kit.v("tower_sprites", {}) as Dictionary).has(t), "visual mapping for tower %s" % t)
		for tier in [1, 2, 3]:
			assert_true(_has_sprite(kit.tower_sprite(t, tier)), "%s tier %d sprite" % [t, tier])


func test_texts_are_translated() -> void:
	var kit := ViewKit.new(_core())
	var core: GameCore = kit.core
	core.state.add_res("gears", 1e9)
	core.state.add_res("blueprints", 1e9)
	core.state.add_res("coal", 1e9)
	var keys: Dictionary = {}
	for id: String in core.offer_ids():
		for k: Variant in core.novelty_of(id):
			keys[str(k)] = true
	for k: String in core.mods.behaviours():
		keys[k] = true
	for k: String in keys:
		var t: String = kit.behaviour_text(k)
		assert_true(t != k and not t.contains("_"), "behaviour text for %s: %s" % [k, t])
	var d: Array = kit.diff_lines("tower:shooter")
	assert_true(not d.is_empty() and str((d[0] as Dictionary)["text"]).contains("→"), "tower diff")
	var du: Array = kit.diff_lines("upg:shooter_dmg")
	assert_true(not du.is_empty(), "upgrade diff")
	for id: String in core.offer_ids():
		assert_true(tr(kit.name_key(id)) != kit.name_key(id), "name of %s" % id)


## Mods with every tower / enemy / mechanism unlocked, except what `skip` itself unlocks.
func _all_unlocked(data: GameData, skip: Dictionary) -> Mods:
	var m := Mods.new()
	for r: Variant in data.economy["start"]["regions"]:
		m.regions[int(r)] = true
	var groups: Dictionary = {"unlock_tower": data.towers, "unlock_enemy": data.enemies, "unlock_ability": data.abilities,
		"unlock_producer": data.producers}
	for ty: String in groups:
		for tgt: String in groups[ty]:
			if str(skip.get("type", "")) == ty and str(skip.get("target", "")) == tgt:
				continue
			m.apply_effect({"type": ty, "target": tgt}, 1)
	return m


## Every effect in the config (map nodes, shop upgrades and their milestones, boss rewards) shows at
## least one row in a card / the choice window: something new, or "было → станет".
func test_every_effect_type_renders_a_row() -> void:
	var kit := ViewKit.new(_core())
	var data: GameData = kit.core.data
	var effects: Array = []
	for n: String in data.nodes:
		for ef: Dictionary in data.node_effects(n):
			effects.append(["node:" + n, ef])
	for u: String in data.upgrades:
		for ef: Dictionary in data.upgrades[u]["effects"]:
			effects.append(["upg:" + u, ef])
		for ms: Dictionary in data.upgrades[u].get("milestones", []):
			for ef: Dictionary in ms["effects"]:
				effects.append(["upg:%s@%d" % [u, int(ms["level"])], ef])
	for b: String in data.bosses:
		for ef: Dictionary in data.bosses[b].get("on_defeat", []):
			effects.append(["boss:" + b, ef])
	var types: Dictionary = {}
	for pair: Array in effects:
		var ef: Dictionary = pair[1]
		var ty: String = str(ef["type"])
		types[ty] = true
		if ty == "call_boss":
			# an action, not a stat: the card says "Бой: <boss>"
			var t: String = kit.behaviour_text("boss:" + str(ef["target"]))
			assert_true(t != "boss:" + str(ef["target"]) and not t.contains("_"), "call_boss row for %s" % pair[0])
			continue
		var before: Mods = _all_unlocked(data, ef)
		before._derive(data)
		var after: Mods = _all_unlocked(data, ef)
		after.apply_effect(ef, 1)
		after._derive(data)
		var rows: PackedStringArray = kit.change_rows(before, after)
		assert_false(rows.is_empty(), "%s: effect %s shows no row" % [pair[0], ty])
		for r: String in rows:
			assert_false(r.contains("DIFF_") or r.contains("STATUS_") or r.contains("BEH_") or r.contains("_"),
				"%s: untranslated row %s" % [pair[0], r])
		if ty.ends_with("_status"):
			var has_status: bool = false
			for r: String in rows:
				# strength in % ("Ошпаривание 0% → 60% · 3с") or, for stun, its real length ("Оглушение 0с → 0.6с")
				has_status = has_status or (r.contains("→") and (r.contains("%") or r.contains(tr("UI_SEC")))
					and not r.contains("0" + tr("UI_SEC") + "\u00a0→\u00a00" + tr("UI_SEC")))
			assert_true(has_status, "%s: status %s has a было→станет row: %s" % [pair[0], ty, rows])
	assert_true(types.size() >= 20, "collected effect types: %d" % types.size())


func test_scene_survives_a_scripted_session() -> void:
	var mg: MainGame = (load(SCENE) as PackedScene).instantiate() as MainGame
	Engine.get_main_loop().root.add_child(mg)
	var core: GameCore = mg.core
	assert_true(core != null, "core started")
	var step := func(sec: float) -> void:
		var t: float = 0.0
		while t < sec:
			core.tick(0.05)
			mg._process(0.05)
			mg.bv.fx._process(0.05)
			mg.popups._process(0.05)
			mg.loot._process(0.05)
			mg.hud._process(0.05)
			t += 0.05
	step.call(20.0)
	assert_true(int(core.state.stats["kills"]) > 0, "something died")
	core.state.add_res("gears", 1e7)
	core.state.add_res("blueprints", 1e7)
	core.buy("tower:shooter")
	for i in 3:
		core.buy("upg:shooter_dmg")      # reaches the "double shot" milestone + tier-up
	for n: String in ["r0_horn", "r0_loopholes", "r0_kettle", "r0_road", "r1_dogs", "r1_riveter", "r1_curtain"]:
		core.buy("node:" + n)
	step.call(10.0)
	assert_eq(core.tower_tier("shooter"), 2)
	assert_eq(mg.bv.towers_of("shooter").size(), core.state.tower_count("shooter"))
	assert_true(core.call_boss("wasteland_chief", true), "boss called")
	step.call(3.0)
	assert_true(core.battle.boss_enemy != null, "boss on the field")
	core.battle.damage(core.battle.boss_enemy, 1e12, "blast", true, "test")
	step.call(3.0)
	assert_eq(core.state.boss_status("wasteland_chief"), "defeated")
	mg.shop.refresh()
	mg.shop.current_tab = 1
	mg.hud.refresh()
	assert_true(mg.popups.pops.size() <= int(mg.kit.f("popup.max", 30)), "popup cap")
	mg.free()
	Engine.time_scale = 1.0
	Game.running = false


## Region 2/3 on screen: every R2 enemy, tower, workshop and mechanism is bought / spawned, the Drill
## Giant fights, and every new event type goes through the screen without engine errors.
func test_scene_handles_r2_and_r3() -> void:
	var mg: MainGame = (load(SCENE) as PackedScene).instantiate() as MainGame
	Engine.get_main_loop().root.add_child(mg)
	var core: GameCore = mg.core
	var step := func(sec: float) -> void:
		var t: float = 0.0
		while t < sec:
			core.tick(0.05)
			mg._process(0.05)
			mg.bv.fx._process(0.05)
			mg.bv.decals._process(0.05)
			mg.popups._process(0.05)
			mg.loot._process(0.05)
			mg.hud._process(0.05)
			t += 0.05
	for r: String in ["gears", "blueprints", "coal", "copper"]:
		core.state.add_res(r, 1e9)
	# the whole map up to R3 (bosses beaten on the spot), except the Drill Giant: he fights on screen below
	for n: String in core.data.node_order:
		if n == "r2_boss" or n.begins_with("r2_trophy") or n.begins_with("r3_") or n in ["r2_steam_jet"]:
			continue
		core.buy("node:" + n)
		if core.battle.boss_enemy != null:
			core.battle.damage(core.battle.boss_enemy, 1e12, "blast", true, "test")
			core.tick(0.05)
	for t: String in ["boiler", "mortar", "riveter"]:
		core.buy("tower:" + t)
	step.call(1.0)
	assert_true(mg.bv.buildings.has("coal_mine"), "coal mine stands in the yard")
	for e: String in ["mole_miner", "coal_cart", "coal_golem", "coal_ember", "diver"]:
		for i in 3:
			core.battle.spawn_enemy_at(e, Vector2(420.0 + 60.0 * i, 200.0 + 90.0 * i))
	step.call(12.0)
	assert_true(core.call_boss("drill_giant", true), "drill giant called")
	step.call(4.0)
	var boss: Battle.Enemy = core.battle.boss_enemy
	assert_true(boss != null and mg.bv.enemy_view(boss.uid) != null, "boss on screen")
	# synthetic events with every field the core sends (rare ones may not happen in a short run)
	var p := Vector2(400, 300)
	var uid: int = boss.uid
	for ev: Dictionary in [
			{"type": "enemy_hit", "uid": uid, "amount": 5.0, "dmg_type": "impact", "crit": false, "pos": boss.pos,
				"source": "tower:shooter", "armored": true, "shielded": false},
			{"type": "enemy_charge", "uid": uid, "pos": boss.pos, "duration": 1.0},
			{"type": "enemy_emerge", "uid": -5, "pos": p, "forced": true},
			{"type": "enemy_shield_broken", "uid": -6, "pos": p},
			{"type": "enemy_split", "uid": -7, "enemy": "coal_golem", "pos": p, "child_type": "coal_ember", "children": []},
			{"type": "chain_fired", "tower": "tesla", "tower_index": 0, "from": Vector2(180, 300), "points": [p, p + Vector2(40, 20)],
				"hits": 2, "crit": false},
			{"type": "ricochet", "uid": 1, "tower": "ricochet", "from": p, "to": p + Vector2(30, 10), "bounce": 1},
			{"type": "geyser", "id": "geyser", "pos": Vector2(330, 300), "radius": 60.0, "hits": 3, "damage": 30.0, "shape": "splash"},
			{"type": "drill_ram", "id": "drill_ram", "pos": Vector2(290, 360), "x_end": 700.0, "width": 30.0, "hits": 2,
				"damage": 50.0, "shape": "line"},
			{"type": "producer_output", "id": "coal_mine", "amount": {"coal": 3.0, "gears": 150.0}, "level": 1},
			{"type": "enemy_status", "uid": uid, "status": "stun", "pos": boss.pos, "duration": 0.5}]:
		mg._on_event(ev)
	step.call(2.0)
	core.battle.damage(boss, 1e12, "blast", true, "test")
	step.call(3.0)
	assert_eq(core.state.boss_status("drill_giant"), "defeated")
	# region 3: divers with helmets, the tesla coil
	core.buy("node:r2_trophy_ram")
	for n: String in ["r3_road", "r3_tesla", "r3_wet_metal", "r3_tesla_limit"]:
		core.buy("node:" + n)
	core.buy("tower:tesla")
	for i in 4:
		core.battle.spawn_enemy_at("diver", Vector2(400.0 + 50.0 * i, 250.0 + 40.0 * i))
	step.call(10.0)
	assert_true(core.mods.is_region_unlocked(3), "region 3 open")
	assert_eq(mg.bv._bg_name, "battlefield_bg_r3")
	mg.shop.refresh()
	mg.hud.refresh()
	mg.free()
	Engine.time_scale = 1.0
	Game.running = false


## Conquest map: opens, buys a node by click (ink splat + stamp + road sparks), a region's fog burns when it
## opens, a choice opens the comparison instead of buying; a 250-node dummy map stays cheap per frame.
func test_conquest_map() -> void:
	var mg: MainGame = (load(SCENE) as PackedScene).instantiate() as MainGame
	Engine.get_main_loop().root.add_child(mg)
	var core: GameCore = mg.core
	var map: MapScreen = mg.map
	assert_true(map != null and not map.visible, "map built, closed")
	map.open()
	assert_true(map.visible, "map open")
	core.state.add_res("gears", 1e9)
	core.state.add_res("blueprints", 1e9)
	map._refresh(true)
	var horn: MapScreen.MNode = map.nodes["r0_horn"]
	assert_eq(horn.status, "available")
	assert_true(map.click(horn), "click buys an available node")
	assert_eq(core.level_of("node:r0_horn"), 1)
	assert_true(map._fx.size() >= 2, "splat + stamp (+ sparks)")
	assert_true(map._hint != null, "something to suggest")
	# the road to the wastes: region 1 opens, its fog burns away
	for n: String in ["r0_kettle", "r0_loopholes", "r0_rumors", "r1_dogs"]:
		core.buy("node:" + n)
	map._refresh(true)
	assert_true(map._fog_fade.has(1), "region 1 fog burns")
	for i in 40:
		map._process(0.05)
	assert_false((map._fog[1] as Sprite2D).visible, "fog gone")
	# a choice pair opens the comparison window, buys nothing
	var horn2: MapScreen.MNode = map.nodes["r1_dog_horn"]
	assert_false(map.click(horn2), "choice is not bought by a click")
	assert_true(mg.choice.visible, "comparison opened")
	mg.choice.close()
	map.close()
	# a full late-game map: 250 nodes over 8 regions
	var big := MapScreen.new()
	mg.add_child(big)
	big.setup(mg.kit, mg.shop, mg.choice, 250)
	assert_true(big.order.size() >= 240, "dummy nodes: %d" % big.order.size())
	big.open()
	var worst: float = 0.0
	for i in 20:
		big._process(0.05)
		worst = maxf(worst, big.draw_ms)
	assert_true(worst < 8.0, "map frame cost %.2f ms" % worst)
	mg.free()
	Engine.time_scale = 1.0
	Game.running = false
