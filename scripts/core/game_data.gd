class_name GameData
extends RefCounted
## Read-only game content parsed from config/*.json (economy, waves, enemies,
## towers, lens, map). Built from the raw dictionaries returned by
## ConfigLoader.load_dir(), so it works in the game, tests and headless sim.
## Validation is strict: every required field must exist (the rest of the core
## reads them without defaults) and every reference must resolve.

## Effect types the core understands (see Mods.apply_effect and docs/CORE.md).
const EFFECT_TYPES: Array[String] = [
	"unlock_enemy", "enemy_spawn_add", "enemy_loot_mult", "enemy_bp_mult", "enemy_hp_mult", "enemy_bait",
	"unlock_tower", "tower_limit_add", "tower_dmg_mult", "tower_reload_mult", "tower_pierce_add",
	"tower_splash_add", "tower_crit_chance_add", "tower_crit_mult_add", "tower_range_add",
	"tower_on_hit_status", "tower_multishot_add", "tower_knockback_add", "tower_cluster_add",
	"tower_crit_chain_add", "tower_tier_add",
	"lens_radius", "lens_dmg", "lens_rate", "lens_auto_mult", "lens_seek", "lens_status", "lens_extra_add",
	"global_dmg_mult", "global_loot_mult", "global_bp_mult",
	"moat_damage", "moat_slow_add", "moat_width_add",
	"unlock_ability", "ability_dmg_mult", "ability_status", "ability_count_add",
	"call_boss", "unlock_region",
	# R2
	"unlock_producer", "producer_amount_mult", "producer_rate_mult", "producer_output_add",
	"tower_zone_status", "tower_armor_pierce", "tower_dig", "lens_dig", "scald_shred",
	"tower_chain_add", "tower_bounce_add", "wet_metal", "ability_puddle",
]
const STATUSES: Array[String] = ["scald", "slow", "stun"]
## Effects whose target is a producer id.
const PRODUCER_EFFECTS: Array[String] = ["unlock_producer", "producer_amount_mult", "producer_rate_mult",
	"producer_output_add"]

const TOWER_REQ: Array[String] = ["name", "desc", "dmg", "dmg_type", "reload", "range_min", "range_max",
	"projectile", "proj_speed", "pierce", "splash", "crit_chance", "crit_mult", "limit", "price", "growth", "row", "color"]
const PROJECTILES: Array[String] = ["bullet", "rivet", "shell", "cone", "chain", "ricochet"]
## Extra required tower fields per projectile kind.
const PROJECTILE_REQ: Dictionary = {
	"cone": ["cone_angle"],
	"chain": ["chain", "chain_range", "chain_decay"],
	"ricochet": ["bounces", "bounce_gain", "bounce_range"],
}
const ENEMY_REQ: Array[String] = ["name", "region", "role", "hp", "speed", "radius", "loot", "resist", "color"]
const NODE_REQ: Array[String] = ["id", "region", "parents", "pos", "kind", "cost", "growth", "max", "effects"]
const UPG_REQ: Array[String] = ["name", "tower", "cost", "growth", "max", "effects"]
const LENS_REQ: Array[String] = ["radius", "dmg", "dmg_pct_hp", "boss_pct_mult", "tick", "dmg_type", "idle_to_auto", "auto_mult", "auto_path",
	"auto_speed", "auto_retarget", "auto_band", "auto_sweep_period", "auto_sweep_amp", "seek_speed",
	"seek_retarget", "hit_radius_factor"]
const WAVES_REQ: Array[String] = ["field", "pack_interval", "first_pack_at", "max_enemies", "boss_pauses_packs",
	"pack_y_spread", "speed_jitter", "lane_drift", "bob_freq", "old_region_pack_factor", "curtain_width",
	"dot_event_interval"]
const FIELD_REQ: Array[String] = ["moat_x", "spawn_x", "spawn_jitter_x", "end_x", "y_min", "y_max"]
const COMBAT_REQ: Array[String] = ["shell_flight_min", "shell_flight_max", "splash_hit_factor", "rivet_hit_pad",
	"multishot_spread", "cluster_spread", "cluster_dmg", "cluster_radius", "cluster_flight", "crit_chain_range",
	"crit_chain_dmg", "cone_hit_factor", "knockback_boss", "bullet_splash_dmg", "near_moat_x",
	"knockback_novel_min", "direct_kinds", "stun_boss", "split_spread", "tower_stagger_step", "tower_stagger_mod",
	"fallback_slot", "wet_metal_mult"]
const ECON_REQ: Array[String] = ["resources", "start", "seed", "price_ceil_below", "income_window", "max_tick"]
const PUDDLE_REQ: Array[String] = ["dps", "radius", "duration", "dmg_type"]
const ABILITY_REQ: Array[String] = ["name", "interval", "dmg", "dmg_pct_hp", "boss_pct_mult", "dmg_type", "radius", "reach_x",
	"shape", "kill_loot_mult"]
const ABILITY_SHAPES: Array[String] = ["splash", "line"]
const PRODUCER_REQ: Array[String] = ["name", "interval", "output"]
## Optional enemy mechanics and their required sub-fields.
const ENEMY_MECH_REQ: Dictionary = {
	"burrow": ["under", "over", "under_speed"],
	"split": ["type", "count"],
	"charge": ["every", "duration", "mult"],
	"shield": ["frac", "block", "breakers"],
}
const IMMUNITIES: Array[String] = ["slow", "stun", "knockback"]

var economy: Dictionary = {}
var waves: Dictionary = {}
var lens: Dictionary = {}
var enemies: Dictionary = {}      # type -> def
var bosses: Dictionary = {}       # boss id -> def
var damage_types: Dictionary = {}
var towers: Dictionary = {}       # type -> def
var wall: Dictionary = {}
var combat: Dictionary = {}
var abilities: Dictionary = {}
var producers: Dictionary = {}    # producer id -> def (economy.producers)
var upgrades: Dictionary = {}     # upgrade id -> def
var regions: Array = []
var nodes: Dictionary = {}        # node id -> def (insertion order = config order)
var node_order: Array[String] = []
var resource_ids: Array[String] = []
var meta_resource_ids: Array[String] = []
var children: Dictionary = {}     # node id -> Array of child ids
var wall_slots: Array[Vector2] = []   # all wall slot positions
var wall_slot_row: Array[int] = []    # row index of each slot
var errors: Array[String] = []


static func from_dir(dir_path: String = ConfigLoader.DEFAULT_DIR) -> GameData:
	return GameData.new(ConfigLoader.load_dir(dir_path))


func _init(cfg: Dictionary = {}) -> void:
	economy = cfg.get("economy", {})
	waves = cfg.get("waves", {})
	lens = cfg.get("lens", {})
	var en: Dictionary = cfg.get("enemies", {})
	enemies = en.get("enemies", {})
	bosses = en.get("bosses", {})
	damage_types = en.get("damage_types", {})
	var tw: Dictionary = cfg.get("towers", {})
	towers = tw.get("towers", {})
	wall = tw.get("wall", {})
	combat = tw.get("combat", {})
	abilities = tw.get("abilities", {})
	upgrades = tw.get("upgrades", {})
	var mp: Dictionary = cfg.get("map", {})
	regions = mp.get("regions", [])
	for n: Dictionary in mp.get("nodes", []):
		var id: String = str(n.get("id", ""))
		nodes[id] = n
		node_order.append(id)
		children[id] = []
	for id: String in node_order:
		for p: Variant in nodes[id].get("parents", []):
			if children.has(str(p)):
				(children[str(p)] as Array).append(id)
	producers = economy.get("producers", {})
	var res: Dictionary = economy.get("resources", {})
	for r: String in res:
		resource_ids.append(r)
		if bool(res[r].get("meta", false)):
			meta_resource_ids.append(r)
	resource_ids.sort_custom(func(a: String, b: String) -> bool:
		return int(res[a].get("order", 0)) < int(res[b].get("order", 0)))
	_build_wall()
	_validate()


func _build_wall() -> void:
	var rows: Array = wall.get("rows", [])
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		var count: int = maxi(1, int(row.get("count", 1)))
		var y0: float = float(row.get("y_min", 150.0))
		var y1: float = float(row.get("y_max", 600.0))
		var mid: int = count / 2
		for k in count:
			# middle-out order: the first towers stand in the middle of the wall
			var slot: int = mid - (k + 1) / 2 if k % 2 == 1 else mid + k / 2
			wall_slots.append(Vector2(float(row.get("x", 200.0)), y0 + (slot + 0.5) * (y1 - y0) / count))
			wall_slot_row.append(ri)


func _require(where: String, d: Dictionary, keys: Array[String]) -> void:
	for k in keys:
		if not d.has(k):
			errors.append("%s: missing required field '%s'" % [where, k])


func _validate() -> void:
	_require("economy", economy, ECON_REQ)
	_require("waves", waves, WAVES_REQ)
	_require("waves.field", waves.get("field", {}), FIELD_REQ)
	_require("lens", lens, LENS_REQ)
	_require("towers.combat", combat, COMBAT_REQ)
	if wall.get("rows", []).is_empty():
		errors.append("towers.wall.rows is empty")
	for id: String in node_order:
		var n: Dictionary = nodes[id]
		_require("node " + id, n, NODE_REQ)
		for p: Variant in n.get("parents", []):
			if not nodes.has(str(p)):
				errors.append("node %s: unknown parent %s" % [id, str(p)])
		for x: Variant in n.get("excludes", []):
			if not nodes.has(str(x)):
				errors.append("node %s: unknown excluded node %s" % [id, str(x)])
			elif not (nodes[str(x)].get("excludes", []) as Array).has(id):
				errors.append("node %s: excludes %s but not vice versa" % [id, str(x)])
		var req: Dictionary = n.get("requires", {})
		if req.has("boss") and not bosses.has(str(req["boss"])):
			errors.append("node %s: requires unknown boss %s" % [id, str(req["boss"])])
		_validate_effects("node " + id, n.get("effects", []))
		_validate_cost("node " + id, n.get("cost", {}))
	for id: String in upgrades:
		var u: Dictionary = upgrades[id]
		_require("upgrade " + id, u, UPG_REQ)
		_validate_effects("upgrade " + id, u.get("effects", []))
		_validate_cost("upgrade " + id, u.get("cost", {}))
		if not towers.has(str(u.get("tower", ""))):
			errors.append("upgrade %s: unknown tower" % id)
		for ms: Dictionary in u.get("milestones", []):
			if not ms.has("level") or not ms.has("effects") or not ms.has("name"):
				errors.append("upgrade %s: milestone needs level, name, effects" % id)
			_validate_effects("upgrade %s milestone" % id, ms.get("effects", []))
	for id: String in towers:
		var t: Dictionary = towers[id]
		_require("tower " + id, t, TOWER_REQ)
		_validate_cost("tower " + id, t.get("price", {}))
		if not PROJECTILES.has(str(t.get("projectile", ""))):
			errors.append("tower %s: unknown projectile %s" % [id, str(t.get("projectile", ""))])
		if not damage_types.has(str(t.get("dmg_type", ""))):
			errors.append("tower %s: unknown damage type" % id)
		if int(t.get("row", 0)) >= (wall.get("rows", []) as Array).size():
			errors.append("tower %s: row out of range" % id)
		for k: Variant in PROJECTILE_REQ.get(str(t.get("projectile", "")), []):
			if not t.has(str(k)):
				errors.append("tower %s: %s needs %s" % [id, str(t.get("projectile", "")), str(k)])
		for st: Dictionary in t.get("on_hit", []):
			if not STATUSES.has(str(st.get("status", ""))):
				errors.append("tower %s: unknown status" % id)
		if t.has("puddle"):
			_require("tower %s puddle" % id, t["puddle"], PUDDLE_REQ)
	for id: String in abilities:
		_require("ability " + id, abilities[id], ABILITY_REQ)
		if not ABILITY_SHAPES.has(str(abilities[id].get("shape", ""))):
			errors.append("ability %s: unknown shape" % id)
		if str(abilities[id].get("shape", "")) == "line" and not abilities[id].has("line_width"):
			errors.append("ability %s: line needs line_width" % id)
	for id: String in producers:
		_require("producer " + id, producers[id], PRODUCER_REQ)
		_validate_cost("producer %s output" % id, producers[id].get("output", {}))
	for id: String in bosses:
		if not enemies.has(str(bosses[id].get("enemy", ""))):
			errors.append("boss %s: unknown enemy" % id)
		_validate_effects("boss " + id, bosses[id].get("on_defeat", []))
	for e: String in enemies:
		var d: Dictionary = enemies[e]
		_require("enemy " + e, d, ENEMY_REQ)
		if str(d.get("role", "")) == "normal" and not d.has("pack"):
			errors.append("enemy %s: normal enemies need 'pack'" % e)
		for dt: String in d.get("resist", {}):
			if not damage_types.has(dt):
				errors.append("enemy %s: unknown damage type %s" % [e, dt])
		_validate_cost("enemy %s loot" % e, d.get("loot", {}))
		for mech: String in ENEMY_MECH_REQ:
			if d.has(mech):
				var req: Array[String] = []
				req.assign(ENEMY_MECH_REQ[mech])
				_require("enemy %s %s" % [e, mech], d[mech], req)
		if d.has("split") and not enemies.has(str(d["split"].get("type", ""))):
			errors.append("enemy %s: split into unknown enemy" % e)
		for im: Variant in d.get("immune", []):
			if not IMMUNITIES.has(str(im)):
				errors.append("enemy %s: unknown immunity %s" % [e, str(im)])
		for br: Variant in d.get("shield", {}).get("breakers", []):
			if not damage_types.has(str(br)):
				errors.append("enemy %s: unknown shield breaker %s" % [e, str(br)])
	for msg in errors:
		push_error("GameData: " + msg)


func _validate_effects(where: String, effects: Array) -> void:
	for ef: Dictionary in effects:
		var t: String = str(ef.get("type", ""))
		if not EFFECT_TYPES.has(t):
			errors.append("%s: unknown effect type '%s'" % [where, t])
			continue
		var target: String = str(ef.get("target", "all"))
		if t.begins_with("tower_") or t == "unlock_tower":
			if target != "all" and not towers.has(target):
				errors.append("%s: unknown tower target %s" % [where, target])
		if t.begins_with("enemy_") or t == "unlock_enemy":
			if target != "all" and not enemies.has(target):
				errors.append("%s: unknown enemy target %s" % [where, target])
		if t == "ability_puddle":
			for k in ["radius", "duration", "dmg_type"]:
				if not ef.has(k):
					errors.append("%s: ability_puddle needs %s" % [where, k])
		if t in ["unlock_ability", "ability_dmg_mult", "ability_status", "ability_count_add", "ability_puddle"] and not abilities.has(target):
			errors.append("%s: unknown ability %s" % [where, target])
		if t == "call_boss" and not bosses.has(target):
			errors.append("%s: unknown boss %s" % [where, target])
		if PRODUCER_EFFECTS.has(t) and not producers.has(target):
			errors.append("%s: unknown producer %s" % [where, target])
		if t == "producer_output_add" and not resource_ids.has(str(ef.get("res", ""))):
			errors.append("%s: unknown resource %s" % [where, str(ef.get("res", ""))])
		if t in ["tower_on_hit_status", "lens_status", "ability_status", "tower_zone_status"] and not STATUSES.has(str(ef.get("status", ""))):
			errors.append("%s: unknown status %s" % [where, str(ef.get("status", ""))])


func _validate_cost(where: String, cost: Dictionary) -> void:
	for r: String in cost:
		if not resource_ids.has(r):
			errors.append("%s: unknown resource %s" % [where, r])


# --- convenience ----------------------------------------------------------

func field(key: String) -> float:
	return float(waves["field"][key])


func lens_value(key: String) -> float:
	return float(lens[key])


func combat_value(key: String) -> float:
	return float(combat[key])


## Field position used when a slot index cannot be resolved (combat.fallback_slot).
func fallback_slot() -> Vector2:
	var a: Array = combat["fallback_slot"]
	return Vector2(float(a[0]), float(a[1]))


func node_effects(id: String) -> Array:
	return nodes.get(id, {}).get("effects", [])


func node_excludes(id: String) -> Array:
	return nodes.get(id, {}).get("excludes", [])


func node_kind(id: String) -> String:
	return str(nodes.get(id, {}).get("kind", ""))


func has_effect(id: String, effect_type: String) -> bool:
	for ef: Dictionary in node_effects(id):
		if str(ef.get("type", "")) == effect_type:
			return true
	return false


## i18n key helpers (keys live in i18n/strings.csv).
static func node_name_key(id: String) -> String:
	return "NODE_" + id.to_upper()


static func node_desc_key(id: String) -> String:
	return "NODE_" + id.to_upper() + "_DESC"
