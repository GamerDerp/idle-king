class_name Battle
extends RefCounted
## The battlefield: enemies, towers on the wall, projectiles, steam lens,
## moat, pack spawner and boss fights. Transient (not saved). Driven by
## GameCore.tick() in steps of at most ~0.1 s; results don't depend on frame
## rate beyond floating point. All randomness comes from the shared core RNG.
##
## Coordinates are logical units equal to screen pixels at 1280x720:
## fortress wall x≈100–210, moat edge x = moat_x (290), spawn x≈900, lane y 130–610.

## One enemy on the field. The view reads these fields every frame.
class Enemy extends RefCounted:
	var uid: int = 0
	var type: String = ""
	var role: String = "normal"     ## normal / escort / boss
	var hp: float = 1.0
	var max_hp: float = 1.0
	var pos: Vector2 = Vector2.ZERO
	var lane_y: float = 0.0
	var phase: float = 0.0
	var speed: float = 20.0
	var radius: float = 10.0
	var resist: Dictionary = {}
	var loot: Dictionary = {}
	var pending: float = 0.0        ## damage of bullets already flying at it
	var alive: bool = true
	var age: float = 0.0
	var scald_t: float = 0.0        ## seconds of "scalded" left (view: steam on enemy)
	var scald_dps: float = 0.0


## A projectile in flight. kind: bullet (homing), rivet (straight, pierces), shell (lobbed, splash).
class Projectile extends RefCounted:
	var uid: int = 0
	var kind: String = "bullet"
	var tower: String = ""
	var pos: Vector2 = Vector2.ZERO
	var start: Vector2 = Vector2.ZERO
	var dest: Vector2 = Vector2.ZERO
	var dir: Vector2 = Vector2.RIGHT
	var speed: float = 600.0
	var target: Enemy = null
	var dmg: float = 0.0
	var dmg_type: String = "impact"
	var crit: bool = false
	var pierce_left: int = 0
	var hit: Dictionary = {}
	var splash: float = 0.0
	var t: float = 0.0              ## shell: time in flight
	var flight: float = 1.0         ## shell: total flight time (view: arc = t/flight)
	var expected: float = 0.0
	var alive: bool = true


## A tower standing on the wall.
class Tower extends RefCounted:
	var type: String = ""
	var index: int = 0
	var pos: Vector2 = Vector2.ZERO
	var cd: float = 0.0
	var shots: int = 0
	var aim: Vector2 = Vector2.ZERO


var data: GameData
var state: GameState
var mods: Mods
var rng: RandomNumberGenerator
var events: Array = []
var emit: bool = true

var enemies: Array[Enemy] = []
var projectiles: Array[Projectile] = []
var towers: Array[Tower] = []

## Lens (read by the view): position, mode "manual"/"auto"/"seek", radius from mods.lens.
var lens_pos: Vector2 = Vector2.ZERO
var lens_mode: String = "auto"
var lens_idle: float = 0.0
var _cursor_last: Vector2 = Vector2(-1.0e9, -1.0e9)
var _lens_phase: float = 0.0
var _lens_acc: float = 0.0
var _seek_timer: float = 0.0
var _seek_target: Vector2 = Vector2.ZERO

## Spawner.
var pack_timer: float = 0.0
var packs_spawned: int = 0
var _pack_acc: Dictionary = {}

## Boss fight in progress (boss_enemy is null otherwise).
var boss_id: String = ""
var boss_enemy: Enemy = null
var boss_outcome: String = ""       ## "defeated" / "retreated" until GameCore consumes it
var _boss_t: float = 0.0
var _boss_queue: Array = []

var _next_uid: int = 1
var _any_dead: bool = false

# config cache
var moat_x: float
var spawn_x: float
var end_x: float
var y_min: float
var y_max: float
var _jitter: float
var _pack_interval: float
var _max_enemies: int
var _curtain_w: float
var _drift: float


func _init(game_data: GameData, game_state: GameState, game_mods: Mods, shared_rng: RandomNumberGenerator) -> void:
	data = game_data
	state = game_state
	mods = game_mods
	rng = shared_rng
	moat_x = data.field("moat_x", 290.0)
	spawn_x = data.field("spawn_x", 900.0)
	end_x = data.field("end_x", 980.0)
	y_min = data.field("y_min", 130.0)
	y_max = data.field("y_max", 610.0)
	_jitter = data.field("spawn_jitter_x", 40.0)
	_pack_interval = maxf(0.2, float(data.waves.get("pack_interval", 3.0)))
	_max_enemies = int(data.waves.get("max_enemies", 300))
	_curtain_w = float(data.waves.get("curtain_width", 50.0))
	_drift = float(data.waves.get("lane_drift", 0.0))
	pack_timer = float(data.waves.get("first_pack_at", 0.5))
	var ap: Dictionary = data.lens.get("auto_path", {})
	lens_pos = Vector2(float(ap.get("cx", 600.0)) + float(ap.get("rx", 200.0)), float(ap.get("cy", 370.0)))
	sync_towers()


func set_mods(m: Mods) -> void:
	mods = m
	sync_towers()


## Rebuilds tower instances to match state.towers (keeps cooldowns of existing ones).
func sync_towers() -> void:
	var old: Dictionary = {}
	for tw in towers:
		old["%s#%d" % [tw.type, tw.index]] = tw
	towers.clear()
	for t: String in data.towers:
		for i in state.tower_count(t):
			var key: String = "%s#%d" % [t, i]
			var tw: Tower = old.get(key, null)
			if tw == null:
				tw = Tower.new()
				tw.type = t
				tw.index = i
				tw.pos = tower_slot(t, i)
				tw.cd = fmod(i * 0.137, 0.3)  # stagger without touching the RNG
			towers.append(tw)


## Wall position of the i-th tower of a type: slots fill from the middle of the wall outwards.
func tower_slot(t: String, i: int) -> Vector2:
	var slots: int = maxi(1, int(data.wall.get("slots", 10)))
	var wy0: float = float(data.wall.get("y_min", 150.0))
	var wy1: float = float(data.wall.get("y_max", 600.0))
	var col: int = i / slots
	var k: int = i % slots
	var mid: int = slots / 2
	var slot: int = mid - (k + 1) / 2 if k % 2 == 1 else mid + k / 2
	slot = clampi(slot, 0, slots - 1)
	var x: float = float(data.towers[t].get("column_x", 200.0)) - col * float(data.wall.get("row_offset_x", 14.0))
	return Vector2(x, wy0 + (slot + 0.5) * (wy1 - wy0) / slots)


func tick(dt: float) -> void:
	_spawn(dt)
	_move(dt)
	_dots(dt)
	_fire_towers(dt)
	_move_projectiles(dt)
	_lens(dt)
	if _any_dead:
		_cleanup()


# --- spawning --------------------------------------------------------------

func _spawn(dt: float) -> void:
	if boss_enemy != null:
		_boss_t += dt
		while not _boss_queue.is_empty() and float(_boss_queue[0]["at"]) <= _boss_t:
			var q: Dictionary = _boss_queue.pop_front()
			_spawn_group(str(q["type"]), int(q["count"]))
		if bool(data.waves.get("boss_pauses_packs", true)):
			return
	pack_timer -= dt
	var guard: int = 0
	while pack_timer <= 0.0 and guard < 8:
		pack_timer += _pack_interval
		guard += 1
		_spawn_pack()


func _spawn_pack() -> void:
	packs_spawned += 1
	var center_y: float = rng.randf_range(y_min, y_max)
	for t: String in mods.unlocked_enemies:
		var acc: float = float(_pack_acc.get(t, 0.0)) + float(mods.enemy_stats[t]["pack"])
		var n: int = int(floor(acc + 1e-9))
		_pack_acc[t] = acc - n
		for i in n:
			_spawn_enemy(t, center_y)
	if emit:
		events.append({"type": "pack_spawned", "index": packs_spawned})


func _spawn_group(t: String, count: int) -> void:
	var center_y: float = rng.randf_range(y_min, y_max)
	for i in count:
		_spawn_enemy(t, center_y)


func _spawn_enemy(t: String, center_y: float, at: Vector2 = Vector2.INF) -> Enemy:
	if enemies.size() >= _max_enemies:
		return null
	var es: Dictionary = mods.enemy_stats[t]
	var e := Enemy.new()
	e.uid = _next_uid
	_next_uid += 1
	e.type = t
	e.role = str(es["role"])
	e.max_hp = float(es["hp"])
	e.hp = e.max_hp
	e.speed = float(es["speed"]) * rng.randf_range(0.92, 1.08)
	e.radius = float(es["radius"])
	e.resist = es["resist"]
	e.loot = es["loot"]
	e.phase = rng.randf() * TAU
	if at == Vector2.INF:
		var y: float = clampf(center_y + rng.randfn(0.0, (y_max - y_min) * 0.2), y_min, y_max)
		e.pos = Vector2(spawn_x + rng.randf() * _jitter, y)
	else:
		e.pos = at
	e.lane_y = e.pos.y
	enemies.append(e)
	if emit:
		events.append({"type": "enemy_spawned", "uid": e.uid, "enemy": t, "role": e.role, "pos": e.pos})
	return e


## Puts one enemy of `t` at `pos` (tests, debug tools).
func spawn_enemy_at(t: String, pos: Vector2) -> Enemy:
	return _spawn_enemy(t, pos.y, pos)


## Starts a boss fight. Returns false if one is already running or the id is unknown.
func start_boss(id: String) -> bool:
	if boss_enemy != null or not data.bosses.has(id):
		return false
	var b: Dictionary = data.bosses[id]
	boss_id = id
	_boss_t = 0.0
	_boss_queue = []
	for q: Dictionary in b.get("escorts", []):
		_boss_queue.append(q)
	_boss_queue.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return float(a["at"]) < float(c["at"]))
	boss_enemy = _spawn_enemy(str(b["enemy"]), 0.0, Vector2(spawn_x + 20.0, (y_min + y_max) * 0.5))
	if boss_enemy == null:
		return false
	if emit:
		events.append({"type": "boss_spawned", "boss": id, "uid": boss_enemy.uid, "hp": boss_enemy.max_hp})
	return true


func _end_boss(outcome: String) -> void:
	boss_outcome = outcome
	if emit:
		var pos: Vector2 = boss_enemy.pos
		events.append({"type": "boss_" + outcome, "boss": boss_id, "pos": pos})
	boss_enemy = null
	_boss_queue = []


# --- movement, moat, damage over time ----------------------------------------

func _move(dt: float) -> void:
	for e in enemies:
		if not e.alive:
			continue
		e.age += dt
		e.pos.x -= e.speed * dt
		if _drift > 0.0:
			e.pos.y = clampf(e.lane_y + sin(e.age * 1.7 + e.phase) * _drift, y_min, y_max)
		if e.pos.x <= moat_x:
			if e.role == "boss":
				e.alive = false
				_any_dead = true
				_end_boss("retreated")
			else:
				_fall(e)


func _fall(e: Enemy) -> void:
	e.alive = false
	_any_dead = true
	state.stats["falls"] = int(state.stats["falls"]) + 1
	state.add_stat_in("falls_by_type", e.type, 1.0)
	if emit:
		events.append({"type": "enemy_fell_in_moat", "uid": e.uid, "enemy": e.type, "pos": e.pos})


func _dots(dt: float) -> void:
	var moat_dps: float = mods.moat_dps
	var curtain_x: float = moat_x + _curtain_w
	for e in enemies:
		if not e.alive:
			continue
		if e.scald_t > 0.0:
			var d: float = e.scald_dps * minf(dt, e.scald_t)
			e.scald_t -= dt
			damage(e, d, "steam", false, "scald", true)
		if moat_dps > 0.0 and e.alive and e.pos.x < curtain_x:
			damage(e, moat_dps * dt, "steam", false, "moat", true)


# --- towers & projectiles ---------------------------------------------------

func _fire_towers(dt: float) -> void:
	for tw in towers:
		var st: Dictionary = mods.tower_stats[tw.type]
		tw.cd -= dt
		var guard: int = 0
		while tw.cd <= 0.0 and guard < 4:
			guard += 1
			var target: Enemy = _pick_target(tw, st)
			if target == null:
				tw.cd = 0.0
				break
			_fire(tw, st, target)
			tw.cd += float(st["reload"])


func _pick_target(tw: Tower, st: Dictionary) -> Enemy:
	var rmin: float = float(st["range_min"])
	var rmax: float = float(st["range_max"])
	var shell: bool = st["projectile"] == "shell"
	var best: Enemy = null
	var best_x: float = INF
	if not shell:
		# closest to the moat first, but skip enemies this tower cannot finish
		# before they fall in (otherwise a weak defence wastes every shot)
		var dmg: float = maxf(0.001, float(st["dmg"]))
		var reload: float = float(st["reload"])
		var inv_speed: float = 1.0 / maxf(1.0, float(st["proj_speed"]))
		var doomed: Enemy = null
		var doomed_x: float = INF
		for e in enemies:
			if not e.alive:
				continue
			var dx: float = e.pos.x - tw.pos.x
			var left: float = e.hp - e.pending
			if dx < rmin or dx > rmax or left <= 0.0 or e.pos.x >= best_x:
				continue
			var eff: float = dmg * (1.0 - float(e.resist.get(st["dmg_type"], 0.0)))
			var shots: float = ceilf(left / maxf(0.001, eff))
			var t_need: float = (shots - 1.0) * reload + dx * inv_speed
			var t_left: float = (e.pos.x - moat_x) / maxf(1.0, e.speed)
			if t_need <= t_left:
				best_x = e.pos.x
				best = e
			elif e.pos.x < doomed_x:
				doomed_x = e.pos.x
				doomed = e
		return best if best != null else doomed
	# shells: the enemy with most neighbours inside the splash, ties -> closest to the moat
	var r: float = float(st["splash"])
	var best_n: int = -1
	var cands: Array[Enemy] = []
	for e in enemies:
		if e.alive and e.hp - e.pending > 0.0:
			var dx: float = e.pos.x - tw.pos.x
			if dx >= rmin and dx <= rmax:
				cands.append(e)
	for c in cands:
		var n: int = 0
		for o in cands:
			if absf(o.pos.x - c.pos.x) <= r and c.pos.distance_squared_to(o.pos) <= r * r:
				n += 1
		if n > best_n or (n == best_n and c.pos.x < best_x):
			best_n = n
			best_x = c.pos.x
			best = c
	return best


func _fire(tw: Tower, st: Dictionary, target: Enemy) -> void:
	var p := Projectile.new()
	p.uid = _next_uid
	_next_uid += 1
	p.kind = str(st["projectile"])
	p.tower = tw.type
	p.pos = tw.pos
	p.start = tw.pos
	p.speed = float(st["proj_speed"])
	p.dmg_type = str(st["dmg_type"])
	p.crit = rng.randf() < float(st["crit_chance"])
	p.dmg = float(st["dmg"]) * (float(st["crit_mult"]) if p.crit else 1.0)
	p.target = target
	var lead_t: float = tw.pos.distance_to(target.pos) / maxf(1.0, p.speed)
	match p.kind:
		"rivet":
			p.pierce_left = int(st["pierce"])
			var aim: Vector2 = target.pos + Vector2(-target.speed * lead_t, 0.0)
			p.dir = (aim - tw.pos).normalized()
			p.dest = aim
			p.target = null
		"shell":
			p.flight = clampf(lead_t, 0.6, 2.0)
			p.dest = target.pos + Vector2(-target.speed * p.flight, 0.0)
			p.splash = float(st["splash"])
			p.expected = p.dmg * (1.0 - float(target.resist.get(p.dmg_type, 0.0)))
			target.pending += p.expected
		_:
			p.dest = target.pos
			p.expected = p.dmg * (1.0 - float(target.resist.get(p.dmg_type, 0.0)))
			target.pending += p.expected
	tw.shots += 1
	tw.aim = p.dest
	projectiles.append(p)
	if emit:
		events.append({"type": "projectile_fired", "uid": p.uid, "kind": p.kind, "tower": tw.type,
			"tower_index": tw.index, "from": tw.pos, "to": p.dest, "crit": p.crit})


func _move_projectiles(dt: float) -> void:
	var any_dead: bool = false
	for p in projectiles:
		match p.kind:
			"bullet":
				_move_bullet(p, dt)
			"rivet":
				_move_rivet(p, dt)
			"shell":
				_move_shell(p, dt)
		if not p.alive:
			any_dead = true
	if any_dead:
		var keep: Array[Projectile] = []
		for p in projectiles:
			if p.alive:
				keep.append(p)
		projectiles = keep


func _move_bullet(p: Projectile, dt: float) -> void:
	var tgt: Enemy = p.target
	if tgt != null and tgt.alive:
		p.dest = tgt.pos
	var step: float = p.speed * dt
	if p.pos.distance_to(p.dest) <= step:
		p.pos = p.dest
		p.alive = false
		if tgt != null and tgt.alive:
			tgt.pending = maxf(0.0, tgt.pending - p.expected)
			_tower_hit(tgt, p)
	else:
		p.pos = p.pos.move_toward(p.dest, step)


func _move_rivet(p: Projectile, dt: float) -> void:
	var a: Vector2 = p.pos
	var b: Vector2 = a + p.dir * p.speed * dt
	p.pos = b
	var seg: Vector2 = b - a
	var len2: float = maxf(seg.length_squared(), 1e-6)
	var hits: Array = []
	var minx: float = minf(a.x, b.x) - 30.0
	var maxx: float = maxf(a.x, b.x) + 30.0
	for e in enemies:
		if not e.alive or e.pos.x < minx or e.pos.x > maxx or p.hit.has(e.uid):
			continue
		var tt: float = clampf((e.pos - a).dot(seg) / len2, 0.0, 1.0)
		var closest: Vector2 = a + seg * tt
		var rr: float = e.radius + 3.0
		if closest.distance_squared_to(e.pos) <= rr * rr:
			hits.append([tt, e])
	if hits.size() > 1:
		hits.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	for h: Array in hits:
		var e: Enemy = h[1]
		p.hit[e.uid] = true
		_tower_hit(e, p)
		p.pierce_left -= 1
		if p.pierce_left < 0:
			p.alive = false
			return
	if b.x > end_x or b.x < 0.0 or b.y < y_min - 60.0 or b.y > y_max + 60.0:
		p.alive = false


func _move_shell(p: Projectile, dt: float) -> void:
	p.t += dt
	p.pos = p.start.lerp(p.dest, minf(1.0, p.t / p.flight))
	if p.t < p.flight:
		return
	p.alive = false
	if p.target != null:
		p.target.pending = maxf(0.0, p.target.pending - p.expected)
	if emit:
		events.append({"type": "shell_exploded", "uid": p.uid, "pos": p.dest, "radius": p.splash, "crit": p.crit})
	for e in enemies:
		if not e.alive:
			continue
		var rr: float = p.splash + e.radius * 0.5
		if absf(e.pos.x - p.dest.x) <= rr and e.pos.distance_squared_to(p.dest) <= rr * rr:
			_tower_hit(e, p)


func _tower_hit(e: Enemy, p: Projectile) -> void:
	var dealt: float = damage(e, p.dmg, p.dmg_type, p.crit, "tower:" + p.tower)
	if not e.alive:
		return
	var sts: Dictionary = mods.tower_stats[p.tower]["statuses"]
	if sts.has("scald"):
		var s: Dictionary = sts["scald"]
		var dur: float = maxf(0.1, float(s["duration"]))
		var dps: float = dealt * float(s["value"]) / dur
		if e.scald_t <= 0.0 or dps > e.scald_dps:
			e.scald_dps = dps
		e.scald_t = dur
		if emit:
			events.append({"type": "enemy_status", "uid": e.uid, "status": "scald", "pos": e.pos, "duration": dur})


## Deals damage after resistances. Returns the damage applied (before overkill clamp).
## quiet = no enemy_hit event (damage over time ticks).
func damage(e: Enemy, amount: float, dmg_type: String, crit: bool, source: String, quiet: bool = false) -> float:
	if not e.alive or amount <= 0.0:
		return 0.0
	var eff: float = amount * (1.0 - float(e.resist.get(dmg_type, 0.0)))
	if eff <= 0.0:
		return 0.0
	var dealt: float = minf(eff, e.hp)
	e.hp -= eff
	var bysrc: Dictionary = state.stats["dmg_by_source"]
	bysrc[source] = float(bysrc.get(source, 0.0)) + dealt
	if emit and not quiet:
		events.append({"type": "enemy_hit", "uid": e.uid, "amount": eff, "dmg_type": dmg_type,
			"crit": crit, "pos": e.pos, "source": source})
	if e.hp <= 0.0:
		_kill(e)
	return eff


func _kill(e: Enemy) -> void:
	e.alive = false
	e.hp = 0.0
	_any_dead = true
	for r: String in e.loot:
		state.add_res(r, float(e.loot[r]))
	state.stats["kills"] = int(state.stats["kills"]) + 1
	state.add_stat_in("kills_by_type", e.type, 1.0)
	if emit:
		events.append({"type": "enemy_killed", "uid": e.uid, "enemy": e.type, "pos": e.pos, "loot": e.loot})
	if e.role == "boss" and e == boss_enemy:
		_end_boss("defeated")


func _cleanup() -> void:
	_any_dead = false
	var keep: Array[Enemy] = []
	for e in enemies:
		if e.alive:
			keep.append(e)
	enemies = keep


# --- steam lens -------------------------------------------------------------

func in_field(p: Vector2) -> bool:
	return p.x >= moat_x - 40.0 and p.x <= spawn_x + 40.0 and p.y >= y_min - 60.0 and p.y <= y_max + 60.0


func _lens(dt: float) -> void:
	var L: Dictionary = mods.lens
	var idle_to_auto: float = data.lens_value("idle_to_auto", 2.0)
	var manual: bool = false
	if state.cursor_active and in_field(state.cursor_pos):
		if state.cursor_pos.distance_squared_to(_cursor_last) > 0.25:
			lens_idle = 0.0
			_cursor_last = state.cursor_pos
		else:
			lens_idle += dt
		manual = lens_idle < idle_to_auto
	else:
		lens_idle = idle_to_auto
	if manual:
		lens_pos = state.cursor_pos
		lens_mode = "manual"
	elif bool(L["seek"]) and not enemies.is_empty():
		_seek_timer -= dt
		if _seek_timer <= 0.0:
			_seek_timer = data.lens_value("seek_retarget", 0.5)
			_seek_target = densest_point(float(L["radius"]))
		lens_pos = lens_pos.move_toward(_seek_target, data.lens_value("seek_speed", 150.0) * dt)
		lens_mode = "seek"
	else:
		var ap: Dictionary = data.lens.get("auto_path", {})
		_lens_phase = fmod(_lens_phase + dt * TAU / maxf(1.0, float(ap.get("period", 14.0))), TAU)
		var target := Vector2(float(ap.get("cx", 600.0)) + cos(_lens_phase) * float(ap.get("rx", 200.0)),
			float(ap.get("cy", 370.0)) + sin(_lens_phase) * float(ap.get("ry", 150.0)))
		lens_pos = lens_pos.move_toward(target, data.lens_value("auto_speed", 160.0) * dt)
		lens_mode = "auto"
	_lens_acc += dt
	var interval: float = float(L["interval"])
	var n: int = 0
	while _lens_acc >= interval and n < 100:
		_lens_acc -= interval
		n += 1
	if n == 0:
		return
	var dmg: float = float(L["dmg"]) * n * (1.0 if manual else float(L["auto_mult"]))
	var radius: float = float(L["radius"])
	var hf: float = data.lens_value("hit_radius_factor", 0.5)
	for e in enemies:
		if not e.alive or absf(e.pos.x - lens_pos.x) > radius + e.radius:
			continue
		var rr: float = radius + e.radius * hf
		if e.pos.distance_squared_to(lens_pos) <= rr * rr:
			damage(e, dmg, str(L["dmg_type"]), false, "lens")
	if emit:
		events.append({"type": "lens_tick", "pos": lens_pos, "radius": radius, "mode": lens_mode})


## Position of the enemy with the most neighbours within `radius` (ties -> closest
## to the moat). Used by the lens "Наводчик" upgrade and the bot's cursor.
## Sorted sweep, so roughly O(n·k) instead of O(n²).
func densest_point(radius: float) -> Vector2:
	var alive: Array[Enemy] = []
	for e in enemies:
		if e.alive:
			alive.append(e)
	if alive.is_empty():
		return lens_pos
	alive.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.pos.x < b.pos.x)
	var r2: float = radius * radius
	var best: int = 0
	var best_n: int = -1
	var lo: int = 0
	var count: int = alive.size()
	for i in count:
		var c: Vector2 = alive[i].pos
		while alive[lo].pos.x < c.x - radius:
			lo += 1
		var n: int = 0
		var j: int = lo
		while j < count and alive[j].pos.x <= c.x + radius:
			if alive[j].pos.distance_squared_to(c) <= r2:
				n += 1
			j += 1
		if n > best_n:
			best_n = n
			best = i
	return alive[best].pos


## Count of alive enemies (view/sim helper).
func alive_count() -> int:
	var n: int = 0
	for e in enemies:
		if e.alive:
			n += 1
	return n
