extends SceneTree
## Headless balance simulation: SimBot plays the real core (scripts/core).
## Run: tools/simulate.sh [minutes=20] [--idle | --active] [--dt=0.05] [--seed=N] [--strict]
## Default runs both modes (active cursor player and idle player).
## Writes sim_out/timeline.csv (+ timeline_idle.csv) and sim_out/report.md.
## --strict: exit code 1 if an active-mode pacing check fails.

const OUT_DIR := "res://sim_out"
const SAMPLE_EVERY := 10.0
const SOURCES: Array[String] = ["lens", "tower:shooter", "tower:riveter", "tower:mortar", "moat", "scald"]

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
	var modes: Array[String] = ["active", "idle"]
	if args.has("idle"):
		modes = ["idle"]
	elif args.has("active"):
		modes = ["active"]
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
	var md: String = _report(results, minutes, dt)
	var f := FileAccess.open(OUT_DIR.path_join("report.md"), FileAccess.WRITE)
	f.store_string(md)
	f.close()
	print("report: sim_out/report.md")
	var code: int = 0
	if args.has("strict"):
		for r: Dictionary in results:
			if r["mode"] == "active":
				for c: Dictionary in r["checks"]:
					if not bool(c["pass"]):
						code = 1
	quit(code)
	return false


static func run_mode(data: GameData, mode: String, minutes: float, dt: float, seed_value: int) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var core := GameCore.create(seed_value, data)
	core.emit_events = false
	var bot := SimBot.new(core, mode == "active")
	var total: float = minutes * 60.0
	var rows: Array = []
	var next_sample: float = SAMPLE_EVERY
	var prev_dmg: Dictionary = {}
	var prev_purch: int = 0
	var lens_share_5: float = -1.0
	var nan_seen: bool = false
	while core.state.time < total - 1e-6:
		bot.step(dt)
		core.tick(dt)
		if core.state.time + 1e-6 >= next_sample:
			next_sample += SAMPLE_EVERY
			var dmg: Dictionary = (core.state.stats["dmg_by_source"] as Dictionary).duplicate()
			var row: Dictionary = {
				"time": core.state.time,
				"gears": core.state.res("gears"),
				"blueprints": core.state.res("blueprints"),
				"gears_s": float(core.income.get("gears", 0.0)),
				"bp_s": float(core.income.get("blueprints", 0.0)),
				"enemies": core.battle.alive_count(),
				"kills": int(core.state.stats["kills"]),
				"falls": int(core.state.stats["falls"]),
				"purchases": bot.purchases.size() - prev_purch,
				"towers": "%d/%d/%d" % [core.state.tower_count("shooter"), core.state.tower_count("riveter"), core.state.tower_count("mortar")],
			}
			for s in SOURCES:
				row["dps_" + s] = (float(dmg.get(s, 0.0)) - float(prev_dmg.get(s, 0.0))) / SAMPLE_EVERY
			for r: String in core.state.resources:
				if not Num.is_valid(core.state.res(r)):
					nan_seen = true
			prev_dmg = dmg
			prev_purch = bot.purchases.size()
			rows.append(row)
			if lens_share_5 < 0.0 and core.state.time >= 300.0 - 1e-6:
				lens_share_5 = _lens_share(dmg)
	var final_dmg: Dictionary = core.state.stats["dmg_by_source"]
	var res: Dictionary = {
		"mode": mode, "minutes": minutes, "rows": rows, "purchases": bot.purchases,
		"boss_log": bot.boss_log, "stats": core.state.stats.duplicate(true),
		"resources": core.state.resources.duplicate(), "lens_share_5": lens_share_5,
		"lens_share_all": _lens_share(final_dmg), "nan": nan_seen,
		"real_ms": Time.get_ticks_msec() - t0, "nodes": core.state.nodes.duplicate(),
		"towers": core.state.towers.duplicate(), "upgrades": core.state.upgrades.duplicate(),
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


static func _analyse(r: Dictionary, total: float) -> void:
	var purchases: Array = r["purchases"]
	var boss_t: float = -1.0
	var attempts: int = 0
	for b: Dictionary in r["boss_log"]:
		if b["event"] == "defeated" and boss_t < 0.0:
			boss_t = float(b["t"])
		if b["event"] == "active":
			attempts += 1
	var phase_end: float = boss_t if boss_t > 0.0 else total
	# gaps between purchases
	var last: float = 0.0
	var max_gap: float = 0.0
	var max_gap_at: float = 0.0
	var in5: int = 0
	for p: Dictionary in purchases:
		var t: float = float(p["t"])
		if t <= 300.0:
			in5 += 1
		if t > phase_end:
			break
		if t - last > max_gap:
			max_gap = t - last
			max_gap_at = last
		last = t
	if phase_end - last > max_gap:
		max_gap = phase_end - last
		max_gap_at = last
	# novelty
	var novel: Array = []
	for p: Dictionary in purchases:
		if bool(p["novel"]):
			novel.append({"t": float(p["t"]), "what": str(p["id"])})
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
	var first: float = float(purchases[0]["t"]) if not purchases.is_empty() else -1.0
	var riv: float = _first_time(purchases, "node:r1_riveter")
	var mor: float = _first_time(purchases, "node:r1_mortar")
	r["first_purchase"] = first
	r["purchases_5min"] = in5
	r["riveter_t"] = riv
	r["mortar_t"] = mor
	r["boss_t"] = boss_t
	r["boss_attempts"] = attempts
	r["max_gap"] = max_gap
	r["max_gap_at"] = max_gap_at
	r["max_novel_gap"] = max_novel_gap
	r["novel"] = novel
	r["phase_end"] = phase_end
	var ls: float = float(r["lens_share_5"])
	r["checks"] = [
		_check("first purchase at 5–15 s", first >= 5.0 and first <= 15.0, _t(first)),
		_check(">= 10 purchases in first 5 min", in5 >= 10, str(in5)),
		_check("Клепальщик unlocked ~3 min (2:15–3:45)", riv >= 135.0 and riv <= 225.0, _t(riv)),
		_check("Мортира unlocked ~8–10 min (7:30–10:30)", mor >= 450.0 and mor <= 630.0, _t(mor)),
		_check("region-1 boss beaten at 12–15 min", boss_t >= 720.0 and boss_t <= 900.0, _t(boss_t)),
		_check("max gap between purchases <= 3:00 (until boss)", max_gap <= 180.0, "%s (after %s)" % [_t(max_gap), _t(max_gap_at)]),
		_check("something new every <= 5:00 (until boss)", max_novel_gap <= 300.0, _t(max_novel_gap)),
		_check("lens damage share 25–40% (first 5 min)", ls >= 0.25 and ls <= 0.40, "%.1f%%" % (ls * 100.0)),
		_check("no NaN/inf", not bool(r["nan"]), str(not bool(r["nan"]))),
	]


static func _check(name: String, ok: bool, value: String) -> Dictionary:
	return {"name": name, "pass": ok, "value": value}


static func _t(sec: float) -> String:
	if sec < 0.0:
		return "never"
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]


func _write_csv(r: Dictionary) -> void:
	var name: String = "timeline.csv" if r["mode"] == "active" else "timeline_%s.csv" % r["mode"]
	var f := FileAccess.open(OUT_DIR.path_join(name), FileAccess.WRITE)
	var cols: Array[String] = ["time", "gears", "blueprints", "gears_s", "bp_s"]
	for s in SOURCES:
		cols.append("dps_" + s)
	cols.append_array(["enemies", "kills", "falls", "purchases", "towers"])
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
		print("  [%s] %s: %s" % ["PASS" if c["pass"] else "FAIL", c["name"], c["value"]])
	print("  kills %d, moat falls %d, lens share all %.1f%%" % [int(r["stats"]["kills"]), int(r["stats"]["falls"]), float(r["lens_share_all"]) * 100.0])


func _report(results: Array, minutes: float, dt: float) -> String:
	var s: String = "# Simulation report\n\nGenerated by tools/simulate.sh: %.0f game minutes per mode, dt = %.3f s, bot = SimBot.\n" % [minutes, dt]
	s += "Active = lazy player keeps the lens over the densest group; idle = no cursor (auto lens).\n"
	s += "Pacing checks (DESIGN.md §9) are binding for the active mode; idle is informational.\n"
	for r: Dictionary in results:
		s += "\n## Mode: %s\n\n" % r["mode"]
		s += "Real time: %.1f s. Kills: %d, moat falls: %d (%.1f%%). Purchases: %d.\n\n" % [
			float(r["real_ms"]) / 1000.0, int(r["stats"]["kills"]), int(r["stats"]["falls"]),
			100.0 * float(r["stats"]["falls"]) / maxf(1.0, float(r["stats"]["kills"]) + float(r["stats"]["falls"])),
			(r["purchases"] as Array).size()]
		s += "### Checks\n\n| check | result | value |\n|---|---|---|\n"
		for c: Dictionary in r["checks"]:
			var tag: String = ("PASS" if c["pass"] else "FAIL") if r["mode"] == "active" else ("ok" if c["pass"] else "info")
			s += "| %s | %s | %s |\n" % [c["name"], tag, c["value"]]
		s += "\nLens share: first 5 min %.1f%%, whole run %.1f%%. Boss attempts: %d.\n" % [
			float(r["lens_share_5"]) * 100.0, float(r["lens_share_all"]) * 100.0, int(r["boss_attempts"])]
		s += "\n### Damage by source (whole run)\n\n| source | damage | share |\n|---|---|---|\n"
		var dmg: Dictionary = r["stats"]["dmg_by_source"]
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
		s += "\n### Timeline (every 60 s)\n\n| time | gears | bp | gears/s | bp/s | dps lens | dps towers | dps moat+scald | enemies | kills | falls | towers s/r/m |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n"
		for row: Dictionary in r["rows"]:
			if int(round(float(row["time"]))) % 60 != 0:
				continue
			var tw: float = float(row["dps_tower:shooter"]) + float(row["dps_tower:riveter"]) + float(row["dps_tower:mortar"])
			s += "| %s | %s | %s | %s | %s | %s | %s | %s | %d | %d | %d | %s |\n" % [
				_t(float(row["time"])), NumFmt.num(float(row["gears"])), NumFmt.num(float(row["blueprints"])),
				NumFmt.num(float(row["gears_s"])), NumFmt.num(float(row["bp_s"])), NumFmt.num(float(row["dps_lens"])),
				NumFmt.num(tw), NumFmt.num(float(row["dps_moat"]) + float(row["dps_scald"])),
				int(row["enemies"]), int(row["kills"]), int(row["falls"]), row["towers"]]
		s += "\n### Purchases (time, id, price, gap since previous)\n\n"
		var last: float = 0.0
		for p: Dictionary in r["purchases"]:
			var pr: PackedStringArray = []
			for k: String in p["price"]:
				pr.append("%s %s" % [NumFmt.num(float(p["price"][k])), k])
			s += "- %s  %s  (%s)  +%ds%s\n" % [_t(float(p["t"])), p["id"], ", ".join(pr), int(float(p["t"]) - last), "  **new**" if p["novel"] else ""]
			last = float(p["t"])
	return s
