class_name GameState
extends RefCounted
## All persistent game state (what a save file holds). Plain data: the rules
## live in GameCore / Battle / Mods. Round-trips through to_dict()/from_dict().
## The field (enemies, projectiles) is transient and not saved.

const FORMAT_VERSION: int = 1

var rng_seed: int = 0
var rng_state: int = 0
var time: float = 0.0                       ## total game seconds simulated
var resources: Dictionary = {}              ## res id -> float
var earned: Dictionary = {}                 ## res id -> float, total ever earned
var towers: Dictionary = {}                 ## tower type -> count owned
var upgrades: Dictionary = {}               ## shop upgrade id -> level
var nodes: Dictionary = {}                  ## map node id -> level
var bosses: Dictionary = {}                 ## boss id -> {status, attempts, defeated_at}
var stats: Dictionary = {}                  ## kills, falls, by type, damage by source ...

## --- input from the view, not saved ---
var cursor_pos: Vector2 = Vector2.ZERO      ## lens cursor in field coordinates
var cursor_active: bool = false             ## mouse is over the field


func _init() -> void:
	reset_stats()


func reset_stats() -> void:
	stats = {
		"kills": 0, "falls": 0, "purchases": 0,
		"kills_by_type": {}, "falls_by_type": {},
		"dmg_by_source": {},       ## "lens", "moat", "scald", "tower:<type>" -> effective damage
	}


func res(id: String) -> float:
	return float(resources.get(id, 0.0))


func add_res(id: String, amount: float) -> void:
	resources[id] = Num.safe(res(id) + amount)
	if amount > 0.0:
		earned[id] = Num.safe(float(earned.get(id, 0.0)) + amount)


func tower_count(t: String) -> int:
	return int(towers.get(t, 0))


func node_level(id: String) -> int:
	return int(nodes.get(id, 0))


func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func boss_status(id: String) -> String:
	return str(bosses.get(id, {}).get("status", "none"))


func add_stat(key: String, amount: float) -> void:
	stats[key] = float(stats.get(key, 0.0)) + amount


func add_stat_in(group: String, key: String, amount: float) -> void:
	var d: Dictionary = stats.get(group, {})
	d[key] = float(d.get(key, 0.0)) + amount
	stats[group] = d


func to_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"seed": rng_seed,
		"rng_state": str(rng_state),
		"time": time,
		"resources": resources.duplicate(true),
		"earned": earned.duplicate(true),
		"towers": towers.duplicate(true),
		"upgrades": upgrades.duplicate(true),
		"nodes": nodes.duplicate(true),
		"bosses": bosses.duplicate(true),
		"stats": stats.duplicate(true),
	}


## Restores from a dict produced by to_dict() (also after a JSON round trip,
## where ints come back as floats).
static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.rng_seed = int(d.get("seed", 0))
	s.rng_state = str(d.get("rng_state", "0")).to_int()
	s.time = float(d.get("time", 0.0))
	s.resources = _floats(d.get("resources", {}))
	s.earned = _floats(d.get("earned", {}))
	s.towers = _ints(d.get("towers", {}))
	s.upgrades = _ints(d.get("upgrades", {}))
	s.nodes = _ints(d.get("nodes", {}))
	s.bosses = (d.get("bosses", {}) as Dictionary).duplicate(true)
	for b: String in s.bosses:
		s.bosses[b]["attempts"] = int(s.bosses[b].get("attempts", 0))
	var st: Dictionary = d.get("stats", {})
	if not st.is_empty():
		s.stats = st.duplicate(true)
		s.stats["kills"] = int(st.get("kills", 0))
		s.stats["falls"] = int(st.get("falls", 0))
		s.stats["purchases"] = int(st.get("purchases", 0))
	return s


static func _floats(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in src:
		out[k] = Num.safe(float(src[k]))
	return out


static func _ints(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in src:
		out[k] = int(src[k])
	return out
