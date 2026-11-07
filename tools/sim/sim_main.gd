extends SceneTree
## Headless balance simulation: SimBot plays the real core (scripts/core).
## Run: tools/simulate.sh [minutes=20] [--active | --real | --idle] [--dt=0.05] [--seed=N] [--strict]
## Default runs all three player modes. Writes sim_out/timeline[_mode].csv and sim_out/report.md.
## --strict: exit code 1 if a binding check fails.

const OUT_DIR := "res://sim_out"
const SAMPLE_EVERY := 10.0
const SOURCES: Array[String] = ["lens", "tower:shooter", "tower:riveter", "tower:mortar", "tower:steam_jet",
	"tower:boiler", "moat", "scald", "zone", "ability:kettle"]
const ALL_MODES: Array[String] = ["active", "real", "idle"]

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var minutes: float = float(args.get("minutes", "20"))
	var dt: float = float(args.get("dt", "0.05"))
	var seed_value: int = int(args.get("seed", "-1"))
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
	for m in modes:
		var r: Dictionary = run_mode(data, m, minutes, dt, seed_value)
		results.append(r)
		_write_csv(r)
		_print_summary(r)
	var f := FileAccess.open(OUT_DIR.path_join("report.md"), FileAccess.WRITE)
	f.store_string(_report(results, minutes, dt))
	f.close()
	print("report: sim_out/report.md")
	var code: int = 0
	if args.has("strict"):
		for r: Dictionary in results:
			for c: Dictionary in r["checks"]:
				if bool(c["binding"]) and not bool(c["pass"]):
					code = 1
	quit(code)
	return false


static func run_mode(data: GameData, mode: String, minutes: float, dt: float, seed_value: int) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var core := GameCore.create(seed_value, data)
	core.emit_events = false
	var bot := SimBot.new(core, mode)
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
				"gears_s": float(core.income.get("gears", 0.0)),
				"bp_s": float(core.income.get("blueprints", 0.0)),
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
	var res: Dictionary = {
		"mode": mode, "minutes": minutes, "rows": rows, "purchases": bot.purchases, "choices": bot.choices,
		"boss_log": bot.boss_log, "stats": core.state.stats.duplicate(true), "bait_skips": bot.bait_skips,
		"resources": core.state.resources.duplicate(), "lens_share_5": lens_share_5,
		"lens_share_all": _lens_share(core.state.stats["dmg_by_source"]), "nan": nan_seen,
		"real_ms": Time.get_ticks_msec() - t0,
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


static func _analyse(r: Dictionary, total: float) -> void:
	var mode: String = r["mode"]
	var purchases: Array = r["purchases"]
	var boss_t: float = -1.0
	var attempts: int = 0
	for b: Dictionary in r["boss_log"]:
		if b["event"] == "defeated" and boss_t < 0.0:
			boss_t = float(b["t"])
		if b["event"] == "active":
			attempts += 1
	var phase_end: float = boss_t if boss_t > 0.0 else total
	var last: float = 0.0
	var max_gap: float = 0.0
	var max_gap_at: float = 0.0
	var in5: int = 0
	var since_novel: int = 0
	var max_between: int = 0
	var max_between_at: float = 0.0
	var cats: Dictionary = {"novel": 0, "tower": 0, "numeric": 0}
	for p: Dictionary in purchases:
		var t: float = float(p["t"])
		if t <= 300.0:
			in5 += 1
		if t > phase_end:
			break
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
	if phase_end - last > max_gap:
		max_gap = phase_end - last
		max_gap_at = last
	var n_before: int = int(cats["novel"]) + int(cats["tower"]) + int(cats["numeric"])
	var numeric_share: float = float(cats["numeric"]) / maxf(1.0, float(n_before))
	var strict_share: float = float(int(cats["numeric"]) + int(cats["tower"])) / maxf(1.0, float(n_before))
	var novel: Array = []
	for p: Dictionary in purchases:
		if p["category"] == "novel":
			novel.append({"t": float(p["t"]), "what": "%s → %s" % [p["id"], ", ".join(p["novelty"])]})
	if boss_t > 0.0:
		novel.append({"t": boss_t, "what": "boss defeated"})
	novel.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	var nlast: float = 0.0
	var max_novel_gap: float = 0.0
	for n: Dictionary in novel:
		if float(n["t"]) > phase_end:
			break
		max_novel_gap = maxf(max_novel_gap, float(n["t"]) - nlast)
		nlast = float(n["t"])
	max_novel_gap = maxf(max_novel_gap, phase_end - nlast)
	var mins: Array = _minutes(r["rows"])
	var peak_leak: float = 0.0
	var peak_at: float = 0.0
	for m: Dictionary in mins:
		if float(m["t"]) <= phase_end + 60.0 and float(m["leak"]) > peak_leak:
			peak_leak = float(m["leak"])
			peak_at = float(m["t"])
	var first: float = float(purchases[0]["t"]) if not purchases.is_empty() else -1.0
	var riv: float = _first_time(purchases, "node:r1_riveter")
	var mor: float = _first_time(purchases, "node:r1_mortar")
	var r2pair: float = maxf(_first_time(purchases, "node:r2_steam_jet"), _first_time(purchases, "node:r2_boiler"))
	r["minutes_rows"] = mins
	r["boss_t"] = boss_t
	r["boss_attempts"] = attempts
	r["novel"] = novel
	r["cats"] = cats
	var ls: float = float(r["lens_share_5"])
	var bind: bool = mode != "idle"
	var lens_lo: float = 0.25 if mode == "active" else 0.15
	r["checks"] = [
		_check("first purchase at 5–15 s", (first >= 5.0 or mode == "idle") and first >= 0.0 and first <= 15.0, _t(first), true),
		_check(">= 10 purchases in first 5 min", in5 >= 10, str(in5), bind),
		_check("Клепальщик unlocked ~3 min (2:15–3:45)", riv >= 135.0 and riv <= 225.0, _t(riv), bind),
		_check("Мортира unlocked ~8–10 min (7:30–10:30)", mor >= 450.0 and mor <= 630.0, _t(mor), bind),
		_check("region-1 boss beaten at 12–15 min", boss_t >= 720.0 and boss_t <= 900.0, _t(boss_t), bind),
		_check("max gap between purchases <= 3:00 (until boss)", max_gap <= 180.0, "%s (after %s)" % [_t(max_gap), _t(max_gap_at)], bind),
		_check("something new every <= 5:00 (until boss)", max_novel_gap <= 300.0, _t(max_novel_gap), bind),
		_check("purchases between novelties <= 8 (until boss)", max_between <= 8, "%d (at %s)" % [max_between, _t(max_between_at)], bind),
		_check("pure-numeric purchases < 50% (until boss)", numeric_share < 0.5,
			"%.0f%% numeric, %.0f%% new, %.0f%% extra towers (numeric+towers %.0f%%)" % [numeric_share * 100.0,
			100.0 * int(cats["novel"]) / maxf(1.0, n_before), 100.0 * int(cats["tower"]) / maxf(1.0, n_before), strict_share * 100.0], bind),
		_check("lens damage share %d–40%% (first 5 min)" % int(lens_lo * 100.0), ls >= lens_lo and ls <= 0.40, "%.1f%%" % (ls * 100.0), bind),
		_check("pressure: a minute with >= 5% moat falls (until boss)", peak_leak >= 0.05, "peak %.1f%% at %s" % [peak_leak * 100.0, _t(peak_at)], bind),
		_check("no collapse: no minute with > 35% moat falls", peak_leak <= 0.35, "peak %.1f%%" % (peak_leak * 100.0), bind),
		_check("region-2 tower pair chosen before 20:00", r2pair > 0.0 and r2pair <= 1200.0, _t(r2pair), bind),
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
	var cols: Array[String] = ["time", "gears", "blueprints", "coal", "gears_s", "bp_s"]
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
	print("== %s: %.0f min simulated in %.1f s real" % [r["mode"], float(r["minutes"]), float(r["real_ms"]) / 1000.0])
	for c: Dictionary in r["checks"]:
		var tag: String = ("PASS" if c["pass"] else "FAIL") if c["binding"] else ("ok" if c["pass"] else "info")
		print("  [%s] %s: %s" % [tag, c["name"], c["value"]])
	var st: Dictionary = r["stats"]
	print("  kills %d, moat falls %d (%.1f%%), lens share all %.1f%%, bait skips %d" % [int(st["kills"]), int(st["falls"]),
		100.0 * float(st["falls"]) / maxf(1.0, float(st["kills"]) + float(st["falls"])), float(r["lens_share_all"]) * 100.0,
		int(r["bait_skips"])])
	for c: Dictionary in r["choices"]:
		print("  choice %s: %s over %s" % [_t(float(c["t"])), c["picked"], ", ".join(c["rejected"])])


func _report(results: Array, minutes: float, dt: float) -> String:
	var s: String = "# Simulation report\n\nGenerated by tools/simulate.sh: %.0f game minutes per mode, dt = %.3f s, bot = SimBot.\n" % [minutes, dt]
	s += "Modes: **active** = lazy player keeps the lens over the densest group; **real** = same, but the mouse leaves the field for 1.5–3 s on every purchase; **idle** = never touches the field (auto lens).\n"
	s += "Checks marked PASS/FAIL are binding (DESIGN.md §9 + critic); ok/info are informational (idle).\n"
	s += "Purchase categories: **new** = adds an on-screen behaviour (Mods.behaviours: new enemy, tower, tier look, status, mechanism, first pierce/splash/multishot...), **tower** = one more tower of an owned type, **numeric** = numbers only.\n"
	for r: Dictionary in results:
		var st: Dictionary = r["stats"]
		s += "\n## Mode: %s\n\n" % r["mode"]
		s += "Real time: %.1f s. Kills: %d, moat falls: %d (%.1f%%). Purchases: %d. Bait skips (leaking): %d.\n\n" % [
			float(r["real_ms"]) / 1000.0, int(st["kills"]), int(st["falls"]),
			100.0 * float(st["falls"]) / maxf(1.0, float(st["kills"]) + float(st["falls"])),
			(r["purchases"] as Array).size(), int(r["bait_skips"])]
		s += "### Checks\n\n| check | result | value |\n|---|---|---|\n"
		for c: Dictionary in r["checks"]:
			var tag: String = ("PASS" if c["pass"] else "FAIL") if c["binding"] else ("ok" if c["pass"] else "info")
			s += "| %s | %s | %s |\n" % [c["name"], tag, c["value"]]
		s += "\nLens share: first 5 min %.1f%%, whole run %.1f%%. Boss attempts: %d. Purchases until boss: %s.\n" % [
			float(r["lens_share_5"]) * 100.0, float(r["lens_share_all"]) * 100.0, int(r["boss_attempts"]), str(r["cats"])]
		s += "\n### Choices\n\n"
		for c: Dictionary in r["choices"]:
			s += "- %s — picked %s over %s (%s)\n" % [_t(float(c["t"])), c["picked"], ", ".join(c["rejected"]), c["reason"]]
		s += "\n### Damage by source (whole run)\n\n| source | damage | share |\n|---|---|---|\n"
		var dmg: Dictionary = st["dmg_by_source"]
		var tot: float = 0.0
		for k: String in dmg:
			tot += float(dmg[k])
		for k: String in dmg:
			s += "| %s | %s | %.1f%% |\n" % [k, NumFmt.num(float(dmg[k])), 100.0 * float(dmg[k]) / maxf(1.0, tot)]
		s += "\n### Something new on screen\n\n"
		for n: Dictionary in r["novel"]:
			s += "- %s — %s\n" % [_t(float(n["t"])), n["what"]]
		s += "\n### Boss\n\n"
		for b: Dictionary in r["boss_log"]:
			s += "- %s — %s %s\n" % [_t(float(b["t"])), b["boss"], b["event"]]
		s += "\n### Per minute: moat falls and where kills happen\n\n| minute end | kills | falls | leak | mean kill x (moat 290, spawn 900) | kills within 150 px of the moat |\n|---|---|---|---|---|---|\n"
		for m: Dictionary in r["minutes_rows"]:
			s += "| %s | %d | %d | %.1f%% | %d | %.1f%% |\n" % [_t(float(m["t"])), int(m["kills"]), int(m["falls"]),
				float(m["leak"]) * 100.0, int(m["kill_x"]), float(m["near"]) * 100.0]
		s += "\n### Timeline (every 60 s)\n\n| time | gears | bp | coal | gears/s | bp/s | dps lens | dps towers | dps other | enemies | towers |\n|---|---|---|---|---|---|---|---|---|---|---|\n"
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
			s += "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %d | %s |\n" % [
				_t(float(row["time"])), NumFmt.num(float(row["gears"])), NumFmt.num(float(row["blueprints"])),
				NumFmt.num(float(row["coal"])), NumFmt.num(float(row["gears_s"])), NumFmt.num(float(row["bp_s"])),
				NumFmt.num(float(row["dps_lens"])), NumFmt.num(tw), NumFmt.num(other), int(row["enemies"]), row["towers"]]
		s += "\n### Purchases (time, id, price, gap, category)\n\n"
		var last: float = 0.0
		for p: Dictionary in r["purchases"]:
			var pr: PackedStringArray = []
			for k: String in p["price"]:
				pr.append("%s %s" % [NumFmt.num(float(p["price"][k])), k])
			s += "- %s  %s  (%s)  +%ds  %s%s\n" % [_t(float(p["t"])), p["id"], ", ".join(pr), int(float(p["t"]) - last),
				p["category"], (" → " + ", ".join(p["novelty"])) if p["category"] == "novel" else ""]
			last = float(p["t"])
	return s
