class_name ViewKit
extends RefCounted
## Shared helpers for the game screen (scripts/view/*): visual config
## (config/visual.json → "game_view"), palette, art <-> screen coordinates,
## small UI builders and player-facing texts for purchases (stat diffs,
## "what's new"). One instance is created by MainGame and handed to every
## sub-view. See docs/VIEW.md.

const FONT_NUMBER: FontFile = preload("res://fonts/kotel_number.fnt")
const FONT_BOLD: FontFile = preload("res://fonts/kotel_bold.fnt")
const FONT_REGULAR: FontFile = preload("res://fonts/kotel_regular.fnt")
const FONT_TITLE: FontFile = preload("res://fonts/kotel_title.fnt")
const FLASH_SHADER: Shader = preload("res://assets/shaders/hit_flash.gdshader")
const LIGHT_SHADER: Shader = preload("res://scripts/view/shaders/hit_light.gdshader")

var core: GameCore
var cfg: Dictionary = {}
var origin: Vector2 = Vector2(0, 40)   ## screen position of art (0, 0)
var art_scale: float = 2.0
var flash_mat: ShaderMaterial          ## solid steam-white silhouette (towers: drop, tier-up)
var hit_mat: ShaderMaterial            ## light hit flash (enemies)
var crit_flash_mat: ShaderMaterial     ## light warm flash (enemy crits)
var _colors: Dictionary = {}


func _init(game_core: GameCore) -> void:
	core = game_core
	cfg = Config.value("visual", "game_view", {})
	var lay: Dictionary = SpriteLib.layout()
	var so: Array = lay.get("screen_offset", [0, 40])
	origin = Vector2(float(so[0]), float(so[1]))
	art_scale = float(SpriteLib.scale())
	flash_mat = _make_flash(str(v("flash.color", "steam_3")))
	hit_mat = _make_light(str(v("flash.color", "steam_3")), f("flash.strength", 0.55))
	crit_flash_mat = _make_light(str(v("flash.crit_color", "parchment_2")), f("flash.crit_strength", 0.7))


func _make_flash(color_name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLASH_SHADER
	m.set_shader_parameter("flash", 1.0)
	m.set_shader_parameter("flash_color", col(color_name))
	return m


## Light (non-silhouette) hit flash for enemies: the sprite keeps its shading.
func _make_light(color_name: String, strength: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LIGHT_SHADER
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("flash_color", col(color_name))
	return m


# --- config / palette --------------------------------------------------------

## Value from visual.json game_view by dotted path.
func v(key: String, default: Variant = null) -> Variant:
	return ConfigLoader.get_path_value(cfg, key, default)


func f(key: String, default: float = 0.0) -> float:
	return float(v(key, default))


func col(color_name: String) -> Color:
	if not _colors.has(color_name):
		_colors[color_name] = Config.color(color_name)
	return _colors[color_name]


## Colour of a damage number / loot text ("impact", "gears", "good"...).
func num_color(kind: String) -> Color:
	return col(str(v("num_colors." + kind, "parchment_2")))


func dmg_icon(dmg_type: String) -> String:
	return str(v("dmg_icons." + dmg_type, "dmg_impact"))


func res_icon(res: String) -> String:
	return str(v("res_icons." + res, "res_gears"))


func enemy_sprites(enemy_type: String) -> Dictionary:
	var m: Dictionary = v("enemy_sprites", {})
	return m.get(enemy_type, m.get("_default", {}))


func tower_base(tower_type: String) -> String:
	var m: Dictionary = v("tower_sprites", {})
	return str(m.get(tower_type, m.get("_default", "rifle")))


func tower_sprite(tower_type: String, tier: int) -> String:
	return "%s_t%d" % [tower_base(tower_type), clampi(tier - 1, 0, 2)]


## Muzzle relative to the tower's feet (art px): manifest `muzzle` − anchor; config fallback.
func muzzle(tower_type: String, tier: int = 1) -> Vector2:
	var sp: String = tower_sprite(tower_type, tier)
	var info: Dictionary = SpriteLib.info(sp)
	if info.has("muzzle"):
		var mz: Array = info["muzzle"]
		return Vector2(float(mz[0]), float(mz[1])) - SpriteLib.anchor(sp)
	var m: Dictionary = v("muzzle", {})
	var a: Array = m.get(tower_base(tower_type), m.get("_default", [12, -20]))
	return Vector2(float(a[0]), float(a[1]))


## Value as shown on screen: whole numbers from 10 up (no "504.5" noise), one decimal below.
static func shown(x: float) -> float:
	return floorf(x) if x >= 10.0 else x


# --- coordinates ---------------------------------------------------------------

## Core/screen position -> art pixel inside the world node (not rounded).
func to_art(p: Vector2) -> Vector2:
	return (p - origin) / art_scale


func to_screen(a: Vector2) -> Vector2:
	return a * art_scale + origin


# --- UI builders ------------------------------------------------------------------

func icon(sprite_name: String, px: int, frame: int = 0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = SpriteLib.texture(sprite_name, frame)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Sprite at an exact integer scale inside a fixed box (no blurry fractional scaling).
func sprite_box(sprite_name: String, box: Vector2, frame: int = 0) -> TextureRect:
	var r := TextureRect.new()
	var tex: Texture2D = SpriteLib.texture(sprite_name, frame)
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size = box
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if tex != null:
		var k: float = floorf(minf(box.x / tex.get_width(), box.y / tex.get_height()))
		if k >= 1.0:
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_SCALE
			r.custom_minimum_size = Vector2(tex.get_width(), tex.get_height()) * k
		else:
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


func label(text: String, variation: String = "", clip: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = StringName(variation)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if clip:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
	return l


func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func vbox(sep: int = 0) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


# --- purchase texts ------------------------------------------------------------------

func name_key(id: String) -> String:
	var p: PackedStringArray = GameCore.split_id(id)
	match p[0]:
		"tower":
			return str(core.data.towers[p[1]]["name"])
		"upg":
			return str(core.data.upgrades[p[1]]["name"])
	return GameData.node_name_key(p[1])


func desc_key(id: String) -> String:
	var p: PackedStringArray = GameCore.split_id(id)
	match p[0]:
		"tower":
			return str(core.data.towers[p[1]]["desc"])
		"upg":
			return str(core.data.upgrades[p[1]]["name"]) + "_DESC"
	return GameData.node_desc_key(p[1])


func res_short(r: String) -> String:
	return tr("RES_%s_SHORT" % r.to_upper())


func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: String in cost:
		parts.append("%s %s" % [Fmt.num(float(cost[r])), res_short(r)])
	return ", ".join(parts)


## Seconds until `cost` is affordable at the current income (INF if never, 0 if now).
func time_to_afford(cost: Dictionary) -> float:
	var worst: float = 0.0
	for r: String in cost:
		var need: float = float(cost[r]) - core.state.res(r)
		if need <= 0.0:
			continue
		var inc: float = float(core.income.get(r, 0.0))
		if inc <= 0.0:
			return INF
		worst = maxf(worst, need / inc)
	return worst


## Damage per second of one tower of `t` with stats `ts` (for "было → станет").
static func tower_dps(ts: Dictionary) -> float:
	return float(ts["dmg"]) * float(ts["multishot"]) / maxf(0.02, float(ts["reload"]))


func dmg_type_name(dmg_type: String) -> String:
	return tr("DMG_" + dmg_type.to_upper())


func status_name(s: String) -> String:
	return tr("STATUS_" + s.to_upper())


func tower_name(t: String) -> String:
	return tr(str(core.data.towers[t]["name"])) if core.data.towers.has(t) else t


func enemy_name(e: String) -> String:
	return tr(str(core.data.enemies[e]["name"])) if core.data.enemies.has(e) else e


func ability_name(a: String) -> String:
	return tr(str(core.data.abilities[a]["name"])) if core.data.abilities.has(a) else a


## Player-facing text of a behaviour key from Mods.behaviours() / novelty_of().
func behaviour_text(key: String) -> String:
	var p: PackedStringArray = key.split(":")
	var a: String = p[1] if p.size() > 1 else ""
	var b: String = p[2] if p.size() > 2 else ""
	match p[0]:
		"enemy":
			return tr("NEW_ENEMY") % enemy_name(a)
		"tower":
			return tr("NEW_TOWER") % tower_name(a)
		"tier":
			return tr("NEW_TIER") % tower_name(a)
		"pierce", "splash", "multishot", "knockback", "cluster", "crit_chain":
			return "%s: %s" % [tower_name(a), tr("BEH_" + p[0].to_upper())]
		"status":
			return "%s: %s" % [tower_name(a), status_name(b)]
		"region":
			return tr("NEW_REGION") % tr("REGION_" + a)
		"ability":
			return tr("NEW_MECHANISM") % ability_name(a)
		"ability_count":
			return "%s ×%s" % [ability_name(a), b]
		"ability_status":
			return "%s: %s" % [ability_name(a), status_name(b)]
		"lens_seek":
			return tr("BEH_LENS_SEEK")
		"lens_status":
			return "%s: %s" % [tr("UI_LENS"), status_name(a)]
		"lens_extra":
			return tr("BEH_LENS_EXTRA")
		"moat_curtain":
			return tr("BEH_MOAT_CURTAIN")
		"moat_slow":
			return tr("BEH_MOAT_SLOW")
		"boss":
			var bn: String = str(core.data.bosses[a]["name"]) if core.data.bosses.has(a) else a
			return tr("BEH_BOSS") % tr(bn)
		"armor_pierce":
			return tr("BEH_ARMOR_PIERCE") % tower_name(a)
		"dig":
			return tr("BEH_DIG") % tower_name(a)
		"lens_dig":
			return tr("BEH_LENS_DIG")
		"zone_status":
			return tr("BEH_ZONE_STATUS") % [tower_name(a), status_name(b)]
		"scald_shred":
			return tr("BEH_SCALD_SHRED")
		"wet_metal":
			return tr("BEH_WET_METAL")
		"producer":
			return tr("BEH_PRODUCER") % producer_name(a)
		"producer_out":
			return tr("BEH_PRODUCER_OUT") % [producer_name(a), tr("RES_%s_SHORT" % b.to_upper())]
		"ability_puddle":
			return tr("BEH_ABILITY_PUDDLE") % ability_name(a)
	return key


func producer_name(pid: String) -> String:
	return tr(str(core.data.producers[pid]["name"])) if core.data.producers.has(pid) else pid


## Short duration: "0.6с", "3с" (status lengths are often under a second).
func dur(seconds: float) -> String:
	if seconds >= 60.0:
		return Fmt.time(seconds)
	var q: float = 0.01 if seconds < 1.0 else 0.1
	return Fmt.num(snappedf(seconds, q) if seconds < 10.0 else roundf(seconds)) + tr("UI_SEC")


## Icon sprite for a behaviour key (toasts).
func behaviour_icon(key: String) -> String:
	var p: PackedStringArray = key.split(":")
	var a: String = p[1] if p.size() > 1 else ""
	match p[0]:
		"enemy":
			return str(enemy_sprites(a).get("walk", "scavenger_walk"))
		"tower", "tier", "pierce", "splash", "multishot", "knockback", "cluster", "crit_chain", "status", \
				"armor_pierce", "dig", "zone_status":
			return tower_sprite(a, core.tower_tier(a)) if core.data.towers.has(a) else "rifle_t0"
		"region":
			return "res_blueprints"
		"ability", "ability_count", "ability_status", "ability_puddle":
			return str(v("ability_icons." + a, "king_idle"))
		"producer", "producer_out":
			return str(v("producer_sprites." + a, "res_coal"))
		"scald_shred":
			return "dmg_steam"
		"wet_metal":
			return "wet_metal"
		"lens_seek", "lens_status", "lens_extra", "lens_dig":
			return "steam_lens"
		"moat_curtain", "moat_slow":
			return "steam_puff"
		"boss":
			return "boss_walk"
	return "gear_coin"


## "было → станет" lines for buying one more level of `id`:
## [{text, good (bool), icon}] — every stat that changes, numbers via Fmt.
func diff_lines(id: String, after: Mods = null, before: Mods = null) -> Array:
	if before == null:
		before = core.mods
	if after == null:
		after = core.preview_mods(id)
	var out: Array = []
	var p: PackedStringArray = GameCore.split_id(id)
	# a bonus to all weapons is one row ("Всё оружие"), not a damage row for every tower
	var g_k: float = after.global_dmg / maxf(1e-9, before.global_dmg)
	# towers
	for t: String in core.data.towers:
		var a: Dictionary = before.tower_stats[t]
		var b: Dictionary = after.tower_stats[t]
		var owned_a: int = core.state.tower_count(t)
		var owned_b: int = owned_a + (1 if id == "tower:" + t else 0)
		var unlocked: bool = before.unlocked_towers.has(t)
		if not unlocked:
			continue
		var icon_name: String = dmg_icon(str(a["dmg_type"]))
		if owned_b != owned_a:
			var da: float = tower_dps(a) * owned_a
			var db: float = tower_dps(b) * owned_b
			out.append({"text": tr("DIFF_TOTAL_DPS") % [Fmt.num(roundf(da) if da >= 10.0 else da), Fmt.num(roundf(db) if db >= 10.0 else db)],
				"good": true, "icon": icon_name})
			continue
		var pre: String = "" if p[0] == "upg" or p[1] == t else tower_name(t) + ": "
		_cmp(out, pre + tr("DIFF_DMG"), float(a["dmg"]) * g_k, float(b["dmg"]), icon_name)
		_cmp(out, pre + tr("DIFF_RATE"), 1.0 / float(a["reload"]), 1.0 / float(b["reload"]), icon_name)
		_cmp(out, pre + tr("DIFF_LIMIT"), float(a["limit"]), float(b["limit"]), icon_name)
		_cmp(out, pre + tr("DIFF_PIERCE"), float(a["pierce"]), float(b["pierce"]), icon_name)
		_cmp(out, pre + tr("DIFF_SPLASH"), float(a["splash"]), float(b["splash"]), icon_name)
		_cmp(out, pre + tr("DIFF_MULTISHOT"), float(a["multishot"]), float(b["multishot"]), icon_name)
		_cmp(out, pre + tr("DIFF_CRIT"), float(a["crit_chance"]) * 100.0, float(b["crit_chance"]) * 100.0, icon_name, "%")
		_cmp(out, pre + tr("DIFF_CRIT_MULT"), float(a["crit_mult"]), float(b["crit_mult"]), icon_name, "", true, "×")
		_cmp(out, pre + tr("DIFF_CRIT_CHAIN"), float(a["crit_chain"]), float(b["crit_chain"]), icon_name)
		_cmp(out, pre + tr("DIFF_TIER"), float(a["tier"]), float(b["tier"]), icon_name)
		_cmp(out, pre + tr("DIFF_KNOCKBACK"), float(a["knockback"]), float(b["knockback"]), icon_name)
		_cmp(out, pre + tr("DIFF_CLUSTER"), float(a["cluster"]), float(b["cluster"]), icon_name)
		_cmp(out, pre + tr("DIFF_RANGE"), float(a["range_max"]), float(b["range_max"]), icon_name)
		_cmp(out, pre + tr("DIFF_ARMOR_PIERCE"), float(a.get("armor_pierce", 0.0)) * 100.0,
			float(b.get("armor_pierce", 0.0)) * 100.0, icon_name, "%")
		_cmp(out, pre + tr("DIFF_CHAIN"), float(a.get("chain", 0)), float(b.get("chain", 0)), icon_name)
		_cmp(out, pre + tr("DIFF_BOUNCE"), float(a.get("bounces", 0)), float(b.get("bounces", 0)), icon_name)
		_status_rows(out, pre, a["statuses"], b["statuses"])
		_status_rows(out, (pre if pre != "" else tower_name(t) + ": ") + tr("DIFF_PUDDLE") + " — ",
			a.get("zone_statuses", {}), b.get("zone_statuses", {}))
	# lens
	var la: Dictionary = before.lens
	var lb: Dictionary = after.lens
	_cmp(out, tr("DIFF_LENS_DPS"), float(la["dmg"]) / float(la["interval"]), float(lb["dmg"]) / float(lb["interval"]), "dmg_steam")
	_cmp(out, tr("DIFF_LENS_RADIUS"), float(la["radius"]), float(lb["radius"]), "dmg_steam")
	_cmp(out, tr("DIFF_LENS_AUTO"), float(la["auto_mult"]) * 100.0, float(lb["auto_mult"]) * 100.0, "dmg_steam", "%")
	_cmp(out, tr("DIFF_LENS_COUNT"), 1.0 + float(la["extra"]), 1.0 + float(lb["extra"]), "dmg_steam")
	_status_rows(out, tr("UI_LENS") + ": ", la["statuses"], lb["statuses"])
	# moat, global
	_cmp(out, tr("DIFF_MOAT_DPS"), before.moat_dps, after.moat_dps, "dmg_steam")
	_cmp(out, tr("DIFF_MOAT_SLOW"), before.moat_slow * 100.0, after.moat_slow * 100.0, "dmg_steam", "%")
	_cmp(out, tr("DIFF_MOAT_WIDTH"), before.moat_width, after.moat_width, "dmg_steam")
	_cmp(out, tr("DIFF_GLOBAL_DMG"), before.global_dmg * 100.0, after.global_dmg * 100.0, "dmg_blast", "%")
	# global loot: one row instead of a loot row for every enemy
	var gl_a: float = before.stat("global_loot", "all", 1.0)
	var gl_b: float = after.stat("global_loot", "all", 1.0)
	var gb_a: float = before.stat("global_bp", "all", 1.0)
	var gb_b: float = after.stat("global_bp", "all", 1.0)
	_cmp(out, tr("DIFF_GLOBAL_LOOT"), gl_a * 100.0, gl_b * 100.0, "res_gears", "%")
	_cmp(out, tr("DIFF_GLOBAL_BP"), gb_a * 100.0, gb_b * 100.0, "res_blueprints", "%")
	var loot_k: Dictionary = {}   ## resource -> after/before global factor (divided out of enemy rows)
	for r: String in core.data.resource_ids:
		loot_k[r] = (gb_b / gb_a) if r == "blueprints" else (gl_b / gl_a)
	# abilities
	for ab: String in after.abilities:
		var bb: Dictionary = after.abilities[ab]
		if not before.abilities.has(ab):
			continue
		var aa: Dictionary = before.abilities[ab]
		_cmp(out, ability_name(ab) + ": " + tr("DIFF_DMG"), float(aa["dmg"]), float(bb["dmg"]), "dmg_steam")
		_cmp(out, ability_name(ab) + ": " + tr("DIFF_COUNT"), float(aa["count"]), float(bb["count"]), "dmg_steam")
		_status_rows(out, ability_name(ab) + ": ", aa["statuses"], bb["statuses"])
	# producers (workshops): output per cycle and cycle length
	for pid: String in after.producers:
		if not before.producers.has(pid):
			continue
		var pa: Dictionary = before.producers[pid]
		var pb: Dictionary = after.producers[pid]
		var pn: String = producer_name(pid)
		var oa: Dictionary = pa["output"]
		var ob: Dictionary = pb["output"]
		for r: String in ob:
			_cmp(out, tr("DIFF_PROD_OUT") % [pn, res_short(r)], float(oa.get(r, 0.0)), float(ob[r]), res_icon(r))
		var n0: int = out.size()
		_cmp(out, tr("DIFF_PROD_CYCLE") % pn, float(pa["interval"]), float(pb["interval"]), res_icon("coal"), "", false)
		if out.size() > n0:
			out[n0]["text"] = "%s %s → %s" % [tr("DIFF_PROD_CYCLE") % pn, dur(float(pa["interval"])), dur(float(pb["interval"]))]
	# enemies (baits: reward good, health bad); no name prefix when only one enemy changes
	var per_enemy: Dictionary = {}
	for e: String in before.unlocked_enemies:
		var ea: Dictionary = before.enemy_stats[e]
		var eb: Dictionary = after.enemy_stats[e]
		var lines: Array = []
		_cmp(lines, tr("DIFF_PACK"), float(ea["pack"]), float(eb["pack"]), "res_gears")
		var lra: Dictionary = ea["loot"]
		var lrb: Dictionary = eb["loot"]
		for r: String in lrb:
			# a global loot bonus is already its own row: compare this enemy's loot without it
			_cmp(lines, tr("DIFF_LOOT") % res_short(r), float(lra.get(r, 0.0)) * float(loot_k.get(r, 1.0)), float(lrb[r]), res_icon(r))
		_cmp(lines, tr("DIFF_HP"), float(ea["hp"]), float(eb["hp"]), "dmg_blast", "", false)
		if not lines.is_empty():
			per_enemy[e] = lines
	for e: String in per_enemy:
		for d: Dictionary in per_enemy[e]:
			if per_enemy.size() > 1:
				d["text"] = enemy_name(e) + ": " + str(d["text"])
			else:
				d["text"] = str(d["text"]).left(1).to_upper() + str(d["text"]).substr(1)
			out.append(d)
	return out


func _cmp(out: Array, what: String, a: float, b: float, icon_name: String, suffix: String = "", up_is_good: bool = true,
		prefix: String = "") -> void:
	if absf(a - b) <= maxf(1e-6, absf(a) * 1e-4):
		return
	var ra: float = roundf(a) if absf(a) >= 100.0 else a
	var rb: float = roundf(b) if absf(b) >= 100.0 else b
	out.append({"text": "%s %s%s%s → %s%s%s" % [what, prefix, Fmt.num(ra), suffix, prefix, Fmt.num(rb), suffix],
		"good": (b > a) == up_is_good, "icon": icon_name})


## On-hit status rows ("Ошпаривание 0% → 60% · 3с"): strength, and how long it lasts.
func _status_rows(out: Array, pre: String, sa: Dictionary, sb: Dictionary) -> void:
	for st: String in sb:
		var a: Dictionary = sa.get(st, {})
		var b: Dictionary = sb[st]
		var va: float = float(a.get("value", 0.0)) * 100.0
		var vb: float = float(b.get("value", 0.0)) * 100.0
		var da: float = float(a.get("duration", 0.0))
		var db: float = float(b.get("duration", 0.0))
		var n: int = out.size()
		var sname: String = status_name(st) if pre != "" else status_name(st).capitalize()
		var icon_name: String = "dmg_steam" if st == "scald" else "dmg_impact"
		# a status with no strength (stun: the enemy just stands still) is all about its length
		if va <= 0.0 and vb <= 0.0:
			if absf(da - db) > 1e-4:
				out.append({"text": "%s%s %s\u00a0→\u00a0%s" % [pre, sname, dur(da), dur(db)], "good": db > da, "icon": icon_name})
			continue
		_cmp(out, pre + sname, va, vb, icon_name, "%")
		if out.size() > n:
			out[n]["text"] = str(out[n]["text"]).replace(" → ", "\u00a0→\u00a0") + "\u00a0·\u00a0" + dur(db)
		elif absf(da - db) > 1e-4:
			out.append({"text": "%s%s %s\u00a0→\u00a0%s" % [pre, sname, dur(da), dur(db)], "good": db > da, "icon": icon_name})


## Short summary of a tower type (choice cards, unlock nodes): "Урон 10 · 1.7/с · дальн. 320".
func tower_summary(t: String, m: Mods = null) -> String:
	if m == null:
		m = core.mods
	var ts: Dictionary = m.tower_stats[t]
	return tr("SUM_TOWER") % [Fmt.num(float(ts["dmg"])), tr("DMG_" + str(ts["dmg_type"]).to_upper()),
		Fmt.num(1.0 / float(ts["reload"])), Fmt.num(float(ts["range_max"]))]


func enemy_summary(e: String, m: Mods = null) -> String:
	if m == null:
		m = core.mods
	var es: Dictionary = m.enemy_stats[e]
	return tr("SUM_ENEMY") % [Fmt.num(float(es["hp"])), Fmt.num(float(es["speed"])), loot_text(es["loot"])]


func loot_text(loot: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: String in loot:
		parts.append("%s %s" % [Fmt.num(float(loot[r])), res_short(r)])
	return ", ".join(parts)


## Novel keys of a purchase as text lines.
func novelty_lines(id: String) -> PackedStringArray:
	return novelty_texts(core.novelty_of(id))


## Every row the choice window / a card shows for going from `before` to `after` ("new" lines, then
## "было → станет"). Used by tests to prove each effect type in the config produces a visible row.
func change_rows(before: Mods, after: Mods, id: String = "node:_") -> PackedStringArray:
	var keys: Array = []
	var now: Dictionary = before.behaviours()
	for k: String in after.behaviours():
		if not now.has(k):
			keys.append(k)
	var out: PackedStringArray = novelty_texts(keys)
	for d: Dictionary in diff_lines(id, after, before):
		out.append(str(d["text"]))
	return out


func novelty_texts(keys: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for k: Variant in keys:
		var ks: String = str(k)
		var p: PackedStringArray = ks.split(":")
		if p[0] == "tier":
			continue
		# a new tower / mechanism brings its base behaviours: name it once
		if p.size() > 1 and p[0] != "tower" and p[0] != "ability" and p[0] != "enemy" \
				and (keys.has("tower:" + p[1]) or keys.has("ability:" + p[1])):
			continue
		out.append(behaviour_text(ks))
	return out


## Icon of a purchase that tells options apart: the tower / enemy it affects, the lens, the moat,
## the King's kettle; else the node kind icon (game_view.node_kind_icons).
func node_icon(id: String) -> String:
	var p: PackedStringArray = GameCore.split_id(id)
	if p[0] == "tower":
		return tower_sprite(p[1], core.tower_tier(p[1]))
	if p[0] == "upg":
		var t: String = str(core.data.upgrades[p[1]]["tower"])
		return tower_sprite(t, core.tower_tier(t))
	var kind: String = str(core.data.nodes[p[1]].get("kind", ""))
	for ef: Dictionary in core.data.node_effects(p[1]):
		var ty: String = str(ef["type"])
		var tgt: String = str(ef.get("target", ""))
		if core.data.towers.has(tgt):
			return tower_sprite(tgt, core.tower_tier(tgt))
		if core.data.enemies.has(tgt):
			return str(enemy_sprites(tgt).get("walk", "scavenger_walk"))
		if ty.begins_with("lens"):
			return "steam_lens"
		if ty.begins_with("moat"):
			return "steam_push"
		if ty.begins_with("ability") or ty == "unlock_ability":
			return str(v("ability_icons." + tgt, "king_tea"))
		if ty.begins_with("producer") or ty == "unlock_producer":
			return str(v("producer_sprites." + tgt, "res_coal"))
		if ty == "call_boss" and core.data.bosses.has(tgt):
			return str(enemy_sprites(str(core.data.bosses[tgt]["enemy"])).get("walk", "boss_walk"))
	var icon_name: String = str(v("node_kind_icons." + kind, "res_blueprints"))
	return icon_name if icon_name != "enemy" and icon_name != "tower" else "res_blueprints"
