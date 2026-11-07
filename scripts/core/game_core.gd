class_name GameCore
extends RefCounted
## Facade of the game logic: owns GameData (content), GameState (save),
## Mods (derived stats) and Battle (field). The view and the headless sim use
## only this API. See docs/CORE.md.
##
##   var core := GameCore.create()           # new game from res://config
##   core.set_cursor(mouse_pos, over_field)  # every frame
##   core.tick(delta)                        # any dt; split into steps <= max_step
##   for ev in core.drain_events(): ...      # view feedback
##   core.buy("node:r0_horn")                # purchases: tower:<t>, upg:<id>, node:<id>

var data: GameData
var state: GameState
var mods: Mods
var battle: Battle
var rng := RandomNumberGenerator.new()
var events: Array = []
var max_step: float = 0.1
## When false no events are recorded (headless sim): cheaper.
var emit_events: bool = true:
	set(v):
		emit_events = v
		if battle != null:
			battle.emit = v

## Rolling income per second over the last `income_window` seconds, res id -> float.
var income: Dictionary = {}
var income_window: float = 10.0
var _income_samples: Array = []     # [time, earned dict]
var _income_timer: float = 0.0


static func create(seed_value: int = -1, game_data: GameData = null) -> GameCore:
	var d: GameData = game_data if game_data != null else GameData.from_dir()
	var c := GameCore.new(d)
	c.new_game(seed_value)
	return c


func _init(game_data: GameData) -> void:
	data = game_data
	state = GameState.new()


## Fresh state from economy.start. seed_value < 0 -> economy.seed.
func new_game(seed_value: int = -1) -> void:
	state = GameState.new()
	var start: Dictionary = data.economy.get("start", {})
	state.rng_seed = seed_value if seed_value >= 0 else int(data.economy.get("seed", 1))
	for r: String in data.resource_ids:
		state.resources[r] = 0.0
		state.earned[r] = 0.0
	var sr: Dictionary = start.get("resources", {})
	for r: String in sr:
		state.resources[r] = float(sr[r])
	var st: Dictionary = start.get("towers", {})
	for t: String in st:
		state.towers[t] = int(st[t])
	rng.seed = state.rng_seed
	state.rng_state = rng.state
	_rebuild()


## Restores a saved state (field starts empty).
func load_state(d: Dictionary) -> void:
	state = GameState.from_dict(d)
	rng.seed = state.rng_seed
	rng.state = state.rng_state
	_rebuild()


func save_state() -> Dictionary:
	state.rng_state = rng.state
	return state.to_dict()


func _rebuild() -> void:
	mods = Mods.compute(data, state)
	battle = Battle.new(data, state, mods, rng)
	battle.events = events
	battle.emit = emit_events
	_income_samples = [[state.time, state.earned.duplicate()]]
	income = {}


func recompute() -> void:
	mods = Mods.compute(data, state)
	battle.set_mods(mods)


func set_cursor(pos: Vector2, active: bool) -> void:
	state.cursor_pos = pos
	state.cursor_active = active


func tick(dt: float) -> void:
	if is_nan(dt) or dt <= 0.0:
		return
	var left: float = minf(dt, 3600.0)
	while left > 1e-9:
		var step: float = minf(left, max_step)
		left -= step
		state.time += step
		battle.tick(step)
		if battle.boss_outcome != "":
			var outcome: String = battle.boss_outcome
			battle.boss_outcome = ""
			_on_boss_outcome(battle.boss_id, outcome)
		_track_income(step)


func drain_events() -> Array:
	var out: Array = events.duplicate()
	events.clear()
	return out


func _emit(ev: Dictionary) -> void:
	if emit_events:
		events.append(ev)


func _track_income(step: float) -> void:
	_income_timer += step
	if _income_timer < 1.0:
		return
	_income_timer = 0.0
	_income_samples.append([state.time, state.earned.duplicate()])
	while _income_samples.size() > 2 and state.time - float(_income_samples[1][0]) >= income_window:
		_income_samples.pop_front()
	var old: Array = _income_samples[0]
	var span: float = maxf(0.001, state.time - float(old[0]))
	for r: String in state.earned:
		income[r] = (float(state.earned[r]) - float((old[1] as Dictionary).get(r, 0.0))) / span


# --- shop -------------------------------------------------------------------

## Every purchase id currently visible to the player (not maxed, region open,
## parents bought, tower type unlocked).
func offer_ids() -> Array[String]:
	var out: Array[String] = []
	for t: String in mods.unlocked_towers:
		out.append("tower:" + t)
	for u: String in data.upgrades:
		var ud: Dictionary = data.upgrades[u]
		if mods.unlocked_towers.has(str(ud.get("tower", ""))) and state.upgrade_level(u) < int(ud.get("max", 1)):
			out.append("upg:" + u)
	for n: String in data.node_order:
		if node_status(n) == "available":
			out.append("node:" + n)
	return out


## "hidden" (region closed), "locked" (no parent bought), "available", "maxed".
func node_status(id: String) -> String:
	var n: Dictionary = data.nodes.get(id, {})
	if n.is_empty() or not mods.is_region_unlocked(int(n.get("region", 0))):
		return "hidden"
	if state.node_level(id) >= int(n.get("max", 1)):
		return "maxed"
	var parents: Array = n.get("parents", [])
	if parents.is_empty():
		return "available"
	for p: Variant in parents:
		if state.node_level(str(p)) > 0:
			return "available"
	return "locked"


static func split_id(id: String) -> PackedStringArray:
	var parts: PackedStringArray = id.split(":", true, 1)
	if parts.size() < 2:
		return PackedStringArray(["", id])
	return parts


## Current level (towers: count owned) and max (towers: current limit).
func level_of(id: String) -> int:
	var p: PackedStringArray = split_id(id)
	match p[0]:
		"tower":
			return state.tower_count(p[1])
		"upg":
			return state.upgrade_level(p[1])
		"node":
			return state.node_level(p[1])
	return 0


func max_of(id: String) -> int:
	var p: PackedStringArray = split_id(id)
	match p[0]:
		"tower":
			return int(mods.tower_stats.get(p[1], {}).get("limit", 0))
		"upg":
			return int(data.upgrades.get(p[1], {}).get("max", 1))
		"node":
			return int(data.nodes.get(p[1], {}).get("max", 1))
	return 0


## Price of the next level: {res id: amount}. base * (1 + growth)^level, rounded up.
func price(id: String) -> Dictionary:
	var p: PackedStringArray = split_id(id)
	var base: Dictionary = {}
	var growth: float = 0.0
	match p[0]:
		"tower":
			var td: Dictionary = data.towers.get(p[1], {})
			base = td.get("price", {})
			growth = float(td.get("growth", 0.0))
		"upg":
			var ud: Dictionary = data.upgrades.get(p[1], {})
			base = ud.get("cost", {})
			growth = float(ud.get("growth", 0.0))
		"node":
			var nd: Dictionary = data.nodes.get(p[1], {})
			base = nd.get("cost", {})
			growth = float(nd.get("growth", 0.0))
	return price_formula(base, growth, level_of(id), float(data.economy.get("price_ceil_below", 1e15)))


static func price_formula(base: Dictionary, growth: float, level: int, ceil_below: float = 1e15) -> Dictionary:
	var out: Dictionary = {}
	var k: float = Num.pow_safe(1.0 + growth, float(level))
	for r: String in base:
		var v: float = Num.safe(float(base[r]) * k)
		out[r] = ceilf(v - 1e-9) if v < ceil_below else v
	return out


func can_afford(cost: Dictionary) -> bool:
	for r: String in cost:
		if state.res(r) + 1e-9 < float(cost[r]):
			return false
	return true


## Visible, not maxed and (for towers) under the limit — affordability not checked.
func is_available(id: String) -> bool:
	var p: PackedStringArray = split_id(id)
	match p[0]:
		"tower":
			return mods.unlocked_towers.has(p[1]) and state.tower_count(p[1]) < max_of(id)
		"upg":
			var ud: Dictionary = data.upgrades.get(p[1], {})
			return not ud.is_empty() and mods.unlocked_towers.has(str(ud.get("tower", ""))) \
				and state.upgrade_level(p[1]) < int(ud.get("max", 1))
		"node":
			return node_status(p[1]) == "available"
	return false


func can_buy(id: String) -> bool:
	return is_available(id) and can_afford(price(id))


## Derived stats as they would be after buying one more level of `id`
## (for "было → станет" in the shop: compare core.mods with the result).
func preview_mods(id: String) -> Mods:
	var st: GameState = GameState.from_dict(state.to_dict())
	var p: PackedStringArray = split_id(id)
	match p[0]:
		"tower":
			st.towers[p[1]] = st.tower_count(p[1]) + 1
		"upg":
			st.upgrades[p[1]] = st.upgrade_level(p[1]) + 1
		"node":
			st.nodes[p[1]] = st.node_level(p[1]) + 1
	return Mods.compute(data, st)


## Buys one level. Emits purchased (+ unlocked / tower_built / boss events).
func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var cost: Dictionary = price(id)
	for r: String in cost:
		state.add_res(r, -float(cost[r]))
	var p: PackedStringArray = split_id(id)
	var new_level: int = 0
	match p[0]:
		"tower":
			state.towers[p[1]] = state.tower_count(p[1]) + 1
			new_level = state.tower_count(p[1])
		"upg":
			state.upgrades[p[1]] = state.upgrade_level(p[1]) + 1
			new_level = state.upgrade_level(p[1])
		"node":
			state.nodes[p[1]] = state.node_level(p[1]) + 1
			new_level = state.node_level(p[1])
	state.stats["purchases"] = int(state.stats["purchases"]) + 1
	recompute()
	_emit({"type": "purchased", "id": id, "level": new_level, "price": cost})
	if p[0] == "tower":
		_emit({"type": "tower_built", "tower": p[1], "index": new_level - 1, "pos": battle.tower_slot(p[1], new_level - 1)})
	if p[0] == "node":
		for ef: Dictionary in data.node_effects(p[1]):
			_on_node_effect(ef, new_level)
	return true


func _on_node_effect(ef: Dictionary, level: int) -> void:
	var t: String = str(ef.get("type", ""))
	match t:
		"unlock_enemy":
			_emit({"type": "unlocked", "what": "enemy", "id": str(ef.get("target", ""))})
		"unlock_tower":
			_emit({"type": "unlocked", "what": "tower", "id": str(ef.get("target", ""))})
		"unlock_region":
			_emit({"type": "unlocked", "what": "region", "id": str(int(float(ef.get("value", 0))))})
		"call_boss":
			call_boss(str(ef.get("target", "")), true)
		_:
			if level == 1 and GameData.NOVEL_EFFECTS.has(t):
				_emit({"type": "unlocked", "what": "behavior", "id": t})


# --- bosses -------------------------------------------------------------------

## Calls a boss: allowed after its map node is bought, while it is not on the
## field and not defeated ("called_first" is used by the node purchase itself).
func call_boss(id: String, called_first: bool = false) -> bool:
	if not data.bosses.has(id):
		return false
	var status: String = state.boss_status(id)
	if status == "defeated" or status == "active":
		return false
	if status == "none" and not called_first:
		return false
	if not battle.start_boss(id):
		return false
	var b: Dictionary = state.bosses.get(id, {"status": "none", "attempts": 0})
	b["status"] = "active"
	b["attempts"] = int(b.get("attempts", 0)) + 1
	state.bosses[id] = b
	return true


func can_call_boss(id: String) -> bool:
	return state.boss_status(id) == "retreated" and battle.boss_enemy == null


## Boss currently on the field ("" if none).
func active_boss() -> String:
	return battle.boss_id if battle.boss_enemy != null else ""


func _on_boss_outcome(id: String, outcome: String) -> void:
	var b: Dictionary = state.bosses.get(id, {"attempts": 1})
	b["status"] = outcome
	if outcome == "defeated":
		b["defeated_at"] = state.time
		var reward: Dictionary = data.bosses[id].get("reward", {})
		for r: String in reward:
			state.add_res(r, float(reward[r]))
		state.bosses[id] = b
		recompute()
		_emit({"type": "boss_reward", "boss": id, "loot": reward})
		for ef: Dictionary in data.bosses[id].get("on_defeat", []):
			_on_node_effect(ef, 1)
	else:
		state.bosses[id] = b
