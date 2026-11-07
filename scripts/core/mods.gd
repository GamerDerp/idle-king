class_name Mods
extends RefCounted
## Effect aggregation: turns everything bought (map nodes, shop upgrades,
## defeated bosses) into derived stats. Data-driven: every effect is a
## {type, target, value, ...} dictionary from config; see GameData.EFFECT_TYPES.
## Recomputed from scratch (Mods.compute) after every purchase, so the state
## never stores derived numbers.
##
## Stat formula for key K and target T:
##   (base + add[K:T] + add[K:all]) * (1 + pct[K:T] + pct[K:all]) * mul[K:T] * mul[K:all]
## An effect adds value*level to add/pct, or with "stack": "mul" multiplies
## mul by (1+value)^level.

## Effect type -> stat key (types not listed use their own name).
const STAT_OF: Dictionary = {
	"enemy_spawn_add": "enemy_spawn", "enemy_hp_mult": "enemy_hp",
	"tower_limit_add": "tower_limit", "tower_dmg_mult": "tower_dmg", "tower_reload_mult": "tower_rate",
	"tower_pierce_add": "tower_pierce", "tower_splash_add": "tower_splash",
	"tower_crit_chance_add": "tower_crit_chance", "tower_crit_mult_add": "tower_crit_mult",
	"tower_range_add": "tower_range", "lens_auto_mult": "lens_auto",
	"global_dmg_mult": "global_dmg", "global_loot_mult": "global_loot", "global_bp_mult": "global_bp",
	"moat_damage": "moat_dps",
}
## Effect types whose value is a flat addition (others are +fraction multipliers).
const ADD_TYPES: Array[String] = [
	"enemy_spawn_add", "tower_limit_add", "tower_pierce_add", "tower_splash_add",
	"tower_crit_chance_add", "tower_crit_mult_add", "tower_range_add",
	"lens_radius", "lens_auto_mult", "moat_damage",
]

var add: Dictionary = {}
var pct: Dictionary = {}
var mul: Dictionary = {}
var flags: Dictionary = {}          ## "enemy:<type>", "tower:<type>", "lens_seek"
var regions: Dictionary = {}        ## region id -> true
var statuses: Dictionary = {}       ## tower type -> {status id -> {value, duration}}

## --- derived, read by Battle / view ---
var unlocked_enemies: Array[String] = []
var unlocked_towers: Array[String] = []
var tower_stats: Dictionary = {}    ## type -> {dmg, reload, range_min, range_max, pierce, splash, crit_chance, crit_mult, limit, ...}
var enemy_stats: Dictionary = {}    ## type -> {hp, speed, radius, pack, loot{}, resist{}}
var lens: Dictionary = {}           ## radius, dmg, interval, auto_mult, seek
var moat_dps: float = 0.0
var global_dmg: float = 1.0


static func compute(data: GameData, state: GameState) -> Mods:
	var m := Mods.new()
	for r: Variant in data.economy.get("start", {}).get("regions", [0]):
		m.regions[int(r)] = true
	for id: String in data.node_order:
		var lvl: int = state.node_level(id)
		if lvl > 0:
			for ef: Dictionary in data.node_effects(id):
				m.apply_effect(ef, lvl)
	for id: String in data.upgrades:
		var lvl: int = state.upgrade_level(id)
		if lvl > 0:
			for ef: Dictionary in data.upgrades[id].get("effects", []):
				m.apply_effect(ef, lvl)
	for b: String in data.bosses:
		if state.boss_status(b) == "defeated":
			for ef: Dictionary in data.bosses[b].get("on_defeat", []):
				m.apply_effect(ef, 1)
	m._derive(data)
	return m


## Applies one effect at a given level (level >= 1).
func apply_effect(ef: Dictionary, level: int) -> void:
	var t: String = str(ef.get("type", ""))
	var target: String = str(ef.get("target", "all"))
	var v: float = float(ef.get("value", 0.0))
	var stack_mul: bool = str(ef.get("stack", "")) == "mul"
	match t:
		"unlock_enemy":
			flags["enemy:" + target] = true
		"unlock_tower":
			flags["tower:" + target] = true
		"unlock_region":
			regions[int(v)] = true
		"lens_seek":
			flags["lens_seek"] = true
		"call_boss":
			pass  # an action on purchase (GameCore), not a stat
		"tower_on_hit_status":
			var st: String = str(ef.get("status", ""))
			var per: Dictionary = statuses.get(target, {})
			var cur: Dictionary = per.get(st, {"value": 0.0, "duration": 0.0})
			cur["value"] = float(cur["value"]) + v * level
			cur["duration"] = maxf(float(cur["duration"]), float(ef.get("duration", 1.0)))
			per[st] = cur
			statuses[target] = per
		"enemy_loot_mult", "enemy_bp_mult":
			_put("enemy_loot" if t == "enemy_loot_mult" else "enemy_bp", target, v, level, stack_mul)
			var hp: float = float(ef.get("hp", 0.0))
			if hp != 0.0:
				_put("enemy_hp", target, hp, level, stack_mul)
		_:
			var stat: String = str(STAT_OF.get(t, t))
			if ADD_TYPES.has(t):
				var key: String = stat + ":" + target
				add[key] = float(add.get(key, 0.0)) + v * level
			else:
				_put(stat, target, v, level, stack_mul)


func _put(stat: String, target: String, v: float, level: int, stack_mul: bool) -> void:
	var key: String = stat + ":" + target
	if stack_mul:
		mul[key] = float(mul.get(key, 1.0)) * pow(1.0 + v, level)
	else:
		pct[key] = float(pct.get(key, 0.0)) + v * level


## Generic stat lookup (see class doc).
func stat(key: String, target: String, base: float) -> float:
	var a: String = key + ":" + target
	var b: String = key + ":all"
	var s: float = base + float(add.get(a, 0.0))
	var p: float = 1.0 + float(pct.get(a, 0.0))
	var m: float = float(mul.get(a, 1.0))
	if target != "all":
		s += float(add.get(b, 0.0))
		p += float(pct.get(b, 0.0))
		m *= float(mul.get(b, 1.0))
	return Num.safe(s * maxf(p, 0.0) * m)


func add_value(key: String, target: String = "all") -> float:
	var v: float = float(add.get(key + ":" + target, 0.0))
	if target != "all":
		v += float(add.get(key + ":all", 0.0))
	return v


func is_region_unlocked(r: int) -> bool:
	return regions.has(r)


func _derive(data: GameData) -> void:
	global_dmg = stat("global_dmg", "all", 1.0)
	var g_loot: float = stat("global_loot", "all", 1.0)
	var g_bp: float = stat("global_bp", "all", 1.0)
	for e: String in data.enemies:
		var d: Dictionary = data.enemies[e]
		if bool(d.get("start", false)) or flags.has("enemy:" + e):
			if str(d.get("role", "normal")) == "normal":
				unlocked_enemies.append(e)
		var loot: Dictionary = {}
		var base_loot: Dictionary = d.get("loot", {})
		for r: String in base_loot:
			if r == "blueprints":
				loot[r] = stat("enemy_bp", e, float(base_loot[r])) * g_bp
			else:
				loot[r] = stat("enemy_loot", e, float(base_loot[r])) * g_loot
		enemy_stats[e] = {
			"hp": maxf(1.0, stat("enemy_hp", e, float(d.get("hp", 1.0)))),
			"speed": float(d.get("speed", 20.0)),
			"radius": float(d.get("radius", 10.0)),
			"pack": maxf(0.0, float(d.get("pack", 0.0)) + add_value("enemy_spawn", e)),
			"loot": loot,
			"resist": d.get("resist", {}),
			"role": str(d.get("role", "normal")),
		}
	for t: String in data.towers:
		var d: Dictionary = data.towers[t]
		if bool(d.get("start", false)) or flags.has("tower:" + t):
			unlocked_towers.append(t)
		var rate: float = maxf(0.01, stat("tower_rate", t, 1.0))
		tower_stats[t] = {
			"dmg": stat("tower_dmg", t, float(d.get("dmg", 1.0))) * global_dmg,
			"dmg_type": str(d.get("dmg_type", "impact")),
			"reload": maxf(0.02, float(d.get("reload", 1.0)) / rate),
			"range_min": float(d.get("range_min", 0.0)),
			"range_max": float(d.get("range_max", 500.0)) + add_value("tower_range", t),
			"projectile": str(d.get("projectile", "bullet")),
			"proj_speed": float(d.get("proj_speed", 600.0)),
			"pierce": int(round(float(d.get("pierce", 0)) + add_value("tower_pierce", t))),
			"splash": float(d.get("splash", 0.0)) + add_value("tower_splash", t),
			"crit_chance": clampf(float(d.get("crit_chance", 0.0)) + add_value("tower_crit_chance", t), 0.0, 1.0),
			"crit_mult": float(d.get("crit_mult", 2.0)) + add_value("tower_crit_mult", t),
			"limit": int(round(float(d.get("limit", 1)) + add_value("tower_limit", t))),
			"statuses": statuses.get(t, {}),
		}
	var base_tick: float = data.lens_value("tick", 0.25)
	lens = {
		"radius": data.lens_value("radius", 40.0) + add_value("lens_radius"),
		"dmg": stat("lens_dmg", "all", data.lens_value("dmg", 1.0)) * global_dmg,
		"interval": maxf(0.02, base_tick / maxf(0.01, stat("lens_rate", "all", 1.0))),
		"auto_mult": data.lens_value("auto_mult", 0.5) + add_value("lens_auto"),
		"seek": flags.has("lens_seek"),
		"dmg_type": str(data.lens.get("dmg_type", "steam")),
	}
	moat_dps = add_value("moat_dps") * global_dmg
