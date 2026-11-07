extends SceneTree
## Headless balance simulation: SimBot plays the real core (scripts/core).
## Run: tools/simulate.sh [minutes=35] [--active | --real | --idle] [--dt=0.05] [--seed=N]
##      [--seeds=1,2,3] [--compare] [--force=node_id,...] [--baits=default|none|greedy|flip] [--strict]
## Default runs all three player modes on the default seed. --seeds adds a summary of the
## same modes on other seeds; --compare adds active-mode variants (forced tower pair,
## no baits / greedy baits). Writes sim_out/timeline[_mode].csv and sim_out/report.md.
## --strict: exit code 1 if a binding check fails in any run.

const OUT_DIR := "res://sim_out"
const SAMPLE_EVERY := 10.0
const SOURCES: Array[String] = ["lens", "tower:shooter", "tower:riveter", "tower:mortar", "tower:steam_jet",
	"tower:boiler", "tower:tesla", "tower:ricochet", "moat", "scald", "zone", "ability:kettle", "ability:geyser",
	"ability:drill_ram"]
const ALL_MODES: Array[String] = ["active", "real", "idle"]
const VARIANTS: Array = [
	{"name": "bot default", "force": [], "baits": "default"},
	{"name": "forced Пароструй", "force": ["r2_steam_jet"], "baits": "default"},
	{"name": "forced Котлобой", "force": ["r2_boiler"], "baits": "default"},
	{"name": "no baits", "force": [], "baits": "none"},
	{"name": "greedy baits", "force": [], "baits": "greedy"},
	{"name": "other side of bait pairs", "force": [], "baits": "flip"},
]

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var minutes: float = float(args.get("minutes", "35"))
	var dt: float = float(args.get("dt", "0.05"))
	var seed_value: int = int(args.get("seed", "-1"))
	var opts: Dictionary = {"force": _csv(str(args.get("force", ""))), "baits": str(args.get("baits", "default"))}
	var modes: Array[String] = []
	for m in ALL_MODES:
		if args.has(m):
			modes.append(m)
	if modes.is_empty():
		modes = ALL_MODES.duplicate()
	var data := GameData.from_dir()
	if not data.errors.is_empty():
		print("config errors: ", data.errors)
		quit(1)
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var results: Array = []
	var all_runs: Array = []
	for m in modes:
		var r: Dictionary = run_mode(data, m, minutes, dt, seed_value, opts)
		results.append(r)
		all_runs.append(r)
		_write_csv(r)
		_print_summary(r)
	var seed_runs: Array = []
	for sv: String in _csv(str(args.get("seeds", ""))):
		for m in modes:
			var r2: Dictionary = run_mode(data, m, minutes, dt, int(sv), opts)
			r2["seed"] = int(sv)
			seed_runs.append(r2)
			all_runs.append(r2)
			_print_summary(r2)
	var compare: Array = []
	if args.has("compare"):
		for v: Dictionary in VARIANTS:
			var r3: Dictionary = {}
			if v["name"] == "bot default" and results.size() > 0 and results[0]["mode"] == "active" \
					and (opts["force"] as Array).is_empty() and opts["baits"] == "default":
				r3 = results[0]
			else:
				r3 = run_mode(data, "active", minutes, dt, seed_value, {"force": v["force"], "baits": v["baits"]})
				print("== variant %s: %.1f s" % [v["name"], float(r3["real_ms"]) / 1000.0])
			r3["variant"] = v["name"]
			compare.append(r3)
	var report_name: String = str(args.get("out", "report.md"))
	var f := FileAccess.open(OUT_DIR.path_join(report_name), FileAccess.WRITE)
	f.store_string(_report(results, seed_runs, compare, minutes, dt))
	f.close()
	print("report: sim_out/" + report_name)
	var code: int = 0
	if args.has("strict"):
		for r: Dictionary in all_runs:
			for c: Dictionary in r["checks"]:
				if bool(c["binding"]) and not bool(c["pass"]):
					code = 1
	quit(code)
	return false


static func _csv(s: String) -> Array:
	var out: Array = []
	for x in s.split(",", false):
		out.append(x.strip_edges())
	return out


static func run_mode(data: GameData, mode: String, minutes: float, dt: float, seed_value: int,
		opts: Dictionary = {}) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var core := GameCore.create(seed_value, data)
	core.emit_events = false
	var bot := SimBot.new(core, mode)
	bot.force = opts.get("force", [])
	bot.bait_policy = str(opts.get("baits", "default"))
	var total: float = minutes * 60.0
	var rows: Array = []
	var next_sample: float = SAMPLE_EVERY
	var prev_dmg: Dictionary = {}
	var prev_purch: int = 0
	var prev_k: int = 0
	var prev_f: int = 0
	var prev_kx: float = 0.0
	var prev_kn: int = 0
	var prev_near: int = 0
	var lens_share_5: float = -1.0
	var nan_seen: bool = false
	while core.state.time < total - 1e-6:
		bot.step(dt)
		core.tick(dt)
		if core.state.time + 1e-6 >= next_sample:
			next_sample += SAMPLE_EVERY
			var dmg: Dictionary = (core.state.stats["dmg_by_source"] as Dictionary).duplicate()
			var k: int = int(core.state.stats["kills"])
			var fl: int = int(core.state.stats["falls"])
			var b: Battle = core.battle
			var row: Dictionary = {
				"time": core.state.time,
				"gears": core.state.res("gears"),
				"blueprints": core.state.res("blueprints"),
				"coal": core.state.res("coal"),
				"copper": core.state.res("copper"),
				"gears_s": float(core.income.get("gears", 0.0)),
				"bp_s": float(core.income.get("blueprints", 0.0)),
				"coal_s": float(core.income.get("coal", 0.0)),
				"enemies": b.alive_count(),
				"kills": k, "falls": fl, "dk": k - prev_k, "df": fl - prev_f,
				"kill_x": (b.kill_x_sum - prev_kx) / maxf(1.0, float(b.kill_count - prev_kn)),
				"near": b.kill_near_moat - prev_near,
				"purchases": bot.purchases.size() - prev_purch,
				"towers": "/".join(core.data.towers.keys().map(func(t: String) -> String: return str(core.state.tower_count(t)))),
			}
			for s in SOURCES:
				row["dps_" + s] = (float(dmg.get(s, 0.0)) - float(prev_dmg.get(s, 0.0))) / SAMPLE_EVERY
			for r: String in core.state.resources:
				if not Num.is_valid(core.state.res(r)):
					nan_seen = true
			prev_dmg = dmg
			prev_purch = bot.purchases.size()
			prev_k = k
			prev_f = fl
			prev_kx = b.kill_x_sum
			prev_kn = b.kill_count
			prev_near = b.kill_near_moat
			rows.append(row)
			if lens_share_5 < 0.0 and core.state.time >= 300.0 - 1e-6:
				lens_share_5 = _lens_share(dmg)
	var bank: Dictionary = {}
	for r: String in ["gears", "blueprints", "coal"]:
		bank[r] = core.state.res(r) / maxf(0.001, float(core.income.get(r, 0.0)) * 60.0)
	var res: Dictionary = {
		"mode": mode, "seed": seed_value, "minutes": minutes, "rows": rows, "purchases": bot.purchases,
		"choices": bot.choices, "boss_log": bot.boss_log, "stats": core.state.stats.duplicate(true),
		"bait_skips": bot.bait_skips, "bait_log": bot.bait_log, "bank_minutes": bank,
		"resources": core.state.resources.duplicate(), "earned": core.state.earned.duplicate(),
		"lens_share_5": lens_share_5,
		"lens_share_all": _lens_share(core.state.stats["dmg_by_source"]), "nan": nan_seen,
		"real_ms": Time.get_ticks_msec() - t0, "bosses": core.state.bosses.duplicate(true),
	}
	_analyse(res, total)
	return res


static func _lens_share(dmg: Dictionary) -> float:
	var tot: float = 0.0
	for k: String in dmg:
		tot += float(dmg[k])
	return float(dmg.get("lens", 0.0)) / maxf(1.0, tot)


static func _first_time(purchases: Array, id: String) -> float:
	for p: Dictionary in purchases:
		if p["id"] == id:
			return float(p["t"])
	return -1.0


## 60-s windows from the 10-s rows: [{t, kills, falls, leak, kill_x}].
static func _minutes(rows: Array) -> Array:
	var out: Array = []
	var k: int = 0
	var f: int = 0
	var kx: float = 0.0
	var near: int = 0
	for row: Dictionary in rows:
		near += int(row["near"])
		k += int(row["dk"])
		f += int(row["df"])
		kx += float(row["kill_x"]) * int(row["dk"])
		if int(round(float(row["time"]))) % 60 == 0:
			out.append({"t": float(row["time"]), "kills": k, "falls": f,
				"leak": float(f) / maxf(1.0, float(k + f)), "kill_x": kx / maxf(1.0, float(k)),
				"near": float(near) / maxf(1.0, float(k))})
			near = 0
			k = 0
			f = 0
			kx = 0.0
	return out


## Purchase rhythm stats in [t_from, t_to): gaps, novelty spacing, categories.
static func _rhythm(purchases: Array, novel_events: Array, t_from: float, t_to: float) -> Dictionary:
	var last: float = t_from
	var max_gap: float = 0.0
	var max_gap_at: float = t_from
	var since_novel: int = 0
	var max_between: int = 0
	var max_between_at: float = 0.0
	var cats: Dictionary = {"novel": 0, "tower": 0, "numeric": 0}
	for p: Dictionary in purchases:
		var t: float = float(p["t"])
		if t < t_from or t > t_to:
			continue
		cats[p["category"]] = int(cats[p["category"]]) + 1
		if p["category"] == "novel":
			since_novel = 0
		else:
			since_novel += 1
			if since_novel > max_between:
				max_between = since_novel
				max_between_at = t
		if t - last > max_gap:
			max_gap = t - last
			max_gap_at = last
		last = t
	if t_to - last > max_gap:
		max_gap = t_to - last
		max_gap_at = last
	var nlast: float = t_from
	var max_novel_gap: float = 0.0
	var max_novel_gap_at: float = t_from
	for n: Dictionary in novel_events:
		var tn: float = float(n["t"])
		if tn < t_from or tn > t_to:
			continue
		if tn - nlast > max_novel_gap:
			max_novel_gap = tn - nlast
			max_novel_gap_at = nlast
		nlast = tn
	if t_to - nlast > max_novel_gap:
		max_novel_gap = t_to - nlast
		max_novel_gap_at = nlast
	var n_all: int = int(cats["novel"]) + int(cats["tower"]) + int(cats["numeric"])
	return {"max_gap": max_gap, "max_gap_at": max_gap_at, "max_between": max_between,
		"max_between_at": max_between_at, "cats": cats, "n": n_all,
		"numeric_share": float(cats["numeric"]) / maxf(1.0, float(n_all)),
		"novel_share": float(cats["novel"]) / maxf(1.0, float(n_all)),
		"tower_share": float(cats["tower"]) / maxf(1.0, float(n_all)),
		"max_novel_gap": max_novel_gap, "max_novel_gap_at": max_novel_gap_at}


static func _boss_times(boss_log: Array, boss: String) -> Dictionary:
	var out: Dictionary = {"defeated": -1.0, "attempts": 0, "first_call": -1.0, "retreats": []}
	for b: Dictionary in boss_log:
		if b["boss"] != boss:
			continue
		match str(b["event"]):
			"active":
				out["attempts"] = int(out["attempts"]) + 1
				if float(out["first_call"]) < 0.0:
					out["first_call"] = float(b["t"])
			"retreated":
				(out["retreats"] as Array).append(float(b["t"]))
			"defeated":
				out["defeated"] = float(b["t"])
	return out


static func _analyse(r: Dictionary, total: float) -> void:
	var mode: String = r["mode"]
	var purchases: Array = r["purchases"]
	var b1: Dictionary = _boss_times(r["boss_log"], "wasteland_chief")
	var b2: Dictionary = _boss_times(r["boss_log"], "drill_giant")
	var in5: int = 0
	for p: Dictionary in purchases:
		if float(p["t"]) <= 300.0:
			in5 += 1
	var novel: Array = []
	for p: Dictionary in purchases:
		if p["category"] == "novel":
			novel.append({"t": float(p["t"]), "what": "%s → %s" % [p["id"], ", ".join(p["novelty"])]})
	for bt: Array in [[b1, "Вожак пустошей"], [b2, "Бур-Великан"]]:
		var bd: Dictionary = bt[0]
		if float(bd["defeated"]) > 0.0:
			novel.append({"t": float(bd["defeated"]), "what": "boss defeated: %s (attempts %d)" % [bt[1], int(bd["attempts"])]})
	novel.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	var whole: Dictionary = _rhythm(purchases, novel, 0.0, total)
	var r1end: float = float(b1["defeated"]) if float(b1["defeated"]) > 0.0 else total
	var early: Dictionary = _rhythm(purchases, novel, 0.0, r1end)
	var late: Dictionary = _rhythm(purchases, novel, r1end, total)
	var mins: Array = _minutes(r["rows"])
	var peak_leak: float = 0.0
	var peak_at: float = 0.0
	for m: Dictionary in mins:
		if float(m["leak"]) > peak_leak:
			peak_leak = float(m["leak"])
			peak_at = float(m["t"])
	var first: float = float(purchases[0]["t"]) if not purchases.is_empty() else -1.0
	var riv: float = _first_time(purchases, "node:r1_riveter")
	var mor: float = _first_time(purchases, "node:r1_mortar")
	var r2pair: float = maxf(_first_time(purchases, "node:r2_steam_jet"), _first_time(purchases, "node:r2_boiler"))
	var r3: float = _first_time(purchases, "node:r3_road")
	var r3pair: float = maxf(_first_time(purchases, "node:r3_tesla"), _first_time(purchases, "node:r3_ricochet"))
	r["minutes_rows"] = mins
	r["boss_t"] = float(b1["defeated"])
	r["boss2_t"] = float(b2["defeated"])
	r["boss_attempts"] = int(b1["attempts"])
	r["boss2"] = b2
	r["novel"] = novel
	r["rhythm"] = {"whole": whole, "r1": early, "after_r1": late}
	r["cats"] = whole["cats"]
	r["key_times"] = {"r2pair": r2pair, "r3": r3, "r3pair": r3pair}
	var ls: float = float(r["lens_share_5"])
	var bind: bool = mode != "idle"
	var lens_lo: float = 0.25 if mode == "active" else 0.15
	var bank: Dictionary = r["bank_minutes"]
	var bank_max: float = 0.0
	var bank_res: String = ""
	for k: String in bank:
		if float(bank[k]) > bank_max:
			bank_max = float(bank[k])
			bank_res = k
	var horizon: String = _t(total)
	r["checks"] = [
		_check("first purchase at 5–15 s", (first >= 5.0 or mode == "idle") and first >= 0.0 and first <= 15.0, _t(first), true),
		_check(">= 10 purchases in first 5 min", in5 >= 10, str(in5), bind),
		_check("Клепальщик unlocked ~3 min (2:15–3:45)", riv >= 135.0 and riv <= 225.0, _t(riv), bind),
		_check("Мортира unlocked ~8–10 min (7:30–10:30)", mor >= 450.0 and mor <= 630.0, _t(mor), bind),
		_check("Вожак (R1 boss) beaten at 12–15 min", float(b1["defeated"]) >= 720.0 and float(b1["defeated"]) <= 900.0,
			"%s (attempts %d)" % [_t(float(b1["defeated"])), int(b1["attempts"])], bind),
		_check("R2 tower pair chosen at 14:30–18:00 (not with the R1 boss reward)", r2pair >= 870.0 and r2pair <= 1080.0, _t(r2pair), bind),
		_check("Бур-Великан (R2 boss) beaten at 26–34 min", float(b2["defeated"]) >= 1560.0 and float(b2["defeated"]) <= 2040.0,
			"%s (attempts %d, first call %s)" % [_t(float(b2["defeated"])), int(b2["attempts"]), _t(float(b2["first_call"]))], bind and total >= 2040.0),
		_check("R3 entered (Медные болота) by the end", r3 > 0.0, _t(r3), bind and total >= 2100.0),
		_check("max gap between purchases <= 3:00 (0–%s)" % horizon, float(whole["max_gap"]) <= 180.0,
			"%s (after %s)" % [_t(float(whole["max_gap"])), _t(float(whole["max_gap_at"]))], bind),
		_check("something new every <= 5:00 (0–%s)" % horizon, float(whole["max_novel_gap"]) <= 300.0,
			"%s (after %s)" % [_t(float(whole["max_novel_gap"])), _t(float(whole["max_novel_gap_at"]))], bind),
		_check("purchases between novelties <= 8 (0–%s)" % horizon, int(whole["max_between"]) <= 8,
			"%d (at %s)" % [int(whole["max_between"]), _t(float(whole["max_between_at"]))], bind),
		_check("pure-numeric purchases <= 40%% (0–%s)" % horizon, float(whole["numeric_share"]) <= 0.40,
			"%.0f%% numeric, %.0f%% new, %.0f%% extra towers (%d purchases)" % [float(whole["numeric_share"]) * 100.0,
			float(whole["novel_share"]) * 100.0, float(whole["tower_share"]) * 100.0, int(whole["n"])], bind),
		_check("lens damage share %d–40%% (first 5 min)" % int(lens_lo * 100.0), ls >= lens_lo and ls <= 0.40, "%.1f%%" % (ls * 100.0), bind),
		_check("pressure: a minute with >= 5% moat falls", peak_leak >= 0.05, "peak %.1f%% at %s" % [peak_leak * 100.0, _t(peak_at)], bind),
		_check("no collapse: no minute with > 35% moat falls", peak_leak <= 0.35, "peak %.1f%%" % (peak_leak * 100.0), bind),
		_check("resources have sinks: stock at the end <= 6 min of income", bank_max <= 6.0,
			"max %.1f min (%s); gears %.1f, bp %.1f, coal %.1f" % [bank_max, bank_res, float(bank["gears"]),
			float(bank["blueprints"]), float(bank["coal"])], bind),
		_check("no NaN/inf", not bool(r["nan"]), str(not bool(r["nan"])), true),
	]


static func _check(name: String, ok: bool, value: String, binding: bool) -> Dictionary:
	return {"name": name, "pass": ok, "value": value, "binding": binding}


static func _t(sec: float) -> String:
	if sec < 0.0:
		return "never"
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]


func _write_csv(r: Dictionary) -> void:
	var name: String = "timeline.csv" if r["mode"] == "active" else "timeline_%s.csv" % r["mode"]
	var f := FileAccess.open(OUT_DIR.path_join(name), FileAccess.WRITE)
	var cols: Array[String] = ["time", "gears", "blueprints", "coal", "copper", "gears_s", "bp_s", "coal_s"]
	for s in SOURCES:
		cols.append("dps_" + s)
	cols.append_array(["enemies", "kills", "falls", "dk", "df", "kill_x", "near", "purchases", "towers"])
	f.store_line(",".join(cols))
	for row: Dictionary in r["rows"]:
		var vals: PackedStringArray = []
		for c in cols:
			var v: Variant = row.get(c, "")
			vals.append(("%.2f" % float(v)) if typeof(v) == TYPE_FLOAT else str(v))
		f.store_line(",".join(vals))
	f.close()


func _print_summary(r: Dictionary) -> void:
	print("== %s seed %d: %.0f min simulated in %.1f s real" % [r["mode"], int(r["seed"]), float(r["minutes"]),
		float(r["real_ms"]) / 1000.0])
	for c: Dictionary in r["checks"]:
		var tag: String = ("PASS" if c["pass"] else "FAIL") if c["binding"] else ("ok" if c["pass"] else "info")
		print("  [%s] %s: %s" % [tag, c["name"], c["value"]])
	var st: Dictionary = r["stats"]
	print("  kills %d, moat falls %d (%.1f%%), lens share all %.1f%%, baits bought %d" % [int(st["kills"]), int(st["falls"]),
		100.0 * float(st["falls"]) / maxf(1.0, float(st["kills"]) + float(st["falls"])), float(r["lens_share_all"]) * 100.0,
		(r["bait_log"] as Array).size()])
	for c: Dictionary in r["choices"]:
		print("  choice %s: %s over %s" % [_t(float(c["t"])), c["picked"], ", ".join(c["rejected"])])


static func _tower_share(r: Dictionary, src: String) -> float:
	var dmg: Dictionary = r["stats"]["dmg_by_source"]
	var tot: float = 0.0
	for k: String in dmg:
		tot += float(dmg[k])
	# + the scald damage-over-time this tower applied (stats.dot_by_owner)
	var dot: float = float((r["stats"].get("dot_by_owner", {}) as Dictionary).get(src, 0.0))
	return (float(dmg.get(src, 0.0)) + dot) / maxf(1.0, tot)


static func _fails(r: Dictionary) -> String:
	var out: PackedStringArray = []
	for c: Dictionary in r["checks"]:
		if bool(c["binding"]) and not bool(c["pass"]):
			out.append(str(c["name"]).substr(0, 28))
	return "—" if out.is_empty() else "; ".join(out)


func _report(results: Array, seed_runs: Array, compare: Array, minutes: float, dt: float) -> String:
	var s: String = "# Simulation report\n\nGenerated by tools/simulate.sh: %.0f game minutes per run, dt = %.3f s, bot = SimBot.\n" % [minutes, dt]
	s += "Modes: **active** = lazy player keeps the lens over the densest group; **real** = same, but the mouse leaves the field for 1.5–3 s on every purchase; **idle** = never touches the field (auto lens).\n"
	s += "Checks marked PASS/FAIL are binding (DESIGN.md §9 + critics) and cover the whole run (0–%s); ok/info are informational (idle).\n" % _t(minutes * 60.0)
	s += "Purchase categories (honest, GameCore.novelty_of): **new** = adds an on-screen behaviour (new enemy, tower, producer, mechanism, status, first pierce/splash/multishot/chain, dig, armour pierce, knockback ≥ %s px...); a new look (tier) or a map region alone is **not** new; **tower** = one more tower of an owned type; **numeric** = numbers only.\n" % "20"
	var all_first: Array = results.duplicate()
	all_first.append_array(seed_runs)
	if not all_first.is_empty():
		s += "\n## Summary (all runs)\n\n| mode | seed | R1 boss | R2 pair | R2 boss (attempts) | R3 | R3 pair | numeric | new | max gap | max new-gap | max between | falls | real s | failed binding checks |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
		for r: Dictionary in all_first:
			var wh: Dictionary = r["rhythm"]["whole"]
			var st: Dictionary = r["stats"]
			var kt: Dictionary = r["key_times"]
			s += "| %s | %d | %s | %s | %s (%d) | %s | %s | %.0f%% | %.0f%% | %s | %s | %d | %.1f%% | %.1f | %s |\n" % [r["mode"], int(r["seed"]),
				_t(float(r["boss_t"])), _t(float(kt["r2pair"])), _t(float(r["boss2_t"])), int(r["boss2"]["attempts"]),
				_t(float(kt["r3"])), _t(float(kt["r3pair"])), float(wh["numeric_share"]) * 100.0, float(wh["novel_share"]) * 100.0,
				_t(float(wh["max_gap"])), _t(float(wh["max_novel_gap"])), int(wh["max_between"]),
				100.0 * float(st["falls"]) / maxf(1.0, float(st["kills"]) + float(st["falls"])), float(r["real_ms"]) / 1000.0, _fails(r)]
	if not compare.is_empty():
		s += "\n## Variants (active, default seed): tower pair and baits\n\n"
		s += "Is the pair choice balanced, and is a bait a real decision? Same bot, same seed; only the forced choice or the bait policy differs (\"greedy\" saves for every bait as soon as it is offered and ignores leaks; \"none\" never buys baits; \"other side\" takes the other node of every «Гудок» ↔ «Слухи о кладе» pair).\n\n"
		s += "| variant | R1 boss | R2 pair | R2 boss (attempts) | R3 | gears earned | bp earned | coal earned | falls | peak leak/min | Пароструй dmg (+its scald) | Котлобой dmg | baits bought |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
		for r: Dictionary in compare:
			var st2: Dictionary = r["stats"]
			var peak: float = 0.0
			for m: Dictionary in r["minutes_rows"]:
				peak = maxf(peak, float(m["leak"]))
			var pick: String = "—"
			for c: Dictionary in r["choices"]:
				if str(c["picked"]) in ["node:r2_steam_jet", "node:r2_boiler"]:
					pick = str(c["picked"]).substr(8)
			s += "| %s | %s | %s %s | %s (%d) | %s | %s | %s | %s | %.1f%% | %.1f%% | %.1f%% | %.1f%% | %d |\n" % [r["variant"],
				_t(float(r["boss_t"])), _t(float(r["key_times"]["r2pair"])), pick, _t(float(r["boss2_t"])), int(r["boss2"]["attempts"]),
				_t(float(r["key_times"]["r3"])), NumFmt.num(float(r["earned"].get("gears", 0.0))),
				NumFmt.num(float(r["earned"].get("blueprints", 0.0))), NumFmt.num(float(r["earned"].get("coal", 0.0))),
				100.0 * float(st2["falls"]) / maxf(1.0, float(st2["kills"]) + float(st2["falls"])), peak * 100.0,
				_tower_share(r, "tower:steam_jet") * 100.0, _tower_share(r, "tower:boiler") * 100.0, (r["bait_log"] as Array).size()]
	for r: Dictionary in results:
		var st: Dictionary = r["stats"]
		s += "\n## Mode: %s (seed %d)\n\n" % [r["mode"], int(r["seed"])]
		s += "Real time: %.1f s. Kills: %d, moat falls: %d (%.1f%%). Purchases: %d. Baits bought: %d.\n\n" % [
			float(r["real_ms"]) / 1000.0, int(st["kills"]), int(st["falls"]),
			100.0 * float(st["falls"]) / maxf(1.0, float(st["kills"]) + float(st["falls"])),
			(r["purchases"] as Array).size(), (r["bait_log"] as Array).size()]
		s += "### Checks\n\n| check | result | value |\n|---|---|---|\n"
		for c: Dictionary in r["checks"]:
			var tag: String = ("PASS" if c["pass"] else "FAIL") if c["binding"] else ("ok" if c["pass"] else "info")
			s += "| %s | %s | %s |\n" % [c["name"], tag, c["value"]]
		s += "\nRhythm by phase (purchases; numeric share; max purchases between novelties; max gap; max gap without something new):\n\n| phase | purchases | numeric | new | towers | max between | max gap | max new-gap |\n|---|---|---|---|---|---|---|---|\n"
		for ph: String in ["r1", "after_r1", "whole"]:
			var rh: Dictionary = r["rhythm"][ph]
			s += "| %s | %d | %.0f%% | %.0f%% | %.0f%% | %d | %s | %s |\n" % [ph, int(rh["n"]), float(rh["numeric_share"]) * 100.0,
				float(rh["novel_share"]) * 100.0, float(rh["tower_share"]) * 100.0, int(rh["max_between"]), _t(float(rh["max_gap"])),
				_t(float(rh["max_novel_gap"]))]
		s += "\nLens share: first 5 min %.1f%%, whole run %.1f%%. Stock at the end in minutes of income: gears %.1f, bp %.1f, coal %.1f.\n" % [
			float(r["lens_share_5"]) * 100.0, float(r["lens_share_all"]) * 100.0, float(r["bank_minutes"]["gears"]),
			float(r["bank_minutes"]["blueprints"]), float(r["bank_minutes"]["coal"])]
		s += "\n### Bosses (attempts; after a retreat the bot presses «вызвать снова» after 45 s + 300 s × hp left)\n\n"
		for b: Dictionary in r["boss_log"]:
			var hpl: String = ""
			if str(b["event"]) == "retreated":
				hpl = " (reached the moat with %.0f%% hp left)" % (float(b.get("hp_left", 0.0)) * 100.0)
			s += "- %s — %s %s%s\n" % [_t(float(b["t"])), b["boss"], b["event"], hpl]
		s += "\n### Choices\n\n"
		for c: Dictionary in r["choices"]:
			s += "- %s — picked %s over %s (%s)\n" % [_t(float(c["t"])), c["picked"], ", ".join(c["rejected"]), c["reason"]]
		s += "\n### Baits bought (time, node, level, leak ratio over the last 30 s)\n\n"
		for bl: Dictionary in r["bait_log"]:
			s += "- %s — %s L%d (leak %.1f%%)\n" % [_t(float(bl["t"])), bl["id"], int(bl["level"]), float(bl["leak"]) * 100.0]
		s += "\n### Damage by source (whole run)\n\n| source | damage | share |\n|---|---|---|\n"
		var dmg: Dictionary = st["dmg_by_source"]
		var tot: float = 0.0
		for k: String in dmg:
			tot += float(dmg[k])
		for k: String in dmg:
			s += "| %s | %s | %.1f%% |\n" % [k, NumFmt.num(float(dmg[k])), 100.0 * float(dmg[k]) / maxf(1.0, tot)]
		var dob: Dictionary = st.get("dot_by_owner", {})
		s += "\nScald (damage over time) by who applied it: %s\n" % ", ".join(dob.keys().map(func(k: String) -> String:
			return "%s %.1f%%" % [k, 100.0 * float(dob[k]) / maxf(1.0, tot)]))
		s += "\n### Timeline of novelties (something new on screen)\n\n"
		for n: Dictionary in r["novel"]:
			s += "- %s — %s\n" % [_t(float(n["t"])), n["what"]]
		s += "\n### Per minute: moat falls and where kills happen\n\n| minute end | kills | falls | leak | mean kill x (moat 290, spawn 900) | kills within 150 px of the moat |\n|---|---|---|---|---|---|\n"
		for m: Dictionary in r["minutes_rows"]:
			s += "| %s | %d | %d | %.1f%% | %d | %.1f%% |\n" % [_t(float(m["t"])), int(m["kills"]), int(m["falls"]),
				float(m["leak"]) * 100.0, int(m["kill_x"]), float(m["near"]) * 100.0]
		s += "\n### Timeline (every 60 s)\n\n| time | gears | bp | coal | copper | gears/s | bp/s | coal/s | dps lens | dps towers | dps other | enemies | towers |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
		for row: Dictionary in r["rows"]:
			if int(round(float(row["time"]))) % 60 != 0:
				continue
			var tw: float = 0.0
			var other: float = 0.0
			for src in SOURCES:
				if src.begins_with("tower:"):
					tw += float(row["dps_" + src])
				elif src != "lens":
					other += float(row["dps_" + src])
			s += "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %d | %s |\n" % [
				_t(float(row["time"])), NumFmt.num(float(row["gears"])), NumFmt.num(float(row["blueprints"])),
				NumFmt.num(float(row["coal"])), NumFmt.num(float(row["copper"])), NumFmt.num(float(row["gears_s"])),
				NumFmt.num(float(row["bp_s"])), NumFmt.num(float(row["coal_s"])),
				NumFmt.num(float(row["dps_lens"])), NumFmt.num(tw), NumFmt.num(other), int(row["enemies"]), row["towers"]]
		s += "\n### Purchases (time, id, price, gap, category)\n\n"
		var last: float = 0.0
		for p: Dictionary in r["purchases"]:
			var pr: PackedStringArray = []
			for k: String in p["price"]:
				pr.append("%s %s" % [NumFmt.num(float(p["price"][k])), k])
			var extra: String = ""
			if p["category"] == "novel":
				extra = " → " + ", ".join(p["novelty"])
			elif not (p.get("changes", []) as Array).is_empty():
				extra = " (look only: " + ", ".join(p["changes"]) + ")"
			s += "- %s  %s  (%s)  +%ds  %s%s\n" % [_t(float(p["t"])), p["id"], ", ".join(pr), int(float(p["t"]) - last),
				p["category"], extra]
			last = float(p["t"])
	return s
