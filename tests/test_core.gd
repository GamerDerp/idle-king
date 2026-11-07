extends "res://tests/test_case.gd"
## Core logic: prices, effects, moat, lens, towers, bosses, determinism, saves.

const Fixture := preload("res://tests/core_fixture.gd")
const FAR := Vector2(850, 150)   # away from the fixture's parked auto lens (600, 370)


func _give(c: GameCore, gears: float, bp: float) -> void:
	c.state.add_res("gears", gears)
	c.state.add_res("blueprints", bp)


func _run(c: GameCore, seconds: float, dt: float = 0.05) -> void:
	var t: float = 0.0
	while t < seconds - 1e-9:
		c.tick(dt)
		t += dt


# --- prices -------------------------------------------------------------------

func test_price_formula() -> void:
	assert_eq(GameCore.price_formula({"gears": 10}, 0.5, 0), {"gears": 10.0})
	assert_eq(GameCore.price_formula({"gears": 10}, 0.5, 2), {"gears": 23.0})  # 22.5 rounded up
	assert_almost(float(GameCore.price_formula({"gears": 10}, 0.5, 3, 1.0)["gears"]), 33.75)
	var p: Dictionary = GameCore.price_formula({"gears": 1e300}, 1.0, 100)
	assert_finite(float(p["gears"]), "huge price stays finite")


func test_price_grows_with_purchases() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 1000, 0)
	assert_eq(c.price("tower:gun"), {"gears": 10.0})
	assert_true(c.buy("tower:gun"))
	assert_eq(c.price("tower:gun"), {"gears": 15.0})
	assert_true(c.buy("tower:gun"))
	assert_eq(c.price("tower:gun"), {"gears": 23.0})
	assert_almost(c.state.res("gears"), 1000.0 - 25.0)
	assert_true(c.buy("tower:gun"))
	assert_false(c.can_buy("tower:gun"), "limit 3 reached")
	assert_false(c.buy("tower:gun"))


func test_cannot_buy_without_money_or_parent() -> void:
	var c: GameCore = Fixture.core()
	assert_false(c.buy("node:a"), "no blueprints")
	_give(c, 0, 100)
	assert_eq(c.node_status("b"), "locked")
	assert_false(c.buy("node:b"), "parent not bought")
	assert_true(c.buy("node:a"))
	assert_eq(c.node_status("b"), "available")
	assert_eq(c.node_status("armor"), "hidden", "region 1 closed")
	assert_true(c.buy("node:road"))
	assert_eq(c.node_status("armor"), "available")
	assert_true(c.buy("node:road") == false, "max level 1")
	assert_eq(c.node_status("road"), "maxed")


# --- effects --------------------------------------------------------------------

func test_effects_tower_damage_pct_and_mul() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 1000, 1000)
	assert_almost(float(c.mods.tower_stats["gun"]["dmg"]), 10.0)
	c.buy("node:a")
	assert_almost(float(c.mods.tower_stats["gun"]["dmg"]), 15.0)
	c.buy("node:a")
	assert_almost(float(c.mods.tower_stats["gun"]["dmg"]), 20.0, 1e-9, "pct stacks additively")
	c.buy("upg:gun_dmg")
	assert_almost(float(c.mods.tower_stats["gun"]["dmg"]), 25.0, 1e-9, "shop upgrade joins the same pool")
	c.buy("node:mulnode")
	c.buy("node:mulnode")
	assert_almost(float(c.mods.tower_stats["gun"]["dmg"]), 100.0, 1e-9, "stack=mul: x2 per level")
	assert_almost(float(c.mods.lens["dmg"]), 8.0, 1e-9, "global dmg applies to the lens")


func test_preview_mods_does_not_change_state() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 100)
	var after: Mods = c.preview_mods("node:a")
	assert_almost(float(after.tower_stats["gun"]["dmg"]), 15.0)
	assert_almost(float(c.mods.tower_stats["gun"]["dmg"]), 10.0)
	assert_eq(c.state.node_level("a"), 0)
	assert_almost(c.state.res("blueprints"), 100.0)


func test_effects_enemy_bait_and_limits() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 1000)
	c.buy("node:a")
	c.buy("node:b")
	var es: Dictionary = c.mods.enemy_stats["grunt"]
	assert_almost(float(es["hp"]), 150.0)
	assert_almost(float(es["loot"]["gears"]), 10.0)
	assert_almost(float(es["loot"]["blueprints"]), 1.0, 1e-9, "loot mult does not touch blueprints")
	assert_almost(float(es["pack"]), 3.0)
	assert_eq(int(c.mods.tower_stats["gun"]["limit"]), 5)


func test_effects_unlocks_and_lens() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 1000)
	assert_false(c.mods.unlocked_enemies.has("armored"))
	assert_false(c.mods.unlocked_towers.has("rivet"))
	c.buy("node:road")
	c.buy("node:armor")
	assert_true(c.mods.unlocked_enemies.has("armored"))
	assert_true(c.mods.unlocked_towers.has("rivet"))
	assert_false(c.mods.unlocked_enemies.has("guard"), "escorts never join packs")
	c.buy("node:lens")
	c.buy("node:lens")
	assert_almost(float(c.mods.lens["radius"]), 60.0)
	assert_almost(float(c.mods.lens["dmg"]), 4.0)
	assert_almost(float(c.mods.lens["interval"]), 0.25 / 3.0)
	assert_almost(float(c.mods.lens["auto_mult"]), 1.0)
	c.buy("node:moat")
	assert_almost(c.mods.moat_dps, 40.0)
	var evs: Array = c.drain_events()
	var unlocked: Array = evs.filter(func(e: Dictionary) -> bool: return e["type"] == "unlocked")
	assert_true(unlocked.size() >= 4, "unlocked events: %s" % str(unlocked))


func test_resistances() -> void:
	var c: GameCore = Fixture.core()
	var e: Battle.Enemy = c.battle.spawn_enemy_at("armored", FAR)
	c.battle.damage(e, 10.0, "impact", false, "test")
	assert_almost(e.hp, 95.0)
	c.battle.damage(e, 10.0, "steam", false, "test")
	assert_almost(e.hp, 80.0)


# --- moat ---------------------------------------------------------------------

func test_enemy_falls_into_moat_without_reward() -> void:
	var c: GameCore = Fixture.core()
	c.battle.spawn_enemy_at("grunt", Vector2(300, 150))
	c.drain_events()
	_run(c, 1.0)
	assert_eq(c.battle.alive_count(), 0)
	assert_eq(int(c.state.stats["falls"]), 1)
	assert_eq(int(c.state.stats["kills"]), 0)
	assert_almost(c.state.res("gears"), 0.0)
	var falls: Array = c.drain_events().filter(func(e: Dictionary) -> bool: return e["type"] == "enemy_fell_in_moat")
	assert_eq(falls.size(), 1)


func test_steam_curtain_damages_near_moat() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.buy("node:moat")
	var near: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(335, 150))
	var far: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(800, 150))
	_run(c, 0.5)
	assert_true(near.hp < 100.0 and near.hp > 70.0, "near hp %f" % near.hp)
	assert_almost(far.hp, 100.0)


# --- lens -----------------------------------------------------------------------

func test_lens_damages_only_inside_radius() -> void:
	var c: GameCore = Fixture.core()
	var inside: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(700, 300))
	var edge: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(700, 300 + 44))
	var outside: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(700, 400))
	inside.speed = 0.0
	edge.speed = 0.0
	outside.speed = 0.0
	# keep the cursor moving slightly so it never counts as idle
	for i in 20:
		c.set_cursor(Vector2(700, 300 + (i % 2) * 0.8), true)
		c.tick(0.05)
	assert_eq(c.battle.lens_mode, "manual")
	assert_almost(inside.hp, 100.0 - 4 * 2.0, 1e-9, "4 ticks x 2 dmg")
	assert_almost(edge.hp, 100.0 - 4 * 2.0, 1e-9, "radius + half enemy radius counts")
	assert_almost(outside.hp, 100.0)
	assert_true(float(c.state.stats["dmg_by_source"]["lens"]) > 0.0)


func test_lens_goes_auto_when_idle_or_away() -> void:
	var c: GameCore = Fixture.core()
	c.set_cursor(Vector2(700, 300), true)
	_run(c, 1.0)
	assert_eq(c.battle.lens_mode, "manual")
	_run(c, 1.5)
	assert_eq(c.battle.lens_mode, "auto", "cursor still for > 2 s")
	c.set_cursor(Vector2(701, 300), true)
	c.tick(0.05)
	assert_eq(c.battle.lens_mode, "manual", "moving again")
	c.set_cursor(Vector2(701, 300), false)
	c.tick(0.05)
	assert_eq(c.battle.lens_mode, "auto", "cursor left the field")
	# auto damage is scaled by auto_mult (0.5); fixture auto lens doesn't move (auto_speed 0)
	var e: Battle.Enemy = c.battle.spawn_enemy_at("grunt", c.battle.lens_pos)
	e.speed = 0.0
	c.battle._lens_acc = 0.0
	_run(c, 1.0)
	assert_almost(e.hp, 100.0 - 4 * 1.0)


func test_lens_seek_moves_to_densest_group() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.state.nodes["x"] = 0
	c.mods.flags["lens_seek"] = true
	c.mods.lens["seek"] = true
	for i in 5:
		var e: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(450 + i * 5, 500))
		e.speed = 0.0
	var lone: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(850, 150))
	lone.speed = 0.0
	_run(c, 3.0)
	assert_eq(c.battle.lens_mode, "seek")
	assert_true(c.battle.lens_pos.distance_to(Vector2(460, 500)) < 20.0, "lens at %s" % str(c.battle.lens_pos))


# --- towers ---------------------------------------------------------------------

func test_bullets_kill_and_give_loot() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 10, 0)
	c.buy("tower:gun")
	var e: Battle.Enemy = c.battle.spawn_enemy_at("grunt", FAR)
	e.speed = 0.0
	c.drain_events()
	_run(c, 10.5)
	assert_false(e.alive)
	assert_eq(int(c.state.stats["kills"]), 1)
	assert_almost(c.state.res("gears"), 5.0)
	assert_almost(c.state.res("blueprints"), 1.0)
	var types: Array = c.drain_events().map(func(ev: Dictionary) -> String: return str(ev["type"]))
	assert_has(types, "projectile_fired")
	assert_has(types, "enemy_hit")
	assert_has(types, "enemy_killed")


func test_rivet_pierces_line_and_scalds() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 100, 10)
	c.buy("node:road")
	c.buy("node:armor")
	c.buy("node:hot")
	c.buy("tower:rivet")
	var tw: Battle.Tower = c.battle.towers[0]
	var line: Array[Battle.Enemy] = []
	for i in 4:
		var e: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(500 + i * 60, tw.pos.y))
		e.speed = 0.0
		line.append(e)
	tw.cd = 0.0
	_run(c, 0.6)
	assert_almost(line[0].max_hp - line[0].hp, 10.0, 0.3, "first hit + some scald")
	assert_true(line[1].hp < 100.0 and line[2].hp < 100.0, "pierce 2 -> three enemies hit")
	assert_almost(line[3].hp, 100.0, 1e-9, "fourth not hit")
	assert_true(line[0].scald_t > 0.0, "scalded")
	_run(c, 0.4)  # tower fires again at 1.0 s; check scald dot ran meanwhile
	assert_true(float(c.state.stats["dmg_by_source"].get("scald", 0.0)) > 3.0)


func test_mortar_splash_hits_group() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 100, 10)
	c.buy("node:road")
	c.buy("node:armor")
	c.buy("tower:mortar")
	var grp: Array[Battle.Enemy] = []
	for p: Vector2 in [Vector2(700, 200), Vector2(715, 210), Vector2(705, 225)]:
		var e: Battle.Enemy = c.battle.spawn_enemy_at("grunt", p)
		e.speed = 0.0
		grp.append(e)
	var lone: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(850, 560))
	lone.speed = 0.0
	c.battle.towers[0].cd = 0.0
	_run(c, 2.2)
	for e in grp:
		assert_almost(e.hp, 70.0, 1e-9, "splash hit")
	assert_almost(lone.hp, 100.0)


func test_tower_slots_distinct() -> void:
	var c: GameCore = GameCore.create(1)
	var seen: Dictionary = {}
	for t: String in c.data.towers:
		for i in 14:
			var p: Vector2 = c.battle.tower_slot(t, i)
			assert_false(seen.has(p), "slot %s#%d duplicates" % [t, i])
			seen[p] = true
			assert_true(p.x >= 90.0 and p.x <= 215.0 and p.y >= 130.0 and p.y <= 620.0)


# --- bosses --------------------------------------------------------------------

func test_boss_retreats_and_can_be_called_again() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.buy("node:road")
	assert_false(c.call_boss("chief"), "cannot call before the node")
	c.buy("node:boss")
	assert_eq(c.state.boss_status("chief"), "active")
	assert_eq(c.active_boss(), "chief")
	c.tick(0.01)
	assert_eq(c.battle.alive_count(), 3, "boss + 2 escorts")
	_run(c, 4.0)  # boss speed 200 -> reaches the moat
	assert_eq(c.state.boss_status("chief"), "retreated")
	assert_eq(c.active_boss(), "")
	assert_almost(c.state.res("blueprints"), 10.0 - 2.0, 1e-9, "no reward on retreat")
	assert_true(c.can_call_boss("chief"))
	assert_true(c.call_boss("chief"))
	assert_eq(int(c.state.bosses["chief"]["attempts"]), 2)
	assert_false(c.call_boss("chief"), "already on the field")
	assert_eq(c.node_status("beyond"), "hidden")
	var boss: Battle.Enemy = c.battle.boss_enemy
	c.battle.damage(boss, 1e9, "impact", false, "test")
	c.tick(0.05)
	assert_eq(c.state.boss_status("chief"), "defeated")
	assert_almost(c.state.res("blueprints"), 108.0, 1e-9, "reward")
	assert_eq(c.node_status("beyond"), "available", "region 2 unlocked by on_defeat")
	assert_false(c.call_boss("chief"), "defeated bosses stay defeated")


func test_boss_pauses_packs() -> void:
	var cfg: Dictionary = Fixture.cfg()
	cfg["waves"]["pack_interval"] = 1.0
	cfg["waves"]["first_pack_at"] = 0.1
	var c := GameCore.create(1, GameData.new(cfg))
	_run(c, 0.5)
	var packs: int = c.battle.packs_spawned
	assert_eq(packs, 1)
	_give(c, 0, 10)
	c.buy("node:road")
	c.buy("node:boss")
	_run(c, 1.0)
	assert_eq(c.battle.packs_spawned, packs, "no packs during the boss")


# --- determinism, saves, long runs -----------------------------------------------

func _bot_run(seed_value: int, seconds: float, dt: float) -> GameCore:
	var c: GameCore = GameCore.create(seed_value)
	c.emit_events = false
	var bot := SimBot.new(c, true)
	var t: float = 0.0
	while t < seconds - 1e-9:
		bot.step(dt)
		c.tick(dt)
		t += dt
	return c


func test_determinism_same_seed_same_result() -> void:
	var a: GameCore = _bot_run(42, 150.0, 0.05)
	var b: GameCore = _bot_run(42, 150.0, 0.05)
	assert_eq(JSON.stringify(a.save_state()), JSON.stringify(b.save_state()))
	assert_eq(a.battle.enemies.size(), b.battle.enemies.size())
	var c: GameCore = _bot_run(43, 150.0, 0.05)
	assert_ne(JSON.stringify(a.save_state()), JSON.stringify(c.save_state()), "other seed differs")


func test_save_roundtrip_json() -> void:
	var a: GameCore = _bot_run(5, 90.0, 0.1)
	var d: Dictionary = a.save_state()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var b := GameCore.new(a.data)
	b.load_state(parsed)
	assert_eq(JSON.stringify(b.save_state()), JSON.stringify(d))
	assert_eq(b.mods.unlocked_enemies, a.mods.unlocked_enemies)
	assert_almost(float(b.mods.tower_stats["shooter"]["dmg"]), float(a.mods.tower_stats["shooter"]["dmg"]))
	assert_eq(b.battle.towers.size(), a.battle.towers.size())


func test_long_run_no_nan() -> void:
	var c: GameCore = _bot_run(9, 25.0 * 60.0, 0.1)
	for r: String in c.state.resources:
		assert_finite(c.state.res(r), r)
	for e: Battle.Enemy in c.battle.enemies:
		assert_finite(e.hp)
		assert_finite(e.pos.x)
	for k: String in c.state.stats["dmg_by_source"]:
		assert_finite(float(c.state.stats["dmg_by_source"][k]), k)
	assert_true(c.state.stats["kills"] > 1000, "the game progressed")
	c.tick(INF)
	c.tick(NAN)
	c.tick(-1.0)
	assert_finite(c.state.time)


func test_dt_sizes_are_close() -> void:
	# fast simulation (dt 0.1) should track the real-time one (1/60) closely
	var a: GameCore = _bot_run(3, 240.0, 1.0 / 60.0)
	var b: GameCore = _bot_run(3, 240.0, 0.1)
	var ka: float = float(a.state.stats["kills"])
	var kb: float = float(b.state.stats["kills"])
	assert_true(absf(ka - kb) / ka < 0.1, "kills %d vs %d" % [ka, kb])


# --- content ------------------------------------------------------------------

func test_real_config_valid_and_translated() -> void:
	var d := GameData.from_dir()
	assert_eq(d.errors, [] as Array[String])
	assert_true(d.nodes.size() >= 25 and d.nodes.size() <= 40, "%d nodes" % d.nodes.size())
	TranslationServer.set_locale("ru")
	var keys: Array[String] = []
	for id: String in d.nodes:
		keys.append(GameData.node_name_key(id))
		keys.append(GameData.node_desc_key(id))
	for t: String in d.towers:
		keys.append(str(d.towers[t]["name"]))
		keys.append(str(d.towers[t]["desc"]))
	for u: String in d.upgrades:
		keys.append(str(d.upgrades[u]["name"]))
	for e: String in d.enemies:
		keys.append(str(d.enemies[e]["name"]))
	for r: String in d.resource_ids:
		keys.append("RES_" + r.to_upper())
	for k in keys:
		assert_ne(String(TranslationServer.translate(k)), k, "missing ru text for " + k)
	var en := TranslationServer.get_translation_object("en")
	for k in keys:
		assert_ne(String(en.get_message(k)), "", "missing en text for " + k)
