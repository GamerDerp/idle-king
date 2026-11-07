class_name GameState
extends RefCounted
## All persistent game state (what a save file holds). Plain data: the rules
## live in GameCore / Battle / Mods. Round-trips through to_dict()/from_dict().
##
## Two layers:
##  - run state (this object's fields): reset by a prestige ("Великая Переплавка");
##  - meta state (`meta`): survives prestige — meta resources (печати), inventions,
##    high-water marks and lifetime statistics.
## The field (enemies, projectiles) is transient and not saved.

const FORMAT_VERSION: int = 2

# --- run state ---
var rng_seed: int = 0
var rng_state: int = 0
var time: float = 0.0                       ## game seconds of this run
var resources: Dictionary = {}              ## run res id -> float
var earned: Dictionary = {}                 ## run res id -> float earned this run
var towers: Dictionary = {}                 ## tower type -> count owned
var tower_slots: Dictionary = {}            ## tower type -> Array of wall slot indices (in purchase order)
var upgrades: Dictionary = {}               ## shop upgrade id -> level
var nodes: Dictionary = {}                  ## map node id -> level
var bosses: Dictionary = {}                 ## boss id -> {status, attempts, defeated_at}
var stats: Dictionary = {}                  ## run stats: kills, falls, by type, damage by source ...

# --- meta state (survives prestige) ---
var meta: Dictionary = {}
var meta_resources: Array[String] = []      ## resource ids stored in meta (from economy.resources[*].meta)

## --- input from the view, not saved ---
var cursor_pos: Vector2 = Vector2.ZERO      ## lens cursor in field coordinates
var cursor_active: bool = false             ## mouse is over the field


func _init() -> void:
	reset_stats()
	meta = new_meta()


static func new_meta() -> Dictionary:
	return {
		"resources": {},                    ## meta res id -> float (печати)
		"inventions": {},                   ## invention id -> level (Совет изобретателей, later)
		"high": {"max_region": 0, "boss_best": {}},   ## boss id -> fastest defeat (run seconds)
		"stats": {"kills": 0, "falls": 0, "time": 0.0, "runs": 1, "bosses": 0},
	}


func reset_stats() -> void:
	stats = {
		"kills": 0, "falls": 0, "purchases": 0,
		"kills_by_type": {}, "falls_by_type": {},
		"dmg_by_source": {},       ## "lens", "moat", "scald", "zone", "ability:<id>", "tower:<type>" -> effective damage
	}


func is_meta_res(id: String) -> bool:
	return meta_resources.has(id)


func res(id: String) -> float:
	if is_meta_res(id):
		return float(meta["resources"].get(id, 0.0))
	return float(resources.get(id, 0.0))


func add_res(id: String, amount: float) -> void:
	if is_meta_res(id):
		var mr: Dictionary = meta["resources"]
		mr[id] = Num.safe(float(mr.get(id, 0.0)) + amount)
		return
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


func add_stat_in(group: String, key: String, amount: float) -> void:
	var d: Dictionary = stats.get(group, {})
	d[key] = float(d.get(key, 0.0)) + amount
	stats[group] = d


## Counts a kill / fall in run and lifetime stats.
func count_event(kind: String, enemy_type: String) -> void:
	stats[kind] = int(stats[kind]) + 1
	add_stat_in(kind + "_by_type", enemy_type, 1.0)
	var ms: Dictionary = meta["stats"]
	ms[kind] = int(ms.get(kind, 0)) + 1


## Clears the run (prestige); meta stays. GameCore.new_run() then applies the start config.
func reset_run() -> void:
	time = 0.0
	resources = {}
	earned = {}
	towers = {}
	tower_slots = {}
	upgrades = {}
	nodes = {}
	bosses = {}
	reset_stats()
	meta["stats"]["runs"] = int(meta["stats"].get("runs", 1)) + 1


func to_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"run": {
			"seed": rng_seed,
			"rng_state": str(rng_state),
			"time": time,
			"resources": resources.duplicate(true),
			"earned": earned.duplicate(true),
			"towers": towers.duplicate(true),
			"tower_slots": tower_slots.duplicate(true),
			"upgrades": upgrades.duplicate(true),
			"nodes": nodes.duplicate(true),
			"bosses": bosses.duplicate(true),
			"stats": stats.duplicate(true),
		},
		"meta": meta.duplicate(true),
	}


## Restores from a dict produced by to_dict() (also after a JSON round trip,
## where ints come back as floats).
static func from_dict(d: Dictionary, meta_res: Array[String] = []) -> GameState:
	var s := GameState.new()
	s.meta_resources = meta_res.duplicate()
	var r: Dictionary = d.get("run", {})
	s.rng_seed = int(r.get("seed", 0))
	s.rng_state = str(r.get("rng_state", "0")).to_int()
	s.time = float(r.get("time", 0.0))
	s.resources = _floats(r.get("resources", {}))
	s.earned = _floats(r.get("earned", {}))
	s.towers = _ints(r.get("towers", {}))
	s.upgrades = _ints(r.get("upgrades", {}))
	s.nodes = _ints(r.get("nodes", {}))
	var ts: Dictionary = r.get("tower_slots", {})
	for t: String in ts:
		var arr: Array = []
		for v: Variant in ts[t]:
			arr.append(int(v))
		s.tower_slots[t] = arr
	s.bosses = (r.get("bosses", {}) as Dictionary).duplicate(true)
	for b: String in s.bosses:
		s.bosses[b]["attempts"] = int(s.bosses[b].get("attempts", 0))
	var st: Dictionary = r.get("stats", {})
	if not st.is_empty():
		s.stats = st.duplicate(true)
		for k: String in ["kills", "falls", "purchases"]:
			s.stats[k] = int(st.get(k, 0))
	var m: Dictionary = d.get("meta", {})
	if not m.is_empty():
		s.meta = new_meta()
		for k: String in m:
			s.meta[k] = (m[k] as Dictionary).duplicate(true) if m[k] is Dictionary else m[k]
		for k: String in ["kills", "falls", "runs", "bosses"]:
			s.meta["stats"][k] = int(s.meta["stats"].get(k, 0))
		s.meta["high"]["max_region"] = int(s.meta["high"].get("max_region", 0))
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
