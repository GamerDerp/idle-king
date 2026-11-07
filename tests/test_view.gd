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
	var groups: Dictionary = {"unlock_tower": data.towers, "unlock_enemy": data.enemies, "unlock_ability": data.abilities}
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
			assert_false(r.contains("DIFF_") or r.contains("STATUS_") or r.contains("BEH_"), "%s: untranslated row %s" % [pair[0], r])
		if ty.ends_with("_status"):
			var has_status: bool = false
			for r: String in rows:
				has_status = has_status or (r.contains("→") and r.contains("%"))
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
