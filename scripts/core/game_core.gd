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

## Rolling income per second over the last economy.income_window seconds, res id -> float.
var income: Dictionary = {}
var _income_samples: Array = []     # [time, earned dict]
var _income_timer: float = 0.0
var _novelty_cache: Dictionary = {} # purchase id -> Array of new behaviour keys (cleared on change)


static func create(seed_value: int = -1, game_data: GameData = null) -> GameCore:
	var d: GameData = game_data if game_data != null else GameData.from_dir()
	var c := GameCore.new(d)
	c.new_game(seed_value)
	return c


func _init(game_data: GameData) -> void:
	data = game_data
	state = GameState.new()
	state.meta_resources = data.meta_resource_ids.duplicate()


## Fresh game (new meta too). seed_value < 0 -> economy.seed.
func new_game(seed_value: int = -1) -> void:
	state = GameState.new()
	state.meta_resources = data.meta_resource_ids.duplicate()
	state.rng_seed = seed_value if seed_value >= 0 else int(data.economy["seed"])
	_apply_start()


## New run after a prestige: run state from economy.start, meta kept.
func new_run() -> void:
	state.reset_run()
	_apply_start()


func _apply_start() -> void:
	var start: Dictionary = data.economy["start"]
	for r: String in data.resource_ids:
		if not state.is_meta_res(r):
			state.resources[r] = 0.0
			state.earned[r] = 0.0
	var sr: Dictionary = start["resources"]
	for r: String in sr:
		state.resources[r] = float(sr[r])
	var st: Dictionary = start["towers"]
	for t: String in st:
		state.towers[t] = int(st[t])
	rng.seed = state.rng_seed
	state.rng_state = rng.state
	_rebuild()


## Restores a saved state (field starts empty).
func load_state(d: Dictionary) -> void:
	state = GameState.from_dict(d, data.meta_resource_ids)
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
	_novelty_cache.clear()


func recompute() -> void:
	mods = Mods.compute(data, state)
	battle.set_mods(mods)
	_novelty_cache.clear()


func set_cursor(pos: Vector2, active: bool) -> void:
	state.cursor_pos = pos
	state.cursor_active = active


func tick(dt: float) -> void:
	if is_nan(dt) or dt <= 0.0:
		return
	var left: float = minf(dt, float(data.economy["max_tick"]))
	while left > 1e-9:
		var step: float = minf(left, max_step)
		left -= step
		state.time += step
		state.meta["stats"]["time"] = float(state.meta["stats"]["time"]) + step
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
	var window: float = float(data.economy["income_window"])
	while _income_samples.size() > 2 and state.time - float(_income_samples[1][0]) >= window:
		_income_samples.pop_front()
	var old: Array = _income_samples[0]
	var span: float = maxf(0.001, state.time - float(old[0]))
	for r: String in state.earned:
		income[r] = (float(state.earned[r]) - float((old[1] as Dictionary).get(r, 0.0))) / span


# --- shop -------------------------------------------------------------------

## Every purchase id currently visible to the player (not maxed, region open,
## parents bought, not excluded by a choice, tower type unlocked).
func offer_ids() -> Array[String]:
	var out: Array[String] = []
	for t: String in mods.unlocked_towers:
		out.append("tower:" + t)
	for u: String in data.upgrades:
		var ud: Dictionary = data.upgrades[u]
		if mods.unlocked_towers.has(str(ud["tower"])) and state.upgrade_level(u) < int(ud["max"]):
			out.append("upg:" + u)
	for n: String in data.node_order:
		if node_status(n) == "available":
			out.append("node:" + n)
	return out


## "hidden" (region closed / required boss not beaten), "locked" (no parent
## bought), "excluded" (the other branch of a choice was taken), "available", "maxed".
func node_status(id: String) -> String:
	var n: Dictionary = data.nodes.get(id, {})
	if n.is_empty() or not mods.is_region_unlocked(int(n["region"])):
		return "hidden"
	var req: Dictionary = n.get("requires", {})
	if req.has("boss") and state.boss_status(str(req["boss"])) != "defeated":
		return "hidden"
	if state.node_level(id) >= int(n["max"]):
		return "maxed"
	for x: Variant in n.get("excludes", []):
		if state.node_level(str(x)) > 0:
			return "excluded"
	var parents: Array = n["parents"]
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
			if not data.towers.has(p[1]):
				return {}
			base = data.towers[p[1]]["price"]
			growth = float(data.towers[p[1]]["growth"])
		"upg":
			if not data.upgrades.has(p[1]):
				return {}
			base = data.upgrades[p[1]]["cost"]
			growth = float(data.upgrades[p[1]]["growth"])
		"node":
			if not data.nodes.has(p[1]):
				return {}
			base = data.nodes[p[1]]["cost"]
			growth = float(data.nodes[p[1]]["growth"])
	return price_formula(base, growth, level_of(id), float(data.economy["price_ceil_below"]))


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


## Visible, not maxed, not excluded and (for towers) under the limit — affordability not checked.
func is_available(id: String) -> bool:
	var p: PackedStringArray = split_id(id)
	match p[0]:
		"tower":
			return mods.unlocked_towers.has(p[1]) and state.tower_count(p[1]) < max_of(id)
		"upg":
			var ud: Dictionary = data.upgrades.get(p[1], {})
			return not ud.is_empty() and mods.unlocked_towers.has(str(ud["tower"])) \
				and state.upgrade_level(p[1]) < int(ud["max"])
		"node":
			return node_status(p[1]) == "available"
	return false


func can_buy(id: String) -> bool:
	return is_available(id) and can_afford(price(id))


## Derived stats as they would be after buying one more level of `id`
## (for "было → станет" in the shop: compare core.mods with the result).
func preview_mods(id: String) -> Mods:
	# only what Mods.compute reads: levels, tower counts, boss statuses
	var st := GameState.new()
	st.nodes = state.nodes.duplicate()
	st.upgrades = state.upgrades.duplicate()
	st.towers = state.towers.duplicate()
	st.bosses = state.bosses
	var p: PackedStringArray = split_id(id)
	match p[0]:
		"tower":
			st.towers[p[1]] = st.tower_count(p[1]) + 1
		"upg":
			st.upgrades[p[1]] = st.upgrade_level(p[1]) + 1
		"node":
			st.nodes[p[1]] = st.node_level(p[1]) + 1
	return Mods.compute(data, st)


## What new on-screen behaviour the next level of `id` brings: keys of
## Mods.behaviours() it adds (new enemy, tower, pierce/splash from 0, status,
## mechanism, producer...), plus "boss:<id>" for a boss call. Empty = numbers only.
## Honest: a new look (tier:*) or an opened map region (region:*) alone is not new
## behaviour — those keys are only in changes_of().
func novelty_of(id: String) -> Array:
	if _novelty_cache.has(id):
		return _novelty_cache[id]
	var out: Array = []
	for k: String in changes_of(id):
		if not Mods.is_cosmetic_key(k):
			out.append(k)
	_novelty_cache[id] = out
	return out


## Every behaviour key the next level of `id` adds, including cosmetic ones (tier:*, region:*).
func changes_of(id: String) -> Array:
	var out: Array = []
	var now: Dictionary = mods.behaviours()
	var after: Dictionary = preview_mods(id).behaviours()
	for k: String in after:
		if not now.has(k):
			out.append(k)
	var p: PackedStringArray = split_id(id)
	if p[0] == "node" and state.node_level(p[1]) == 0:
		for ef: Dictionary in data.node_effects(p[1]):
			if str(ef["type"]) == "call_boss":
				out.append("boss:" + str(ef["target"]))
	return out


## Next behaviour milestone of a shop upgrade (for shop cards: "at level 6: Разрывные пули"):
## {level, levels_left, name, desc, novelty: [behaviour keys it adds]} or {} if none left.
func next_milestone(upgrade_id: String) -> Dictionary:
	var ud: Dictionary = data.upgrades.get(upgrade_id, {})
	var lvl: int = state.upgrade_level(upgrade_id)
	var best: Dictionary = {}
	for ms: Dictionary in ud.get("milestones", []):
		var at: int = int(ms["level"])
		if at > lvl and at <= int(ud["max"]) and (best.is_empty() or at < int(best["level"])):
			best = ms
	if best.is_empty():
		return {}
	var at_lvl: int = int(best["level"])
	var st := GameState.new()
	st.nodes = state.nodes.duplicate()
	st.upgrades = state.upgrades.duplicate()
	st.towers = state.towers.duplicate()
	st.bosses = state.bosses
	st.upgrades[upgrade_id] = at_lvl
	var nov: Array = []
	var now: Dictionary = mods.behaviours()
	for k: String in Mods.compute(data, st).behaviours():
		if not now.has(k) and not Mods.is_cosmetic_key(k):
			nov.append(k)
	return {"level": at_lvl, "levels_left": at_lvl - lvl, "name": str(best["name"]),
		"desc": str(best["name"]) + "_DESC", "novelty": nov}


## Producer cycle progress 0..1 (Угольная шахта: the view fills a wheel/cart with it).
func producer_progress(pid: String) -> float:
	return battle.producer_progress(pid)


## "novel" (something new on screen), "tower" (one more tower of an owned type), "numeric".
func purchase_category(id: String) -> String:
	if not novelty_of(id).is_empty():
		return "novel"
	if id.begins_with("tower:"):
		return "tower"
	return "numeric"


## Visual tier of a tower type (1 = iron, 2 = brass, 3 = gilded...), raised by shop milestones.
func tower_tier(t: String) -> int:
	return int(mods.tower_stats.get(t, {}).get("tier", 1))


## Buys one level. Emits purchased (+ unlocked / tower_built / milestone / tier_up /
## choice_made / boss events).
func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var cost: Dictionary = price(id)
	var before: Dictionary = mods.behaviours()
	var tiers_before: Dictionary = {}
	for t: String in mods.tower_stats:
		tiers_before[t] = tower_tier(t)
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
		_emit({"type": "tower_built", "tower": p[1], "index": new_level - 1, "pos": battle.tower_pos(p[1], new_level - 1)})
	if p[0] == "upg":
		for ms: Dictionary in data.upgrades[p[1]].get("milestones", []):
			if int(ms["level"]) == new_level:
				_emit({"type": "milestone", "upgrade": p[1], "tower": str(data.upgrades[p[1]]["tower"]),
					"name": str(ms["name"]), "level": new_level})
	if p[0] == "node":
		var ex: Array = data.node_excludes(p[1])
		if not ex.is_empty() and new_level == 1:
			_emit({"type": "choice_made", "id": p[1], "excluded": ex.duplicate()})
		for ef: Dictionary in data.node_effects(p[1]):
			_on_node_effect(ef)
		var reg: int = int(data.nodes[p[1]]["region"])
		var high: Dictionary = state.meta["high"]
		for r: int in mods.regions:
			if r > int(high["max_region"]):
				high["max_region"] = r
		high["max_region"] = maxi(int(high["max_region"]), reg)
	var after: Dictionary = mods.behaviours()
	for k: String in after:
		if not before.has(k):
			_emit({"type": "unlocked", "what": "behavior", "id": k})
	for t: String in mods.tower_stats:
		if tower_tier(t) > int(tiers_before.get(t, 1)):
			_emit({"type": "tier_up", "tower": t, "tier": tower_tier(t)})
	return true


func _on_node_effect(ef: Dictionary) -> void:
	match str(ef["type"]):
		"unlock_enemy":
			_emit({"type": "unlocked", "what": "enemy", "id": str(ef["target"])})
		"unlock_tower":
			_emit({"type": "unlocked", "what": "tower", "id": str(ef["target"])})
		"unlock_producer":
			_emit({"type": "unlocked", "what": "producer", "id": str(ef["target"])})
		"unlock_region":
			_emit({"type": "unlocked", "what": "region", "id": str(int(float(ef["value"])))})
		"call_boss":
			call_boss(str(ef["target"]), true)


# --- goal bar -----------------------------------------------------------------

## The next goal for the goal bar: {id, text_key, args, progress 0..1, cost}.
## Boss fight > boss retry > cheapest node that brings something new >
## cheapest node at all. text_key are i18n keys (GOAL_*), args are i18n keys too.
func next_goal() -> Dictionary:
	var ab: String = active_boss()
	if ab != "":
		var be: Battle.Enemy = battle.boss_enemy
		return {"id": "boss:" + ab, "text_key": "GOAL_BOSS_FIGHT", "args": [str(data.bosses[ab]["name"])],
			"progress": clampf(1.0 - be.hp / be.max_hp, 0.0, 1.0), "cost": {}}
	for b: String in data.bosses:
		if can_call_boss(b):
			return {"id": "boss:" + b, "text_key": "GOAL_BOSS_RETRY", "args": [str(data.bosses[b]["name"])],
				"progress": 1.0, "cost": {}}
	var best: String = ""
	var best_cost: float = INF
	var any: String = ""
	var any_cost: float = INF
	for id in offer_ids():
		if not id.begins_with("node:"):
			continue
		var c: float = _cost_sum(price(id))
		if c < any_cost:
			any_cost = c
			any = id
		if c < best_cost and not novelty_of(id).is_empty():
			best_cost = c
			best = id
	var pick: String = best if best != "" else any
	if pick == "":
		return {"id": "", "text_key": "GOAL_NONE", "args": [], "progress": 1.0, "cost": {}}
	var cost: Dictionary = price(pick)
	var prog: float = 1.0
	for r: String in cost:
		if float(cost[r]) > 0.0:
			prog = minf(prog, state.res(r) / float(cost[r]))
	var node_id: String = pick.substr(5)
	return {"id": pick, "text_key": "GOAL_NODE", "args": [GameData.node_name_key(node_id)],
		"progress": clampf(prog, 0.0, 1.0), "cost": cost}


static func _cost_sum(cost: Dictionary) -> float:
	var s: float = 0.0
	for r: String in cost:
		s += float(cost[r])
	return s


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
		var high: Dictionary = state.meta["high"]
		var best: Dictionary = high["boss_best"]
		best[id] = minf(float(best.get(id, INF)), state.time)
		state.meta["stats"]["bosses"] = int(state.meta["stats"]["bosses"]) + 1
		var before: Dictionary = mods.behaviours()
		recompute()
		_emit({"type": "boss_reward", "boss": id, "loot": reward})
		for ef: Dictionary in data.bosses[id].get("on_defeat", []):
			_on_node_effect(ef)
		for r: int in mods.regions:
			high["max_region"] = maxi(int(high["max_region"]), r)
		for k: String in mods.behaviours():
			if not before.has(k):
				_emit({"type": "unlocked", "what": "behavior", "id": k})
	else:
		state.bosses[id] = b
