class_name SimBot
extends RefCounted
## A "reasonable player" bot that drives a GameCore: used by the headless
## balance sim (tools/sim), tests and the debug view's --bot autoplay.
##
## Modes:
##   active — a lazy player who keeps the lens over the densest group, reacting
##            every `reaction` s with some aim noise;
##   real   — like active, but the mouse leaves the field for 1.5–3 s on every
##            purchase (to click in the shop panel) — the lens goes auto meanwhile;
##   idle   — never touches the field (lens always in auto mode).
## Purchases every `think_interval` s:
##   1. re-call a retreated boss after `recall_delay` s;
##   2. map nodes: save for the cheapest "priority" node (new enemy / tower /
##      region / boss / boss reward) if affordable within `save_horizon` s; else the
##      node it wants most (novelty looks `novelty_discount` cheaper) if affordable
##      within `wish_horizon` s; else the cheapest affordable. "Bait" nodes are
##      skipped while more than `leak_skip_bait` of enemies fall into the moat.
##      Choices (excludes): picks by a simple value heuristic, logged in `choices`;
##   3. gears: save for a newly unlocked tower type, else the cheapest tower / shop upgrade.

var core: GameCore
var mode: String = "active"
var purchases: Array = []           ## [{t, id, price, category, novelty}]
var choices: Array = []             ## [{t, picked, rejected, reason}]
var boss_log: Array = []            ## [{t, boss, event}]
var bait_skips: int = 0             ## think cycles where baits were skipped because of leaks
var think_interval: float = 0.5
var reaction: float = 0.4
var cursor_speed: float = 900.0
var aim_noise: float = 14.0
var away_min: float = 1.5
var away_max: float = 3.0
var save_horizon: float = 60.0
var wish_horizon: float = 25.0
var novelty_discount: float = 0.4
var recall_delay: float = 45.0
var leak_skip_bait: float = 0.12

var cursor: Vector2 = Vector2(600, 370)
var _aim: Vector2 = Vector2(600, 370)
var _think_t: float = 0.0
var _aim_t: float = 0.0
var _away: float = 0.0
var _rng := RandomNumberGenerator.new()
var _leak_samples: Array = []       ## [time, kills, falls]
var _leak_t: float = 0.0
var _last_boss_status: Dictionary = {}
var _retreat_at: float = -1.0
var _skipped_this_think: bool = false


func _init(game_core: GameCore, bot_mode: Variant = "active", seed_value: int = 7) -> void:
	core = game_core
	if bot_mode is bool:
		mode = "active" if bot_mode else "idle"
	else:
		mode = str(bot_mode)
	_rng.seed = seed_value


func step(dt: float) -> void:
	_cursor_step(dt)
	_leak_t -= dt
	if _leak_t <= 0.0:
		_leak_t = 5.0
		_leak_samples.append([core.state.time, int(core.state.stats["kills"]), int(core.state.stats["falls"])])
		if _leak_samples.size() > 7:
			_leak_samples.pop_front()
	_track_boss()
	_think_t -= dt
	if _think_t <= 0.0:
		_think_t = think_interval
		think()


## Fraction of enemies that fell into the moat over the last ~30 s.
func leak_ratio() -> float:
	if _leak_samples.size() < 2:
		return 0.0
	var a: Array = _leak_samples[0]
	var b: Array = _leak_samples[-1]
	var k: float = float(int(b[1]) - int(a[1]))
	var f: float = float(int(b[2]) - int(a[2]))
	return f / maxf(1.0, k + f)


func _cursor_step(dt: float) -> void:
	if mode == "idle":
		core.set_cursor(Vector2.ZERO, false)
		return
	if _away > 0.0:
		_away -= dt
		core.set_cursor(Vector2(1100, 300), false)
		return
	_aim_t -= dt
	if _aim_t <= 0.0:
		_aim_t = reaction
		if core.battle.alive_count() > 0:
			var r: float = float(core.mods.lens["radius"])
			_aim = core.battle.densest_point(r) + Vector2(_rng.randfn(0.0, aim_noise), _rng.randfn(0.0, aim_noise))
	cursor = cursor.move_toward(_aim, cursor_speed * dt)
	core.set_cursor(cursor, true)


func _track_boss() -> void:
	for b: String in core.data.bosses:
		var s: String = core.state.boss_status(b)
		if s != str(_last_boss_status.get(b, "none")):
			_last_boss_status[b] = s
			boss_log.append({"t": core.state.time, "boss": b, "event": s})
			if s == "retreated":
				_retreat_at = core.state.time


func think() -> void:
	for b: String in core.data.bosses:
		if core.can_call_boss(b) and core.state.time - _retreat_at >= recall_delay:
			core.call_boss(b)
	_skipped_this_think = false
	for i in 30:
		if not _buy_one():
			break
	if _skipped_this_think:
		bait_skips += 1


## Value of a choice option (higher = preferred): towers by damage per second per
## price, otherwise by how many new behaviours it brings, then cheaper, then config order.
func _option_value(id: String) -> float:
	var n: String = id.substr(5)
	for ef: Dictionary in core.data.node_effects(n):
		if str(ef["type"]) == "unlock_tower":
			var t: String = str(ef["target"])
			var td: Dictionary = core.data.towers[t]
			var dps: float = float(td["dmg"]) / float(td["reload"]) * (1.0 + float(td["splash"]) / 40.0) \
				* (1.0 + float(td["pierce"]))
			if str(td["projectile"]) == "cone":
				dps *= 2.5   # hits a whole cone of enemies
			return 1000.0 + dps / maxf(1.0, GameCore._cost_sum(td["price"])) * 1000.0
	# situational: boost the towers I own most of; moat help when enemies leak
	var v: float = core.novelty_of(id).size() * 10.0 - GameCore._cost_sum(core.price(id)) / 1000.0
	for ef: Dictionary in core.data.node_effects(n):
		var et: String = str(ef["type"])
		if et.begins_with("tower_") and ef.has("target"):
			v += core.state.tower_count(str(ef["target"]))
		if et.begins_with("moat_") and leak_ratio() > 0.03:
			v += 5.0
		if et.begins_with("lens_"):
			v += 3.0 if mode != "idle" else 0.0
	return v


## Ids of choice options the bot has decided against (the other branch is better).
func _rejected_options(offers: Array[String]) -> Dictionary:
	var rej: Dictionary = {}
	for id in offers:
		if not id.begins_with("node:"):
			continue
		var n: String = id.substr(5)
		for x: Variant in core.data.node_excludes(n):
			var other: String = "node:" + str(x)
			if offers.has(other) and not rej.has(id):
				var mine: float = _option_value(id)
				var theirs: float = _option_value(other)
				var lose: bool = theirs > mine or (theirs == mine and \
					core.data.node_order.find(str(x)) < core.data.node_order.find(n))
				if lose:
					rej[id] = other
	return rej


func _buy_one() -> bool:
	var offers: Array[String] = core.offer_ids()
	var rejected: Dictionary = _rejected_options(offers)
	var leaking: bool = leak_ratio() > leak_skip_bait
	var bp_rate: float = maxf(0.001, float(core.income.get("blueprints", 0.0)))
	var gear_rate: float = maxf(0.001, float(core.income.get("gears", 0.0)))
	# --- map nodes
	var goal: String = ""
	var goal_cost: float = INF
	var cheapest: String = ""
	var cheapest_cost: float = INF
	var wish: String = ""
	var wish_cost: float = INF
	var wish_score: float = INF
	for id in offers:
		if not id.begins_with("node:") or rejected.has(id):
			continue
		var cost: float = _main_cost(id)
		var n: String = id.substr(5)
		if _is_priority(id):
			if cost < goal_cost:
				goal_cost = cost
				goal = id
			continue
		if core.data.node_kind(n) == "bait" and leaking:
			_skipped_this_think = true
			continue
		var score: float = cost
		if not core.novelty_of(id).is_empty():
			score *= novelty_discount
		if score < wish_score:
			wish_score = score
			wish_cost = cost
			wish = id
		if core.can_buy(id) and cost < cheapest_cost:
			cheapest_cost = cost
			cheapest = id
	if goal != "" and core.can_buy(goal):
		return _buy(goal, rejected)
	var bp: float = core.state.res("blueprints")
	var saving: bool = goal != "" and (goal_cost - bp) / bp_rate <= save_horizon
	var spare: float = bp - goal_cost if saving else bp
	if wish != "" and wish_cost <= spare and core.can_buy(wish):
		return _buy(wish, rejected)
	var wish_wait: bool = wish != "" and (wish_cost - spare) / bp_rate <= wish_horizon
	if cheapest != "" and not wish_wait and cheapest_cost <= spare:
		return _buy(cheapest, rejected)
	# --- gears: towers and shop upgrades
	var g_goal: String = ""
	var g_goal_cost: float = INF
	var g_best: String = ""
	var g_best_cost: float = INF
	for id in offers:
		if id.begins_with("node:"):
			continue
		var cost: float = _main_cost(id)
		if id.begins_with("tower:") and core.state.tower_count(id.substr(6)) == 0 and core.is_available(id):
			if cost < g_goal_cost:
				g_goal_cost = cost
				g_goal = id
		if core.can_buy(id) and cost < g_best_cost:
			g_best_cost = cost
			g_best = id
	if g_goal != "" and core.can_buy(g_goal):
		return _buy(g_goal, rejected)
	var g_saving: bool = g_goal != "" and (g_goal_cost - core.state.res("gears")) / gear_rate <= save_horizon
	if g_best != "" and (not g_saving or core.state.res("gears") - g_best_cost >= g_goal_cost):
		return _buy(g_best, rejected)
	return false


func _is_priority(id: String) -> bool:
	var n: String = id.substr(5)
	if core.data.node_kind(n) in ["spine", "region", "boss", "reward"]:
		return true
	return core.data.has_effect(n, "unlock_tower")


## Gears for towers/upgrades; blueprints for nodes (secondary materials count too).
func _main_cost(id: String) -> float:
	return GameCore._cost_sum(core.price(id))


func _buy(id: String, rejected: Dictionary) -> bool:
	var p: Dictionary = core.price(id)
	var cat: String = core.purchase_category(id)
	var nov: Array = core.novelty_of(id).duplicate()
	var excl: Array = core.data.node_excludes(id.substr(5)) if id.begins_with("node:") else []
	var other: Array = []
	var why: String = ""
	if not excl.is_empty():
		for x: Variant in excl:
			other.append("node:" + str(x))
		why = "value %.2f vs %s" % [_option_value(id), ", ".join(other.map(func(o: String) -> String:
			return "%.2f" % _option_value(o)))]
	if not core.buy(id):
		return false
	purchases.append({"t": core.state.time, "id": id, "price": p, "category": cat, "novelty": nov})
	if not excl.is_empty():
		choices.append({"t": core.state.time, "picked": id, "rejected": other, "reason": why})
	if mode == "real":
		_away = maxf(_away, _rng.randf_range(away_min, away_max))
	return true
