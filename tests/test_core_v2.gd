extends "res://tests/test_case.gd"
## Core iteration 2: choices (excludes), milestones and tiers, novelty, run/meta
## split, aggregated damage-over-time events, goal bar, new behaviours.

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


func _open_region1(c: GameCore) -> void:
	_give(c, 1e6, 100)
	c.buy("node:road")
	c.buy("node:armor")


# --- choices --------------------------------------------------------------------

func test_excludes_make_a_choice() -> void:
	var c: GameCore = Fixture.core()
	_open_region1(c)
	assert_has(c.offer_ids(), "node:hot")
	assert_has(c.offer_ids(), "node:boom")
	c.drain_events()
	assert_true(c.buy("node:hot"))
	assert_eq(c.node_status("boom"), "excluded")
	assert_false(c.offer_ids().has("node:boom"))
	assert_false(c.buy("node:boom"))
	var ev: Array = _events(c, "choice_made")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["excluded"], ["boom"])


func test_excludes_must_be_mutual() -> void:
	var cfg: Dictionary = Fixture.cfg()
	cfg["map"]["nodes"][9].erase("excludes")   # "boom" no longer excludes "hot"
	expected_errors = 1
	var d := GameData.new(cfg)
	assert_eq(d.errors.size(), 1, str(d.errors))


func test_missing_required_field_is_an_error() -> void:
	var cfg: Dictionary = Fixture.cfg()
	cfg["towers"]["towers"]["gun"].erase("range_max")
	cfg["enemies"]["enemies"]["grunt"].erase("speed")
	expected_errors = 2
	var d := GameData.new(cfg)
	assert_eq(d.errors.size(), 2, str(d.errors))


func test_boss_reward_requires_victory() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.buy("node:road")
	c.buy("node:boss")
	assert_eq(c.node_status("trophy"), "hidden")
	c.battle.damage(c.battle.boss_enemy, 1e9, "impact", false, "test")
	c.tick(0.05)
	assert_eq(c.node_status("trophy"), "available")
	assert_true(c.buy("node:trophy"), "free reward")
	assert_eq(c.battle.lenses.size(), 2, "second automatic lens")


# --- milestones, tiers, novelty --------------------------------------------------

func test_milestone_changes_behaviour_and_tier() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 1000, 0)
	assert_eq(c.tower_tier("gun"), 1)
	assert_true(c.novelty_of("upg:gun_dmg").is_empty(), "level 1 is just numbers")
	assert_eq(c.purchase_category("upg:gun_dmg"), "numeric")
	c.buy("upg:gun_dmg")
	assert_has(c.novelty_of("upg:gun_dmg"), "multishot:gun", "level 2 = milestone")
	assert_false(c.novelty_of("upg:gun_dmg").has("tier:gun:2"), "a new look alone is not new behaviour")
	assert_has(c.changes_of("upg:gun_dmg"), "tier:gun:2", "but it is listed among the changes")
	c.drain_events()
	c.buy("upg:gun_dmg")
	assert_eq(c.tower_tier("gun"), 2)
	assert_eq(int(c.mods.tower_stats["gun"]["multishot"]), 2)
	assert_eq(_events(c, "tier_up").size(), 1)
	c.buy("upg:gun_dmg")
	assert_eq(c.tower_tier("gun"), 2, "milestone applies once")
	assert_eq(int(c.mods.tower_stats["gun"]["multishot"]), 2)


func test_milestone_events() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 1000, 0)
	c.buy("upg:gun_dmg")
	c.drain_events()
	c.buy("upg:gun_dmg")
	var evs: Array = c.drain_events()
	var types: Array = evs.map(func(e: Dictionary) -> String: return str(e["type"]))
	assert_has(types, "milestone")
	assert_has(types, "tier_up")


func test_novelty_is_honest_for_numeric_adds() -> void:
	var c: GameCore = Fixture.core()
	_open_region1(c)
	# rivets already pierce: more pierce would be numeric; first cluster is new
	assert_has(c.novelty_of("node:boom"), "cluster:mortar")
	assert_true(c.novelty_of("node:a").is_empty(), "+% damage is numeric")
	assert_eq(c.purchase_category("tower:gun"), "tower", "the unlock was the novelty, copies are towers")
	assert_has(c.novelty_of("node:moat"), "moat_curtain")


func test_multishot_hits_two_targets() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 1000, 0)
	c.buy("tower:gun")
	c.buy("upg:gun_dmg")
	c.buy("upg:gun_dmg")
	var a: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(700, 200))
	var b: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(720, 500))
	a.speed = 0.0
	b.speed = 0.0
	c.battle.towers[0].cd = 0.0
	c.tick(0.05)
	c.tick(0.05)
	assert_true(a.hp < 100.0 and b.hp < 100.0, "both hit by one volley: %f %f" % [a.hp, b.hp])


# --- run / meta -----------------------------------------------------------------

func test_run_meta_split_survives_prestige() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 100, 10)
	c.buy("node:road")
	c.buy("node:boss")
	c.battle.damage(c.battle.boss_enemy, 1e9, "impact", false, "test")
	c.tick(0.05)
	assert_almost(c.state.res("seals"), 1.0)
	assert_eq(int(c.state.meta["stats"]["kills"]), 1)
	assert_eq(int(c.state.meta["high"]["max_region"]), 2)
	assert_true(c.state.meta["high"]["boss_best"].has("chief"))
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.save_state()))
	assert_has(d, "run")
	assert_has(d, "meta")
	c.new_run()
	assert_eq(c.state.node_level("road"), 0, "run reset")
	assert_eq(c.state.boss_status("chief"), "none")
	assert_almost(c.state.res("gears"), 0.0)
	assert_almost(c.state.res("seals"), 1.0, 1e-9, "печати survive")
	assert_eq(int(c.state.meta["stats"]["kills"]), 1, "lifetime stats survive")
	assert_eq(int(c.state.meta["stats"]["runs"]), 2)
	assert_eq(int(c.state.stats["kills"]), 0)
	var c2 := GameCore.new(c.data)
	c2.load_state(d)
	assert_almost(c2.state.res("seals"), 1.0)
	assert_eq(c2.state.node_level("road"), 1)


# --- events for the juicy view -----------------------------------------------------

func test_dot_events_are_aggregated() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.buy("node:moat")
	var e: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(320, 150))
	e.speed = 0.0
	e.hp = 1e6
	e.max_hp = 1e6
	c.drain_events()
	_run(c, 1.0, 1.0 / 60.0)
	var dots: Array = _events(c, "enemy_dot")
	assert_true(dots.size() >= 3 and dots.size() <= 5, "~4 per second, got %d" % dots.size())
	var sum: float = 0.0
	for d: Dictionary in dots:
		sum += float(d["amount"])
		assert_eq(d["source"], "moat")
	assert_almost(sum, float(dots[-1]["total"]), 1e-6, "total = cumulative")
	assert_true(sum > 30.0 and sum <= 40.0 + 1e-6, "sum %f" % sum)


func test_lens_tick_reports_damage_and_hits() -> void:
	var c: GameCore = Fixture.core()
	for i in 3:
		var e: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(700 + i * 5, 300))
		e.speed = 0.0
	c.drain_events()
	for i in 6:
		c.set_cursor(Vector2(705, 300 + (i % 2) * 0.8), true)
		c.tick(0.05)
	var ticks: Array = _events(c, "lens_tick")
	assert_eq(ticks.size(), 1)
	assert_eq(int(ticks[0]["hits"]), 3)
	assert_almost(float(ticks[0]["damage"]), 6.0)


func test_next_goal() -> void:
	var c: GameCore = Fixture.core()
	var g: Dictionary = c.next_goal()
	assert_eq(g["text_key"], "GOAL_NODE")
	assert_true(float(g["progress"]) >= 0.0 and float(g["progress"]) <= 1.0)
	_give(c, 0, 10)
	c.buy("node:road")
	c.buy("node:boss")
	g = c.next_goal()
	assert_eq(g["text_key"], "GOAL_BOSS_FIGHT")
	_run(c, 4.0)
	assert_eq(c.next_goal()["text_key"], "GOAL_BOSS_RETRY")


# --- new behaviours --------------------------------------------------------------

func test_burrowed_enemy_is_untouchable() -> void:
	var c: GameCore = Fixture.core()
	var m: Battle.Enemy = c.battle.spawn_enemy_at("mole", Vector2(800, 200))
	m.speed = 0.0
	m.underground = true
	m.burrow_t = 5.0
	assert_almost(c.battle.damage(m, 50.0, "impact", false, "test"), 0.0)
	assert_almost(m.hp, 100.0)
	m.underground = false
	assert_almost(c.battle.damage(m, 50.0, "impact", false, "test"), 50.0)


func test_burrow_cycles() -> void:
	var c: GameCore = Fixture.core()
	var m: Battle.Enemy = c.battle.spawn_enemy_at("mole", Vector2(850, 200))
	m.burrow_t = 0.5
	var seen_under: bool = false
	var seen_over: bool = false
	for i in 60:
		c.tick(0.05)
		seen_under = seen_under or m.underground
		seen_over = seen_over or not m.underground
	assert_true(seen_under and seen_over)


func test_steam_cone_hits_inside_and_slows() -> void:
	var c: GameCore = Fixture.core()
	_open_region1(c)
	c.buy("tower:jet")
	var tw: Battle.Tower = c.battle.towers[0]
	var inside: Battle.Enemy = c.battle.spawn_enemy_at("grunt", tw.pos + Vector2(200, 0))
	var inside2: Battle.Enemy = c.battle.spawn_enemy_at("grunt", tw.pos + Vector2(260, 20))
	var outside: Battle.Enemy = c.battle.spawn_enemy_at("grunt", tw.pos + Vector2(200, 200))
	for e in [inside, inside2, outside]:
		e.speed = 0.0
	tw.cd = 0.0
	c.tick(0.05)
	assert_true(inside.hp < 100.0 and inside2.hp < 100.0)
	assert_almost(outside.hp, 100.0)
	assert_true(inside.slow_t > 0.0 and inside.slow_f > 0.4)


func test_cluster_fragments() -> void:
	var c: GameCore = Fixture.core()
	_open_region1(c)
	c.buy("node:boom")
	c.buy("tower:mortar")
	var e: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(700, 300))
	e.speed = 0.0
	e.hp = 1e6
	e.max_hp = 1e6
	c.battle.towers[0].cd = 0.0
	c.drain_events()
	_run(c, 2.0)
	var ex: Array = _events(c, "shell_exploded")
	var frags: int = ex.filter(func(x: Dictionary) -> bool: return bool(x["fragment"])).size()
	assert_eq(frags, 3)


func test_kettle_splashes_front_enemy() -> void:
	var c: GameCore = Fixture.core()
	_give(c, 0, 10)
	c.buy("node:kettle")
	var front: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(400, 200))
	var far: Battle.Enemy = c.battle.spawn_enemy_at("grunt", Vector2(850, 200))
	front.speed = 0.0
	far.speed = 0.0
	c.drain_events()
	_run(c, 2.1)
	assert_almost(front.hp, 100.0 - 5.0 - 10.0, 1e-6, "flat + 10% of max hp")
	assert_almost(far.hp, 100.0, 1e-9, "out of reach")
	assert_eq(_events(c, "ability_fired").size(), 1)


func test_old_enemies_thin_out_after_boss() -> void:
	var c: GameCore = Fixture.core()
	assert_almost(float(c.mods.enemy_stats["grunt"]["pack"]), 2.0)
	_give(c, 0, 10)
	c.buy("node:road")
	c.buy("node:boss")
	c.battle.damage(c.battle.boss_enemy, 1e9, "impact", false, "test")
	c.tick(0.05)
	assert_almost(float(c.mods.enemy_stats["grunt"]["pack"]), 1.0, 1e-9, "region 0 enemy x0.5 after one boss")
	assert_almost(float(c.mods.enemy_stats["armored"]["pack"]), 1.0, 1e-9, "region 1 enemy unchanged")
