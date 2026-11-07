extends RefCounted
## Small synthetic content for core tests (independent of the real balance).


static func cfg() -> Dictionary:
	return {
		"economy": {
			"resources": {"gears": {"order": 0}, "blueprints": {"order": 1}},
			"start": {"resources": {"gears": 0, "blueprints": 0}, "towers": {}, "regions": [0]},
			"seed": 1,
		},
		"waves": {
			"field": {"moat_x": 290, "spawn_x": 900, "spawn_jitter_x": 0, "end_x": 980, "y_min": 130, "y_max": 610},
			"pack_interval": 1000.0, "first_pack_at": 1000.0, "max_enemies": 300,
			"boss_pauses_packs": true, "curtain_width": 50, "lane_drift": 0.0,
		},
		"lens": {
			"radius": 40, "dmg": 2.0, "tick": 0.25, "dmg_type": "steam", "idle_to_auto": 2.0, "auto_mult": 0.5,
			"auto_path": {"cx": 600, "cy": 370, "rx": 0, "ry": 0, "period": 10.0},
			"auto_speed": 0, "seek_speed": 150, "seek_retarget": 0.5, "hit_radius_factor": 0.5,
		},
		"enemies": {
			"damage_types": {"impact": {}, "steam": {}, "spark": {}, "blast": {}},
			"enemies": {
				"grunt": {"region": 0, "role": "normal", "start": true, "hp": 100, "speed": 30, "radius": 10,
					"pack": 2, "loot": {"gears": 5, "blueprints": 1}, "resist": {}},
				"armored": {"region": 1, "role": "normal", "hp": 100, "speed": 30, "radius": 10, "pack": 1,
					"loot": {"gears": 10}, "resist": {"impact": 0.5, "steam": -0.5}},
				"guard": {"region": 1, "role": "escort", "hp": 50, "speed": 30, "radius": 10, "loot": {"gears": 1}},
				"chief": {"region": 1, "role": "boss", "hp": 1000, "speed": 200, "radius": 20, "loot": {"gears": 50}},
			},
			"bosses": {
				"chief": {"enemy": "chief", "escorts": [{"type": "guard", "count": 2, "at": 0.0}],
					"reward": {"blueprints": 100}, "on_defeat": [{"type": "unlock_region", "value": 2}]},
			},
		},
		"towers": {
			"wall": {"y_min": 150, "y_max": 600, "slots": 10, "row_offset_x": 14},
			"towers": {
				"gun": {"start": true, "dmg": 10, "dmg_type": "impact", "reload": 1.0, "range_min": 0, "range_max": 2000,
					"projectile": "bullet", "proj_speed": 100000, "pierce": 0, "splash": 0, "crit_chance": 0.0,
					"crit_mult": 2.0, "limit": 3, "price": {"gears": 10}, "growth": 0.5, "column_x": 200},
				"rivet": {"dmg": 10, "dmg_type": "impact", "reload": 1.0, "range_min": 0, "range_max": 2000,
					"projectile": "rivet", "proj_speed": 2000, "pierce": 2, "splash": 0, "crit_chance": 0.0,
					"crit_mult": 2.0, "limit": 2, "price": {"gears": 10}, "growth": 0.5, "column_x": 165},
				"mortar": {"dmg": 30, "dmg_type": "blast", "reload": 1.0, "range_min": 0, "range_max": 2000,
					"projectile": "shell", "proj_speed": 400, "pierce": 0, "splash": 40, "crit_chance": 0.0,
					"crit_mult": 2.0, "limit": 2, "price": {"gears": 10}, "growth": 0.5, "column_x": 130},
			},
			"upgrades": {
				"gun_dmg": {"tower": "gun", "cost": {"gears": 20}, "growth": 1.0, "max": 5,
					"effects": [{"type": "tower_dmg_mult", "target": "gun", "value": 0.5}]},
			},
		},
		"map": {
			"regions": [{"id": 0}, {"id": 1}, {"id": 2}],
			"nodes": [
				{"id": "a", "region": 0, "parents": [], "cost": {"blueprints": 10}, "growth": 1.0, "max": 3,
					"effects": [{"type": "tower_dmg_mult", "target": "gun", "value": 0.5}]},
				{"id": "b", "region": 0, "parents": ["a"], "cost": {"blueprints": 10}, "growth": 0, "max": 2,
					"effects": [{"type": "enemy_loot_mult", "target": "grunt", "value": 1.0, "hp": 0.5},
						{"type": "enemy_spawn_add", "target": "grunt", "value": 1},
						{"type": "tower_limit_add", "target": "gun", "value": 2}]},
				{"id": "mulnode", "region": 0, "parents": [], "cost": {"blueprints": 1}, "growth": 0, "max": 3,
					"effects": [{"type": "global_dmg_mult", "value": 1.0, "stack": "mul"}]},
				{"id": "road", "region": 0, "parents": [], "cost": {"blueprints": 1}, "growth": 0, "max": 1,
					"effects": [{"type": "unlock_region", "value": 1}]},
				{"id": "armor", "region": 1, "parents": ["road"], "cost": {"blueprints": 1}, "growth": 0, "max": 1,
					"effects": [{"type": "unlock_enemy", "target": "armored"}, {"type": "unlock_tower", "target": "rivet"},
						{"type": "unlock_tower", "target": "mortar"}]},
				{"id": "lens", "region": 0, "parents": [], "cost": {"blueprints": 1}, "growth": 0, "max": 2,
					"effects": [{"type": "lens_radius", "value": 10}, {"type": "lens_dmg", "value": 0.5},
						{"type": "lens_rate", "value": 1.0}, {"type": "lens_auto_mult", "value": 0.25}]},
				{"id": "moat", "region": 0, "parents": [], "cost": {"blueprints": 1}, "growth": 0, "max": 1,
					"effects": [{"type": "moat_damage", "value": 40}]},
				{"id": "hot", "region": 1, "parents": ["road"], "cost": {"blueprints": 1}, "growth": 0, "max": 1,
					"effects": [{"type": "tower_on_hit_status", "target": "rivet", "status": "scald", "value": 1.0, "duration": 2.0}]},
				{"id": "boss", "region": 1, "parents": ["road"], "cost": {"blueprints": 1}, "growth": 0, "max": 1,
					"effects": [{"type": "call_boss", "target": "chief"}]},
				{"id": "beyond", "region": 2, "parents": ["boss"], "cost": {"blueprints": 1}, "growth": 0, "max": 1,
					"effects": []},
			],
		},
	}


static func core(seed_value: int = 1) -> GameCore:
	var c := GameCore.create(seed_value, GameData.new(cfg()))
	return c
