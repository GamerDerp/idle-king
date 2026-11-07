class_name Mods
extends RefCounted
## Effect aggregation: turns everything bought (map nodes, shop upgrades and
## their milestones, defeated bosses) into derived stats. Data-driven: every
## effect is a {type, target, value, ...} dictionary from config; see
## GameData.EFFECT_TYPES. Recomputed from scratch (Mods.compute) after every
## purchase, so the state never stores derived numbers.
##
## Stat formula for key K and target T:
##   (base + add[K:T] + add[K:all]) * (1 + pct[K:T] + pct[K:all]) * mul[K:T] * mul[K:all]
## An effect adds value*level to add/pct, or with "stack": "mul" multiplies
## mul by (1+value)^level. Bait HP ("hp" field) always stacks multiplicatively.

## Effect type -> stat key (types not listed use their own name).
const STAT_OF: Dictionary = {
	"enemy_spawn_add": "enemy_spawn", "enemy_hp_mult": "enemy_hp",
	"tower_limit_add": "tower_limit", "tower_dmg_mult": "tower_dmg", "tower_reload_mult": "tower_rate",
	"tower_pierce_add": "tower_pierce", "tower_splash_add": "tower_splash",
	"tower_crit_chance_add": "tower_crit_chance", "tower_crit_mult_add": "tower_crit_mult",
	"tower_range_add": "tower_range", "tower_multishot_add": "tower_multishot",
	"tower_knockback_add": "tower_knockback", "tower_cluster_add": "tower_cluster",
	"tower_crit_chain_add": "tower_crit_chain", "tower_tier_add": "tower_tier",
	"lens_auto_mult": "lens_auto", "lens_extra_add": "lens_extra",
	"global_dmg_mult": "global_dmg", "global_loot_mult": "global_loot", "global_bp_mult": "global_bp",
	"moat_damage": "moat_dps", "moat_slow_add": "moat_slow", "moat_width_add": "moat_width",
	"ability_dmg_mult": "ability_dmg", "ability_count_add": "ability_count",
}
## Effect types whose value is a flat addition (others are +fraction multipliers).
const ADD_TYPES: Array[String] = [
	"enemy_spawn_add", "tower_limit_add", "tower_pierce_add", "tower_splash_add",
	"tower_crit_chance_add", "tower_crit_mult_add", "tower_range_add", "tower_multishot_add",
	"tower_knockback_add", "tower_cluster_add", "tower_crit_chain_add", "tower_tier_add",
	"lens_radius", "lens_auto_mult", "lens_extra_add", "moat_damage", "moat_slow_add", "moat_width_add",
	"ability_count_add",
]
const LENS_KEY: String = "__lens"
const ABILITY_PREFIX: String = "__ability:"

var add: Dictionary = {}
var pct: Dictionary = {}
var mul: Dictionary = {}
var flags: Dictionary = {}          ## "enemy:<type>", "tower:<type>", "ability:<id>", "lens_seek"
var regions: Dictionary = {}        ## region id -> true
var statuses: Dictionary = {}       ## tower type (or LENS_KEY) -> {status id -> {value, duration}}

## --- derived, read by Battle / view ---
var unlocked_enemies: Array[String] = []
var unlocked_towers: Array[String] = []
var tower_stats: Dictionary = {}    ## type -> {dmg, reload, range_min, range_max, pierce, splash, multishot, tier, ...}
var enemy_stats: Dictionary = {}    ## type -> {hp, speed, radius, pack, loot{}, resist{}, role, burrow}
var lens: Dictionary = {}           ## radius, dmg, interval, auto_mult, seek, extra, statuses, dmg_type
var abilities: Dictionary = {}      ## unlocked ability id -> {interval, dmg, dmg_pct_hp, dmg_type, radius, reach_x, status}
var moat_dps: float = 0.0
var moat_slow: float = 0.0
var moat_width: float = 0.0
var global_dmg: float = 1.0
var era: int = 0                    ## bosses defeated: older enemies thin out in packs


static func compute(data: GameData, state: GameState) -> Mods:
	var m := Mods.new()
	for r: Variant in data.economy["start"]["regions"]:
		m.regions[int(r)] = true
	for id: String in data.node_order:
		var lvl: int = state.node_level(id)
		if lvl > 0:
			for ef: Dictionary in data.node_effects(id):
				m.apply_effect(ef, lvl)
	for id: String in data.upgrades:
		var lvl: int = state.upgrade_level(id)
		if lvl <= 0:
			continue
		for ef: Dictionary in data.upgrades[id]["effects"]:
			m.apply_effect(ef, lvl)
		for ms: Dictionary in data.upgrades[id].get("milestones", []):
			if lvl >= int(ms["level"]):
				for ef: Dictionary in ms["effects"]:
					m.apply_effect(ef, 1)
	for b: String in data.bosses:
		if state.boss_status(b) == "defeated":
			m.era += 1
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
		"unlock_ability":
			flags["ability:" + target] = true
		"unlock_region":
			regions[int(v)] = true
		"lens_seek":
			flags["lens_seek"] = true
		"call_boss":
			pass  # an action on purchase (GameCore), not a stat
		"tower_on_hit_status", "lens_status", "ability_status":
			var owner: String = target
			if t == "lens_status":
				owner = LENS_KEY
			elif t == "ability_status":
				owner = ABILITY_PREFIX + target
			_add_status(owner, str(ef["status"]), v * level, float(ef.get("duration", 1.0)))
		"enemy_loot_mult", "enemy_bp_mult", "enemy_bait":
			if t != "enemy_bp_mult":
				_put("enemy_loot", target, v, level, stack_mul)
			if t != "enemy_loot_mult":
				_put("enemy_bp", target, v, level, stack_mul)
			var hp: float = float(ef.get("hp", 0.0))
			if hp != 0.0:
				_put("enemy_hp", target, hp, level, true)
		_:
			var stat: String = str(STAT_OF.get(t, t))
			if ADD_TYPES.has(t):
				var key: String = stat + ":" + target
				add[key] = float(add.get(key, 0.0)) + v * level
			else:
				_put(stat, target, v, level, stack_mul)


func _add_status(owner: String, st: String, value: float, duration: float) -> void:
	var per: Dictionary = statuses.get(owner, {})
	var cur: Dictionary = per.get(st, {"value": 0.0, "duration": 0.0})
	cur["value"] = float(cur["value"]) + value
	cur["duration"] = maxf(float(cur["duration"]), duration)
	per[st] = cur
	statuses[owner] = per


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
	var old_factor: float = float(data.waves["old_region_pack_factor"])
	for e: String in data.enemies:
		var d: Dictionary = data.enemies[e]
		var role: String = str(d["role"])
		if role == "normal" and (bool(d.get("start", false)) or flags.has("enemy:" + e)):
			unlocked_enemies.append(e)
		var loot: Dictionary = {}
		var base_loot: Dictionary = d["loot"]
		for r: String in base_loot:
			if r == "blueprints":
				loot[r] = stat("enemy_bp", e, float(base_loot[r])) * g_bp
			else:
				loot[r] = stat("enemy_loot", e, float(base_loot[r])) * g_loot
		var pack: float = 0.0
		if role == "normal":
			var age: int = maxi(0, era - int(d["region"]))
			pack = maxf(0.0, float(d["pack"]) + add_value("enemy_spawn", e)) * pow(old_factor, age)
		enemy_stats[e] = {
			"hp": maxf(1.0, stat("enemy_hp", e, float(d["hp"]))),
			"speed": float(d["speed"]),
			"radius": float(d["radius"]),
			"pack": pack,
			"loot": loot,
			"resist": d["resist"],
			"role": role,
			"burrow": d.get("burrow", {}),
		}
	for t: String in data.towers:
		var d: Dictionary = data.towers[t]
		if bool(d.get("start", false)) or flags.has("tower:" + t):
			unlocked_towers.append(t)
		var rate: float = maxf(0.01, stat("tower_rate", t, 1.0))
		var sts: Dictionary = {}
		for st: Dictionary in d.get("on_hit", []):
			sts[str(st["status"])] = {"value": float(st["value"]), "duration": float(st["duration"])}
		var extra: Dictionary = statuses.get(t, {})
		for s: String in extra:
			var cur: Dictionary = sts.get(s, {"value": 0.0, "duration": 0.0})
			sts[s] = {"value": float(cur["value"]) + float(extra[s]["value"]),
				"duration": maxf(float(cur["duration"]), float(extra[s]["duration"]))}
		tower_stats[t] = {
			"dmg": stat("tower_dmg", t, float(d["dmg"])) * global_dmg,
			"dmg_type": str(d["dmg_type"]),
			"reload": maxf(0.02, float(d["reload"]) / rate),
			"range_min": float(d["range_min"]),
			"range_max": float(d["range_max"]) + add_value("tower_range", t),
			"projectile": str(d["projectile"]),
			"proj_speed": float(d["proj_speed"]),
			"pierce": int(round(float(d["pierce"]) + add_value("tower_pierce", t))),
			"splash": float(d["splash"]) + add_value("tower_splash", t),
			"crit_chance": clampf(float(d["crit_chance"]) + add_value("tower_crit_chance", t), 0.0, 1.0),
			"crit_mult": float(d["crit_mult"]) + add_value("tower_crit_mult", t),
			"limit": int(round(float(d["limit"]) + add_value("tower_limit", t))),
			"multishot": 1 + int(round(add_value("tower_multishot", t))),
			"knockback": add_value("tower_knockback", t),
			"cluster": int(round(add_value("tower_cluster", t))),
			"crit_chain": int(round(add_value("tower_crit_chain", t))),
			"tier": 1 + int(round(add_value("tower_tier", t))),
			"cone_angle": float(d.get("cone_angle", 0.0)),
			"puddle": d.get("puddle", {}),
			"row": int(d["row"]),
			"statuses": sts,
		}
	lens = {
		"radius": data.lens_value("radius") + add_value("lens_radius"),
		"dmg": stat("lens_dmg", "all", data.lens_value("dmg")) * global_dmg,
		"dmg_pct_hp": stat("lens_dmg", "all", data.lens_value("dmg_pct_hp")) * global_dmg,
		"interval": maxf(0.02, data.lens_value("tick") / maxf(0.01, stat("lens_rate", "all", 1.0))),
		"auto_mult": data.lens_value("auto_mult") + add_value("lens_auto"),
		"seek": flags.has("lens_seek"),
		"extra": int(round(add_value("lens_extra"))),
		"statuses": statuses.get(LENS_KEY, {}),
		"dmg_type": str(data.lens["dmg_type"]),
	}
	for a: String in data.abilities:
		if flags.has("ability:" + a):
			var ad: Dictionary = data.abilities[a]
			var k: float = stat("ability_dmg", a, 1.0) * global_dmg
			var asts: Dictionary = {}
			for st: Dictionary in ad.get("statuses", []):
				asts[str(st["status"])] = {"value": float(st["value"]), "duration": float(st["duration"])}
			var aextra: Dictionary = statuses.get(ABILITY_PREFIX + a, {})
			for s2: String in aextra:
				var cur: Dictionary = asts.get(s2, {"value": 0.0, "duration": 0.0})
				asts[s2] = {"value": float(cur["value"]) + float(aextra[s2]["value"]),
					"duration": maxf(float(cur["duration"]), float(aextra[s2]["duration"]))}
			abilities[a] = {
				"interval": float(ad["interval"]), "dmg": float(ad["dmg"]) * k,
				"dmg_pct_hp": float(ad["dmg_pct_hp"]) * k, "boss_pct_mult": float(ad["boss_pct_mult"]),
				"dmg_type": str(ad["dmg_type"]), "radius": float(ad["radius"]), "reach_x": float(ad["reach_x"]),
				"count": 1 + int(round(add_value("ability_count", a))), "statuses": asts,
			}
	moat_dps = add_value("moat_dps") * global_dmg
	moat_slow = clampf(add_value("moat_slow"), 0.0, 0.9)
	moat_width = float(data.waves["curtain_width"]) + add_value("moat_width")


## Set of qualitative features currently present ("behaviour signature").
## A purchase is "new on screen" when it adds keys here (GameCore.novelty_of).
func behaviours() -> Dictionary:
	var b: Dictionary = {}
	for e in unlocked_enemies:
		b["enemy:" + e] = true
	for t in unlocked_towers:
		b["tower:" + t] = true
		var ts: Dictionary = tower_stats[t]
		b["tier:%s:%d" % [t, int(ts["tier"])]] = true
		if int(ts["pierce"]) > 0:
			b["pierce:" + t] = true
		if float(ts["splash"]) > 0.0:
			b["splash:" + t] = true
		if int(ts["multishot"]) > 1:
			b["multishot:" + t] = true
		if float(ts["knockback"]) > 0.0:
			b["knockback:" + t] = true
		if int(ts["cluster"]) > 0:
			b["cluster:" + t] = true
		if int(ts["crit_chain"]) > 0:
			b["crit_chain:" + t] = true
		for s: String in ts["statuses"]:
			b["status:%s:%s" % [t, s]] = true
	for r: int in regions:
		b["region:%d" % r] = true
	for a: String in abilities:
		b["ability:" + a] = true
		if int(abilities[a]["count"]) > 1:
			b["ability_count:%s:%d" % [a, int(abilities[a]["count"])]] = true
		for s: String in abilities[a]["statuses"]:
			b["ability_status:%s:%s" % [a, s]] = true
	if bool(lens["seek"]):
		b["lens_seek"] = true
	for s: String in lens["statuses"]:
		b["lens_status:" + s] = true
	if int(lens["extra"]) > 0:
		b["lens_extra:%d" % int(lens["extra"])] = true
	if moat_dps > 0.0:
		b["moat_curtain"] = true
	if moat_slow > 0.0:
		b["moat_slow"] = true
	return b
