extends "res://tests/test_case.gd"
## Region 2 «Угольные копи» mechanics: moles (burrow/emerge, dig), carts (immunities),
## golems (split), frontal armour (boss), diver shield, stun, producers, geysers,
## drill ram, zone statuses, chain / ricochet towers, honest novelty, next_milestone.

const Fixture := preload("res://tests/core_fixture.gd")


func _give(c: GameCore, gears: float, bp: float) -> void:
	c.state.add_res("gears", gears)
	c.state.add_res("blueprints", bp)


func _run(c: GameCore, seconds: float, dt: float = 0.05) -> void:
	var t: float = 0.0
	while t < seconds - 1e-9:
		c.tick(dt)
		t += dt


func _events(c: GameCore, type: String) -> Array:
	return c.drain_events().filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _still(e: Battle.Enemy) -> Battle.Enemy:
	e.speed = 0.0
	return e


# --- moles ------------------------------------------------------------------------

func test_mole_emerge_event_and_under_speed() -> void:
	var c: GameCore = Fixture.core()
	var m: Battle.Enemy = c.battle.spawn_enemy_at("mole", Vector2(850, 200))
	m.under_speed = 2.0
	m.underground = true
	assert_almost(m.cur_speed(), 60.0, 1e-6, "faster underground")
	m.burrow_t = 0.1
	c.drain_events()
	c.tick(0.15)
	assert_false(m.underground)
	var em: Array = c.drain_events().filter(func(e: Dictionary) -> bool: return e["type"] == "enemy_emerge")
	assert_eq(em.size(), 1)
	assert_false(bool(em[0]["forced"]))


func test_lens_dig_forces_moles_up() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	var m: Battle.Enemy = _still(c.battle.spawn_enemy_at("mole", Vector2(600, 370)))
	m.underground = true
	m.burrow_t = 99.0
	c.set_cursor(Vector2(600, 370), true)
	_run(c, 0.5)
	assert_true(m.underground, "without the node the lens cannot reach it")
	assert_almost(m.hp, 100.0)
	c.buy("node:lens_dig")
	assert_has(c.mods.behaviours(), "lens_dig")
	c.drain_events()
	c.set_cursor(Vector2(601, 370), true)
	_run(c, 0.5)
	assert_false(m.underground, "dug out")
	assert_true(m.hp < 100.0, "and burnt")
	var em: Array = _events(c, "enemy_emerge")
	assert_true(em.size() >= 1 and bool(em[0]["forced"]))


# --- carts: immunities ------------------------------------------------------------

func test_cart_ignores_slow_stun_knockback() -> void:
	var c: GameCore = Fixture.core()
	var cart: Battle.Enemy = c.battle.spawn_enemy_at("cart", Vector2(700, 300))
	var grunt: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(700, 400))
	for e in [cart, grunt]:
		c.battle._apply_status(e, "slow", 0.5, 2.0, 0.0)
		c.battle._apply_status(e, "stun", 0.0, 2.0, 0.0)
	assert_almost(cart.cur_speed(), 30.0, 1e-6, "cart keeps its speed")
	assert_almost(grunt.cur_speed(), 0.0, 1e-6, "stunned grunt stands still")
	_give(c, 1000, 10)
	c.buy("node:kb_big")
	c.buy("tower:gun")
	var x0: float = cart.pos.x
	var p := Battle.Projectile.new()
	p.tower = "gun"
	p.kind = "bullet"
	p.dmg = 1.0
	c.battle._tower_hit(cart, p)
	assert_almost(cart.pos.x, x0, 1e-6, "not knocked back")
	var gx: float = grunt.pos.x
	c.battle._tower_hit(grunt, p)
	assert_true(grunt.pos.x > gx + 20.0, "grunt is knocked back")


func test_stun_freezes_and_boss_is_resistant() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 1000, 10)
	c.buy("node:stun")
	assert_has(c.mods.behaviours(), "status:gun:stun")
	var e: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(700, 300))
	c.battle._apply_status(e, "stun", 0.0, 1.0, 0.0)
	var x: float = e.pos.x
	_run(c, 0.5)
	assert_almost(e.pos.x, x, 1e-6, "stunned: does not move")
	_run(c, 0.6)
	assert_true(e.pos.x < x, "walks again")
	c.buy("node:road")
	c.buy("node:boss")
	var chief: Battle.Enemy = c.battle.boss_enemy
	c.battle._apply_status(chief, "stun", 0.0, 1.0, 0.0)
	assert_almost(chief.stun_t, 0.25, 1e-6, "bosses: duration x combat.stun_boss")


# --- golems: split --------------------------------------------------------------------

func test_golem_splits_into_embers() -> void:
	var c: GameCore = Fixture.core()
	var g: Battle.Enemy = c.battle.spawn_enemy_at("golem", Vector2(700, 300))
	c.drain_events()
	c.battle.damage(g, 1e6, "blast", false, "test")
	var embers: Array = c.battle.enemies.filter(func(e: Battle.Enemy) -> bool: return e.type == "ember" and e.alive)
	assert_eq(embers.size(), 2)
	assert_eq(embers[0].parent_uid, g.uid)
	var ev: Array = _events(c, "enemy_split")
	assert_eq(ev.size(), 1)
	assert_eq((ev[0]["children"] as Array).size(), 2)
	assert_eq(str(ev[0]["child_type"]), "ember")
	assert_eq(int(c.state.stats["kills"]), 1)


# --- frontal armour, armour pierce, steam rust --------------------------------------------

func test_front_armor_blocks_direct_fire_only() -> void:
	var c: GameCore = Fixture.core()
	var b: Battle.Enemy = c.battle.spawn_enemy_at("armored_boss", Vector2(700, 300))
	assert_almost(c.battle.damage(b, 100.0, "impact", false, "t", false, true), 30.0, 1e-6, "direct x0.3")
	assert_almost(c.battle.damage(b, 100.0, "blast", false, "t", false, false), 100.0, 1e-6, "explosions in full")
	assert_almost(c.battle.damage(b, 100.0, "impact", false, "t", false, true, 0.5), 65.0, 1e-6, "pierce halves the block")
	c.drain_events()
	c.battle.damage(b, 10.0, "impact", false, "t", false, true)
	var hit: Array = _events(c, "enemy_hit")
	assert_true(bool(hit[0]["armored"]))
	_give(c, 0, 10)
	c.buy("node:shred")
	b.scald_t = 1.0
	assert_almost(c.battle.damage(b, 100.0, "impact", false, "t", false, true), 65.0, 1e-6, "scalded: block halved")


func test_shells_ignore_front_armor_but_bullets_do_not() -> void:
	var c: GameCore = Fixture.core()
	var b: Battle.Enemy = c.battle.spawn_enemy_at("armored_boss", Vector2(700, 300))
	var p := Battle.Projectile.new()
	p.tower = "gun"
	p.kind = "bullet"
	p.dmg = 100.0
	c.battle._tower_hit(b, p)
	assert_almost(b.hp, 1000.0 - 30.0, 1e-6)
	_give(c, 1000, 10)
	c.buy("node:ap")
	assert_has(c.mods.behaviours(), "armor_pierce:gun")
	c.battle._tower_hit(b, p)
	assert_almost(b.hp, 1000.0 - 30.0 - 65.0, 1e-6)
	p.kind = "shell"
	c.battle._tower_hit(b, p)
	assert_almost(b.hp, 1000.0 - 30.0 - 65.0 - 100.0, 1e-6)


func test_boss_charges() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.buy("node:drill")
	var b: Battle.Enemy = c.battle.boss_enemy
	assert_eq(b.type, "armored_boss")
	c.drain_events()
	_run(c, 1.1)
	assert_true(b.charging)
	assert_almost(b.cur_speed(), 30.0, 1e-6, "dash x3")
	assert_eq(_events(c, "enemy_charge").size(), 1)


func test_boss_retreat_reports_hp_left() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.buy("node:drill")
	var b: Battle.Enemy = c.battle.boss_enemy
	c.battle.damage(b, 400.0, "blast", false, "t")
	b.pos.x = c.battle.moat_x + 1.0
	c.drain_events()
	c.tick(0.5)
	assert_eq(c.state.boss_status("drill"), "retreated")
	assert_almost(c.battle.boss_last_hp, 0.6, 1e-6)
	var ev: Array = _events(c, "boss_retreated")
	assert_almost(float(ev[0]["hp_left"]), 0.6, 1e-6)
	assert_true(c.call_boss("drill"), "«вызвать снова»")
	assert_eq(int(c.state.bosses["drill"]["attempts"]), 2)


# --- diver shield, wet metal ------------------------------------------------------------

func test_diver_shield_only_breakers_remove_it() -> void:
	var c: GameCore = Fixture.core()
	var d: Battle.Enemy = c.battle.spawn_enemy_at("diver", Vector2(700, 300))
	assert_almost(d.shield_hp, 50.0)
	assert_almost(c.battle.damage(d, 50.0, "impact", false, "t"), 10.0, 1e-6, "impact cut by the helmet")
	assert_almost(d.shield_hp, 50.0, 1e-6, "impact does not wear the helmet")
	c.drain_events()
	c.battle.damage(d, 60.0, "steam", false, "t")
	assert_almost(d.shield_hp, 0.0)
	assert_almost(d.hp, 100.0 - 10.0 - 10.0, 1e-6, "overflow goes to health")
	assert_eq(_events(c, "enemy_shield_broken").size(), 1)
	assert_almost(c.battle.damage(d, 10.0, "impact", false, "t"), 10.0, 1e-6, "no helmet: full damage")


func test_wet_metal_doubles_spark_on_scalded() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.buy("node:wet")
	var e: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(700, 300))
	assert_almost(c.battle.damage(e, 10.0, "spark", false, "t"), 10.0)
	e.scald_t = 1.0
	assert_almost(c.battle.damage(e, 10.0, "spark", false, "t"), 20.0)


# --- producers ------------------------------------------------------------------------

func test_producer_cycle_output_event_and_levels() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	assert_almost(c.producer_progress("mine"), 0.0)
	c.buy("node:mine")
	assert_has(c.mods.behaviours(), "producer:mine")
	c.drain_events()
	_run(c, 1.0)
	assert_almost(c.producer_progress("mine"), 0.5, 0.03)
	_run(c, 1.05)
	var out: Array = _events(c, "producer_output")
	assert_eq(out.size(), 1)
	assert_almost(float(out[0]["amount"]["coal"]), 3.0)
	assert_almost(c.state.res("coal"), 3.0)
	assert_eq(int(c.mods.producers["mine"]["level"]), 1)
	assert_true(c.novelty_of("node:mine_up").is_empty(), "more output is numbers only")
	c.buy("node:mine_up")
	assert_eq(int(c.mods.producers["mine"]["level"]), 2)
	assert_almost(float(c.mods.producers["mine"]["output"]["coal"]), 4.5)
	assert_has(c.novelty_of("node:mine_bp"), "producer_out:mine:blueprints", "a new output resource is new")


# --- geysers, drill ram, kettle puddle --------------------------------------------------

func test_geyser_event_and_half_loot() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.buy("node:geyser")
	var e: Battle.Enemy = _still(c.battle.spawn_enemy_at("grunt", Vector2(c.battle.moat_x + 60.0, 300)))
	var g0: float = c.state.res("gears")
	c.drain_events()
	_run(c, 1.05)
	assert_false(e.alive)
	var gs: Array = c.drain_events()
	assert_eq(gs.filter(func(x: Dictionary) -> bool: return x["type"] == "geyser").size(), 1)
	assert_eq(gs.filter(func(x: Dictionary) -> bool: return x["type"] == "ability_fired").size(), 0)
	assert_almost(c.state.res("gears") - g0, 2.5, 1e-6, "geyser kills give kill_loot_mult (50%) of the loot")


func test_drill_ram_hits_a_lane() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.buy("node:ram")
	var a: Battle.Enemy = _still(c.battle.spawn_enemy_at("grunt", Vector2(400, 300)))
	var b: Battle.Enemy = _still(c.battle.spawn_enemy_at("grunt", Vector2(800, 305)))
	var off: Battle.Enemy = _still(c.battle.spawn_enemy_at("grunt", Vector2(600, 500)))
	c.drain_events()
	_run(c, 1.05)
	assert_almost(a.hp, 50.0)
	assert_almost(b.hp, 50.0)
	assert_almost(off.hp, 100.0)
	var ev: Array = _events(c, "drill_ram")
	assert_eq(ev.size(), 1)
	assert_eq(str(ev[0]["shape"]), "line")


func test_kettle_puddle_and_boiler_tar_zone() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 1000, 20)
	c.buy("node:kettle")
	c.buy("node:kettle_puddle")
	assert_has(c.mods.behaviours(), "ability_puddle:kettle")
	_still(c.battle.spawn_enemy_at("grunt", Vector2(400, 200))).max_hp = 1e6
	c.drain_events()
	_run(c, 2.1)
	assert_eq(c.battle.zones.size(), 1)
	assert_eq(_events(c, "zone_created").size(), 1)
	c.buy("node:r2t")
	c.buy("node:tar")
	assert_has(c.mods.behaviours(), "zone_status:boiler:slow")
	c.battle.zones.clear()
	var p := Battle.Projectile.new()
	p.tower = "boiler"
	p.kind = "shell"
	p.start = Vector2(200, 300)
	p.dest = Vector2(600, 300)
	p.flight = 0.01
	p.t = 1.0
	p.splash = 10.0
	c.battle._move_shell(p, 0.05)
	var e: Battle.Enemy = _still(c.battle.spawn_enemy_at("grunt", Vector2(600, 300)))
	c.tick(0.05)
	assert_true(e.slow_t > 0.0, "tar puddle slows")


# --- chain & ricochet -----------------------------------------------------------------------

func test_tesla_chain_jumps() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 1000, 10)
	c.buy("node:r2t")
	c.buy("tower:tesla")
	var es: Array = []
	for i in 4:
		es.append(_still(c.battle.spawn_enemy_at("grunt", Vector2(600 + i * 60, 300))))
	for tw in c.battle.towers:
		tw.cd = 0.0 if tw.type == "tesla" else 99.0
	c.drain_events()
	c.tick(0.05)
	var ch: Array = _events(c, "chain_fired")
	assert_eq(ch.size(), 1)
	assert_eq((ch[0]["points"] as Array).size(), 4, "tower + target + 2 jumps")
	assert_almost(es[0].hp, 90.0)
	assert_almost(es[1].hp, 95.0, 1e-6, "decay 0.5")
	assert_almost(es[2].hp, 97.5)
	assert_almost(es[3].hp, 100.0, 1e-6, "chain = 2 jumps")


func test_ricochet_bounces_with_gain() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 1000, 10)
	c.buy("node:r2t")
	c.buy("tower:rico")
	var a: Battle.Enemy = _still(c.battle.spawn_enemy_at("grunt", Vector2(500, 300)))
	var b: Battle.Enemy = _still(c.battle.spawn_enemy_at("grunt", Vector2(600, 300)))
	for tw in c.battle.towers:
		tw.cd = 0.0 if tw.type == "rico" else 99.0
	c.drain_events()
	_run(c, 0.3)
	assert_almost(a.hp, 90.0)
	assert_almost(b.hp, 85.0, 1e-6, "bounce +50%")
	assert_true(_events(c, "ricochet").size() >= 1)


# --- honest novelty, next milestone -----------------------------------------------------------

func test_small_knockback_is_not_novel() -> void:
	var c: GameCore = Fixture.core()
	assert_true(c.novelty_of("node:kb_small").is_empty(), "10 px < knockback_novel_min")
	assert_has(c.novelty_of("node:kb_big"), "knockback:gun")
	assert_false(c.novelty_of("node:road").has("region:1"), "a region alone is not new behaviour")
	assert_has(c.changes_of("node:road"), "region:1")
	assert_eq(c.purchase_category("node:road"), "numeric")


func test_next_milestone() -> void:
	var c: GameCore = Fixture.core()
	var ms: Dictionary = c.next_milestone("gun_dmg")
	assert_eq(int(ms["level"]), 2)
	assert_eq(int(ms["levels_left"]), 2)
	assert_eq(str(ms["name"]), "MS")
	assert_has(ms["novelty"], "multishot:gun")
	_give(c, 1000, 0)
	c.buy("upg:gun_dmg")
	c.buy("upg:gun_dmg")
	assert_true(c.next_milestone("gun_dmg").is_empty(), "no more milestones")
	assert_true(c.next_milestone("nope").is_empty())


func test_real_config_r2_content() -> void:
	var d := GameData.from_dir()
	assert_eq(d.errors.size(), 0, str(d.errors))
	for e in ["mole_miner", "coal_cart", "coal_golem", "diver"]:
		assert_has(d.enemies, e)
	assert_true(float(d.enemies["drill_giant"]["front_armor"]) > 0.5)
	assert_has(d.producers, "coal_mine")
	for n in ["r2_steam_jet", "r2_boiler", "r2_geysers", "r2_boss", "r3_road", "r3_tesla", "r3_ricochet"]:
		assert_has(d.nodes, n)
	# both rewards of the R2 boss are qualitative
	var c := GameCore.create(-1, d)
	c.state.bosses["wasteland_chief"] = {"status": "defeated", "attempts": 1}
	c.state.bosses["drill_giant"] = {"status": "defeated", "attempts": 1}
	c.state.nodes["r1_boss"] = 1
	c.state.nodes["r2_road"] = 1
	c.state.nodes["r2_carts"] = 1
	c.state.nodes["r2_golems"] = 1
	c.state.nodes["r2_boss"] = 1
	c.recompute()
	assert_false(c.novelty_of("node:r2_trophy_ram").is_empty())
	assert_false(c.novelty_of("node:r2_trophy_lens").is_empty())


func test_unused_node_texts_removed() -> void:
	var d := GameData.from_dir()
	var f := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	var stale: Array = []
	while not f.eof_reached():
		var k: String = f.get_line().get_slice(",", 0)
		if k.begins_with("NODE_"):
			var id: String = k.substr(5).trim_suffix("_DESC").to_lower()
			if not d.nodes.has(id):
				stale.append(k)
	assert_eq(stale, [], "i18n keys of nodes that no longer exist")
