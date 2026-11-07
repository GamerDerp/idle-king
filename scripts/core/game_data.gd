class_name GameData
extends RefCounted
## Read-only game content parsed from config/*.json (economy, waves, enemies,
## towers, lens, map). Built from the raw dictionaries returned by
## ConfigLoader.load_dir(), so it works in the game, tests and headless sim.

## Effect types the core understands (see Mods.apply_effect and docs/CORE.md).
const EFFECT_TYPES: Array[String] = [
	"unlock_enemy", "enemy_spawn_add", "enemy_loot_mult", "enemy_bp_mult", "enemy_hp_mult",
	"unlock_tower", "tower_limit_add", "tower_dmg_mult", "tower_reload_mult", "tower_pierce_add",
	"tower_splash_add", "tower_crit_chance_add", "tower_crit_mult_add", "tower_range_add",
	"tower_on_hit_status",
	"lens_radius", "lens_dmg", "lens_rate", "lens_auto_mult", "lens_seek",
	"global_dmg_mult", "global_loot_mult", "global_bp_mult",
	"moat_damage", "call_boss", "unlock_region",
]

## Effect types that put something new on screen / change behaviour (pacing "novelty").
const NOVEL_EFFECTS: Array[String] = [
	"unlock_enemy", "unlock_tower", "tower_on_hit_status", "lens_seek", "moat_damage",
	"call_boss", "unlock_region", "tower_pierce_add", "tower_splash_add",
]

var economy: Dictionary = {}
var waves: Dictionary = {}
var lens: Dictionary = {}
var enemies: Dictionary = {}      # type -> def
var bosses: Dictionary = {}       # boss id -> def
var damage_types: Dictionary = {}
var towers: Dictionary = {}       # type -> def
var wall: Dictionary = {}
var upgrades: Dictionary = {}     # upgrade id -> def
var regions: Array = []
var nodes: Dictionary = {}        # node id -> def (insertion order = config order)
var node_order: Array[String] = []
var resource_ids: Array[String] = []
var children: Dictionary = {}     # node id -> Array of child ids
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
	var res: Dictionary = economy.get("resources", {})
	for r: String in res:
		resource_ids.append(r)
	resource_ids.sort_custom(func(a: String, b: String) -> bool:
		return int(res[a].get("order", 0)) < int(res[b].get("order", 0)))
	_validate()


func _validate() -> void:
	for id: String in node_order:
		var n: Dictionary = nodes[id]
		for p: Variant in n.get("parents", []):
			if not nodes.has(str(p)):
				errors.append("node %s: unknown parent %s" % [id, str(p)])
		_validate_effects("node " + id, n.get("effects", []))
		_validate_cost("node " + id, n.get("cost", {}))
	for id: String in upgrades:
		_validate_effects("upgrade " + id, upgrades[id].get("effects", []))
		_validate_cost("upgrade " + id, upgrades[id].get("cost", {}))
		if not towers.has(str(upgrades[id].get("tower", ""))):
			errors.append("upgrade %s: unknown tower" % id)
	for id: String in towers:
		_validate_cost("tower " + id, towers[id].get("price", {}))
	for id: String in bosses:
		if not enemies.has(str(bosses[id].get("enemy", ""))):
			errors.append("boss %s: unknown enemy" % id)
		_validate_effects("boss " + id, bosses[id].get("on_defeat", []))
	for e: String in enemies:
		for dt: String in enemies[e].get("resist", {}):
			if not damage_types.has(dt):
				errors.append("enemy %s: unknown damage type %s" % [e, dt])
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
		if t == "call_boss" and not bosses.has(target):
			errors.append("%s: unknown boss %s" % [where, target])


func _validate_cost(where: String, cost: Dictionary) -> void:
	for r: String in cost:
		if not resource_ids.has(r):
			errors.append("%s: unknown resource %s" % [where, r])


# --- convenience ----------------------------------------------------------

func field(key: String, default: float = 0.0) -> float:
	return float(waves.get("field", {}).get(key, default))


func lens_value(key: String, default: float = 0.0) -> float:
	return float(lens.get(key, default))


func node_effects(id: String) -> Array:
	return nodes.get(id, {}).get("effects", [])


func is_novel_node(id: String) -> bool:
	for ef: Dictionary in node_effects(id):
		if NOVEL_EFFECTS.has(str(ef.get("type", ""))):
			return true
	return false


func node_kind(id: String) -> String:
	return str(nodes.get(id, {}).get("kind", ""))


## i18n key helpers (keys live in i18n/strings.csv).
static func node_name_key(id: String) -> String:
	return "NODE_" + id.to_upper()


static func node_desc_key(id: String) -> String:
	return "NODE_" + id.to_upper() + "_DESC"
