extends RefCounted
## Small synthetic content for core tests (independent of the real balance).
## Every required field is present (GameData validation is strict).


static func tower(dmg: float, projectile: String, row: int, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"name": "T", "desc": "T", "dmg": dmg, "dmg_type": "impact", "reload": 1.0,
		"range_min": 0, "range_max": 2000, "projectile": projectile, "proj_speed": 100000, "pierce": 0,
		"splash": 0, "crit_chance": 0.0, "crit_mult": 2.0, "limit": 3, "price": {"gears": 10}, "growth": 0.5,
		"row": row, "color": "brass_2"}
	d.merge(extra, true)
	return d


static func enemy(region: int, role: String, hp: float, speed: float, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"name": "E", "region": region, "role": role, "hp": hp, "speed": speed, "radius": 10,
		"loot": {"gears": 5, "blueprints": 1}, "resist": {}, "color": "iron_3"}
	if role == "normal":
		d["pack"] = 2
	d.merge(extra, true)
	return d


static func node(id: String, region: int, parents: Array, cost: float, growth: float, mx: int, effects: Array,
		extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"id": id, "region": region, "parents": parents, "pos": [0, 0], "kind": "tower",
		"cost": {"blueprints": cost}, "growth": growth, "max": mx, "effects": effects}
	d.merge(extra, true)
	return d


static func cfg() -> Dictionary:
	return {
		"economy": {
			"resources": {"gears": {"order": 0}, "blueprints": {"order": 1}, "coal": {"order": 2},
				"seals": {"order": 3, "meta": true}},
			"start": {"resources": {"gears": 0, "blueprints": 0}, "towers": {}, "regions": [0]},
			"seed": 1, "price_ceil_below": 1e15, "income_window": 10.0, "max_tick": 3600.0,
		},
		"waves": {
			"field": {"moat_x": 290, "spawn_x": 900, "spawn_jitter_x": 0, "end_x": 980, "y_min": 130, "y_max": 610},
			"pack_interval": 1000.0, "first_pack_at": 1000.0, "max_enemies": 300, "boss_pauses_packs": true,
			"pack_y_spread": 0.2, "speed_jitter": [1.0, 1.0], "lane_drift": 0.0, "bob_freq": 1.7,
			"old_region_pack_factor": 0.5, "curtain_width": 50, "dot_event_interval": 0.25,
		},
		"lens": {
			"radius": 40, "dmg": 2.0, "dmg_pct_hp": 0.0, "boss_pct_mult": 0.1, "tick": 0.25, "dmg_type": "steam", "idle_to_auto": 2.0, "auto_mult": 0.5,
			"auto_path": {"cx": 600, "cy": 370, "rx": 0, "ry": 0, "period": 10.0},
			"auto_speed": 0, "auto_retarget": 0.5, "auto_band": 60, "auto_sweep_period": 4.0, "auto_sweep_amp": 0,
			"seek_speed": 150, "seek_retarget": 0.5, "hit_radius_factor": 0.5,
		},
		"enemies": {
			"damage_types": {"impact": {}, "steam": {}, "spark": {}, "blast": {}},
			"enemies": {
				"grunt": enemy(0, "normal", 100, 30, {"start": true}),
				"armored": enemy(1, "normal", 100, 30, {"pack": 1, "loot": {"gears": 10},
					"resist": {"impact": 0.5, "steam": -0.5}}),
				"mole": enemy(1, "normal", 100, 30, {"pack": 1, "burrow": {"under": 1.0, "over": 1.0}}),
				"guard": enemy(1, "escort", 50, 30, {"loot": {"gears": 1}}),
				"chief": enemy(1, "boss", 1000, 200, {"radius": 20, "loot": {"gears": 50}}),
			},
			"bosses": {
				"chief": {"name": "B", "enemy": "chief", "escorts": [{"type": "guard", "count": 2, "at": 0.0}],
					"reward": {"blueprints": 100, "seals": 1}, "on_defeat": [{"type": "unlock_region", "value": 2}]},
			},
		},
		"towers": {
			"wall": {"rows": [{"x": 200, "y_min": 150, "y_max": 600, "count": 4},
				{"x": 168, "y_min": 150, "y_max": 600, "count": 4}]},
			"combat": {"shell_flight_min": 0.6, "shell_flight_max": 2.0, "splash_hit_factor": 0.5, "rivet_hit_pad": 3.0,
				"multishot_spread": 0.1, "cluster_spread": 1.4, "cluster_dmg": 0.5, "cluster_radius": 0.5,
				"cluster_flight": 0.3, "crit_chain_range": 90, "crit_chain_dmg": 0.5, "cone_hit_factor": 0.5,
				"knockback_boss": 0.0, "bullet_splash_dmg": 0.5, "near_moat_x": 150},
			"towers": {
				"gun": tower(10, "bullet", 0, {"start": true}),
				"rivet": tower(10, "rivet", 0, {"proj_speed": 2000, "pierce": 2, "limit": 2}),
				"mortar": tower(30, "shell", 1, {"dmg_type": "blast", "proj_speed": 400, "splash": 40, "limit": 2}),
				"jet": tower(10, "cone", 0, {"dmg_type": "steam", "proj_speed": 0, "range_max": 300, "cone_angle": 0.3,
					"on_hit": [{"status": "slow", "value": 0.5, "duration": 1.0}]}),
			},
			"upgrades": {
				"gun_dmg": {"name": "U", "tower": "gun", "cost": {"gears": 20}, "growth": 1.0, "max": 5,
					"effects": [{"type": "tower_dmg_mult", "target": "gun", "value": 0.5}],
					"milestones": [{"level": 2, "name": "MS", "effects": [{"type": "tower_tier_add", "target": "gun", "value": 1},
						{"type": "tower_multishot_add", "target": "gun", "value": 1}]}]},
			},
			"abilities": {
				"kettle": {"name": "K", "interval": 2.0, "dmg": 5, "dmg_pct_hp": 0.1, "boss_pct_mult": 0.1,
					"dmg_type": "steam", "radius": 40, "reach_x": 200, "statuses": []},
			},
		},
		"map": {
			"regions": [{"id": 0}, {"id": 1}, {"id": 2}],
			"nodes": [
				node("a", 0, [], 10, 1.0, 3, [{"type": "tower_dmg_mult", "target": "gun", "value": 0.5}]),
				node("b", 0, ["a"], 10, 0, 2, [{"type": "enemy_bait", "target": "grunt", "value": 1.0, "hp": 0.5},
					{"type": "enemy_spawn_add", "target": "grunt", "value": 1},
					{"type": "tower_limit_add", "target": "gun", "value": 2}], {"kind": "bait"}),
				node("mulnode", 0, [], 1, 0, 3, [{"type": "global_dmg_mult", "value": 1.0, "stack": "mul"}]),
				node("road", 0, [], 1, 0, 1, [{"type": "unlock_region", "value": 1}]),
				node("armor", 1, ["road"], 1, 0, 1, [{"type": "unlock_enemy", "target": "armored"},
					{"type": "unlock_tower", "target": "rivet"}, {"type": "unlock_tower", "target": "mortar"},
					{"type": "unlock_tower", "target": "jet"}]),
				node("lens", 0, [], 1, 0, 2, [{"type": "lens_radius", "value": 10}, {"type": "lens_dmg", "value": 0.5},
					{"type": "lens_rate", "value": 1.0}, {"type": "lens_auto_mult", "value": 0.25}]),
				node("moat", 0, [], 1, 0, 1, [{"type": "moat_damage", "value": 40}]),
				node("kettle", 0, [], 1, 0, 1, [{"type": "unlock_ability", "target": "kettle"}]),
				node("hot", 1, ["road"], 1, 0, 1, [{"type": "tower_on_hit_status", "target": "rivet", "status": "scald",
					"value": 1.0, "duration": 2.0}], {"excludes": ["boom"]}),
				node("boom", 1, ["road"], 1, 0, 1, [{"type": "tower_cluster_add", "target": "mortar", "value": 3}],
					{"excludes": ["hot"]}),
				node("boss", 1, ["road"], 1, 0, 1, [{"type": "call_boss", "target": "chief"}], {"kind": "boss"}),
				node("trophy", 1, ["boss"], 0, 0, 1, [{"type": "lens_extra_add", "value": 1}],
					{"kind": "reward", "requires": {"boss": "chief"}}),
				node("beyond", 2, ["boss"], 1, 0, 1, []),
			],
		},
	}


static func core(seed_value: int = 1) -> GameCore:
	var c := GameCore.create(seed_value, GameData.new(cfg()))
	return c
