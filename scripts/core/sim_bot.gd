class_name SimBot
extends RefCounted
## A "reasonable player" bot that drives a GameCore: used by the headless
## balance sim (tools/sim), tests and the debug view's --bot autoplay.
##
## Cursor: active = a lazy player who keeps the lens over the densest group,
## reacting every `reaction` s with some aim noise; idle = no cursor at all
## (lens in auto mode).
## Purchases every `think_interval` s:
##   1. re-call a retreated boss after `recall_delay` s;
##   2. map nodes: save for the cheapest "priority" node (new enemy / tower /
##      behaviour / region / boss) if it is affordable within `save_horizon` s,
##      otherwise buy the cheapest affordable node (skipping "bait" nodes while
##      enemies leak into the moat);
##   3. gears: save for a newly unlocked tower type, otherwise buy the cheapest
##      tower / shop upgrade.

var core: GameCore
var active: bool = true
var purchases: Array = []           ## [{t, id, price, novel}]
var boss_log: Array = []            ## [{t, event}]
var think_interval: float = 0.5
var reaction: float = 0.4
var cursor_speed: float = 900.0
var aim_noise: float = 14.0
var save_horizon: float = 60.0
var recall_delay: float = 45.0
var leak_skip_bait: float = 0.12
## A new behaviour looks this much cheaper to the bot (players are drawn to new things).
var novelty_discount: float = 0.4
## Waits up to this many seconds of income for the node it wants most.
var wish_horizon: float = 25.0

var cursor: Vector2 = Vector2(600, 370)
var _aim: Vector2 = Vector2(600, 370)
var _think_t: float = 0.0
var _aim_t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _leak_samples: Array = []       ## [time, kills, falls]
var _leak_t: float = 0.0
var _last_boss_status: Dictionary = {}
var _retreat_at: float = -1.0


func _init(game_core: GameCore, is_active: bool = true, seed_value: int = 7) -> void:
	core = game_core
	active = is_active
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
	if not active:
		core.set_cursor(Vector2.ZERO, false)
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
	for i in 30:
		if not _buy_one():
			break


func _buy_one() -> bool:
	var offers: Array[String] = core.offer_ids()
	var leaking: bool = leak_ratio() > leak_skip_bait
	var bp_rate: float = maxf(0.001, float(core.income.get("blueprints", 0.0)))
	var gear_rate: float = maxf(0.001, float(core.income.get("gears", 0.0)))
	# --- map nodes
	var goal: String = ""
	var goal_cost: float = INF
	var cheapest: String = ""           # cheapest affordable by real cost
	var cheapest_cost: float = INF
	var wish: String = ""               # best by score (novelty looks cheaper), maybe not affordable yet
	var wish_cost: float = INF
	var wish_score: float = INF
	for id in offers:
		if not id.begins_with("node:"):
			continue
		var cost: float = _main_cost(id)
		var n: String = id.substr(5)
		if _is_priority(id):
			if cost < goal_cost:
				goal_cost = cost
				goal = id
			continue
		if leaking and core.data.node_kind(n) == "bait":
			continue
		var score: float = cost
		if core.state.node_level(n) == 0 and core.data.is_novel_node(n):
			score *= novelty_discount
		if score < wish_score:
			wish_score = score
			wish_cost = cost
			wish = id
		if core.can_buy(id) and cost < cheapest_cost:
			cheapest_cost = cost
			cheapest = id
	if goal != "" and core.can_buy(goal):
		return _buy(goal)
	var bp: float = core.state.res("blueprints")
	var saving: bool = goal != "" and (goal_cost - bp) / bp_rate <= save_horizon
	var spare: float = bp - goal_cost if saving else bp
	if wish != "" and wish_cost <= spare and core.can_buy(wish):
		return _buy(wish)
	var wish_wait: bool = wish != "" and (wish_cost - spare) / bp_rate <= wish_horizon
	if cheapest != "" and not wish_wait and cheapest_cost <= spare:
		return _buy(cheapest)
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
		return _buy(g_goal)
	var g_saving: bool = g_goal != "" and (g_goal_cost - core.state.res("gears")) / gear_rate <= save_horizon
	if g_best != "" and (not g_saving or core.state.res("gears") - g_best_cost >= g_goal_cost):
		return _buy(g_best)
	return false


func _is_priority(id: String) -> bool:
	var n: String = id.substr(5)
	var kind: String = core.data.node_kind(n)
	if kind in ["spine", "region", "boss"]:
		return true
	for ef: Dictionary in core.data.node_effects(n):
		if str(ef.get("type", "")) == "unlock_tower":
			return true
	return false


func _main_cost(id: String) -> float:
	var p: Dictionary = core.price(id)
	var s: float = 0.0
	for r: String in p:
		s += float(p[r])
	return s


func _buy(id: String) -> bool:
	var p: Dictionary = core.price(id)
	var novel: bool = id.begins_with("node:") and core.state.node_level(id.substr(5)) == 0 \
		and core.data.is_novel_node(id.substr(5))
	if id.begins_with("tower:") and core.state.tower_count(id.substr(6)) == 0:
		novel = true
	if not core.buy(id):
		return false
	purchases.append({"t": core.state.time, "id": id, "price": p, "novel": novel})
	return true
