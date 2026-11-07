class_name Battle
extends RefCounted
## The battlefield: enemies, towers on the wall, projectiles, steam lenses,
## moat, mechanisms (abilities), burning puddles, pack spawner and boss fights.
## Transient (not saved). Driven by GameCore.tick() in steps of at most ~0.1 s.
## All randomness comes from the shared core RNG; all numbers from config.
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
	var speed: float = 20.0         ## base walking speed (before slows)
	var radius: float = 10.0
	var resist: Dictionary = {}
	var loot: Dictionary = {}
	var pending: float = 0.0        ## damage of bullets/shells already flying at it
	var alive: bool = true
	var age: float = 0.0
	var scald_t: float = 0.0        ## seconds of "scalded" left (view: steam on the enemy)
	var scald_dps: float = 0.0
	var scald_src: String = ""      ## who scalded it last (stats: dot_by_owner)
	var slow_t: float = 0.0         ## seconds of slow left (view: frost/steam drag)
	var slow_f: float = 0.0         ## speed reduction fraction
	var underground: bool = false   ## burrowed: untouchable, untargetable (view: dirt mound)
	var burrow: Dictionary = {}     ## {under, over} seconds, empty = never burrows
	var burrow_t: float = 0.0
	var dot_acc: Dictionary = {}    ## source -> damage accumulated for the next enemy_dot event
	var dot_timer: float = 0.0
	var dot_total: float = 0.0      ## all damage-over-time this enemy took
	var immune: Dictionary = {}     ## "slow" / "stun" / "knockback" -> true (heavy carts)
	var stun_t: float = 0.0         ## seconds stunned left: stands still (view: stars over the head)
	var under_speed: float = 1.0    ## speed factor while burrowed
	var front_armor: float = 0.0    ## fraction of direct-fire damage blocked (view: armour plate, "dzing" on hit)
	var charge: Dictionary = {}     ## {every, duration, mult}: periodic dash
	var charge_t: float = 0.0
	var charging: bool = false      ## dashing now (view: dust trail)
	var shield: Dictionary = {}     ## {frac, block, breakers}
	var shield_hp: float = 0.0      ## > 0: shield up (view: copper helmet), only `breakers` damage removes it
	var shield_max: float = 0.0
	var split: Dictionary = {}      ## {type, count}: splits on death
	var parent_uid: int = 0         ## split child: uid of the enemy it came from
	var bait: int = 0               ## bait levels on this type (view: loot sacks)

	func cur_speed() -> float:
		if stun_t > 0.0:
			return 0.0
		var v: float = speed * (1.0 - slow_f if slow_t > 0.0 else 1.0)
		if underground:
			v *= under_speed
		if charging:
			v *= float(charge["mult"])
		return v


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
	var flight: float = 1.0         ## shell: total flight time (view: arc height by t/flight)
	var expected: float = 0.0
	var fragment: bool = false      ## shell: cluster fragment (smaller arc)
	var bounces_left: int = 0       ## ricochet: jumps left
	var bounce: int = 0             ## ricochet: jumps made
	var alive: bool = true


## A tower standing on the wall.
class Tower extends RefCounted:
	var type: String = ""
	var index: int = 0
	var slot: int = 0
	var pos: Vector2 = Vector2.ZERO
	var cd: float = 0.0
	var shots: int = 0
	var aim: Vector2 = Vector2.ZERO


## Burning / boiling ground left by a shell.
class Zone extends RefCounted:
	var uid: int = 0
	var pos: Vector2 = Vector2.ZERO
	var radius: float = 40.0
	var dps: float = 10.0
	var dmg_type: String = "steam"
	var t: float = 0.0
	var duration: float = 3.0
	var statuses: Dictionary = {}   ## status id -> {value, duration}, refreshed on everyone inside (tar puddle: slow)
	var tower: String = ""


## A steam lens. Index 0 follows the cursor; extra lenses (trophies) are always automatic.
class Lens extends RefCounted:
	var index: int = 0
	var pos: Vector2 = Vector2.ZERO
	var mode: String = "auto"       ## manual / auto / seek
	var phase: float = 0.0
	var acc: float = 0.0
	var timer: float = 0.0
	var target: Vector2 = Vector2.ZERO
	var has_target: bool = false
	var sweep: float = 0.0


var data: GameData
var state: GameState
var mods: Mods
var rng: RandomNumberGenerator
var events: Array = []
var emit: bool = true

var enemies: Array[Enemy] = []
var projectiles: Array[Projectile] = []
var towers: Array[Tower] = []
var zones: Array[Zone] = []
var lenses: Array[Lens] = []        ## lenses[0] = the player's lens

## Main lens (read by the view): position, mode "manual"/"auto"/"seek".
var lens_pos: Vector2:
	get: return lenses[0].pos
var lens_mode: String:
	get: return lenses[0].mode
var lens_idle: float = 0.0
var _cursor_last: Vector2 = Vector2(-1.0e9, -1.0e9)

## Mechanisms: ability id -> seconds since last use.
var ability_timers: Dictionary = {}
## Producers (Угольная шахта): id -> seconds into the current cycle (progress = t / mods.producers[id].interval).
var producer_t: Dictionary = {}

## Spawner.
var pack_timer: float = 0.0
var packs_spawned: int = 0
var _pack_acc: Dictionary = {}

## Boss fight in progress (boss_enemy is null otherwise).
var boss_id: String = ""
var boss_enemy: Enemy = null
var boss_outcome: String = ""       ## "defeated" / "retreated" until GameCore consumes it
var boss_last_hp: float = 0.0       ## hp fraction the last boss had when the fight ended (0 = defeated)
var _boss_t: float = 0.0
var _boss_queue: Array = []

## Where kills happen (sim/report: is the fight near the moat?).
var kill_x_sum: float = 0.0
var kill_count: int = 0
var kill_near_moat: int = 0          ## kills within combat.near_moat_x of the moat

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
var _drift: float
var _bob_freq: float
var _dot_interval: float
var _c: Dictionary                  # towers.combat
var _direct: Dictionary = {}        # projectile kinds that count as direct fire (frontal armour)


func _init(game_data: GameData, game_state: GameState, game_mods: Mods, shared_rng: RandomNumberGenerator) -> void:
	data = game_data
	state = game_state
	mods = game_mods
	rng = shared_rng
	moat_x = data.field("moat_x")
	spawn_x = data.field("spawn_x")
	end_x = data.field("end_x")
	y_min = data.field("y_min")
	y_max = data.field("y_max")
	_jitter = data.field("spawn_jitter_x")
	_pack_interval = maxf(0.2, float(data.waves["pack_interval"]))
	_max_enemies = int(data.waves["max_enemies"])
	_drift = float(data.waves["lane_drift"])
	_bob_freq = float(data.waves["bob_freq"])
	_dot_interval = float(data.waves["dot_event_interval"])
	_c = data.combat
	for k: Variant in _c["direct_kinds"]:
		_direct[str(k)] = true
	pack_timer = float(data.waves["first_pack_at"])
	_sync_lenses()
	sync_towers()


func set_mods(m: Mods) -> void:
	mods = m
	_sync_lenses()
	sync_towers()


func _sync_lenses() -> void:
	var want: int = 1 + int(mods.lens["extra"])
	var ap: Dictionary = data.lens["auto_path"]
	while lenses.size() < want:
		var l := Lens.new()
		l.index = lenses.size()
		l.phase = l.index * PI
		l.pos = Vector2(float(ap["cx"]) + cos(l.phase) * float(ap["rx"]), float(ap["cy"]))
		lenses.append(l)
	while lenses.size() > want:
		lenses.pop_back()


# --- wall -------------------------------------------------------------------

## Makes sure every owned tower has a wall slot (state.tower_slots), then
## rebuilds tower instances (keeps cooldowns of existing ones).
func sync_towers() -> void:
	for t: String in data.towers:
		var slots: Array = state.tower_slots.get(t, [])
		while slots.size() < state.tower_count(t):
			slots.append(_free_slot(int(data.towers[t]["row"])))
			state.tower_slots[t] = slots
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
				# stagger without touching the RNG
				tw.cd = fmod(i * data.combat_value("tower_stagger_step"), data.combat_value("tower_stagger_mod"))
			tw.slot = int(state.tower_slots[t][i])
			tw.pos = slot_pos(tw.slot)
			towers.append(tw)


## First free wall slot, preferring `row`; -1 - n when the wall is full (stacked behind).
func _free_slot(row: int) -> int:
	var used: Dictionary = {}
	for t: String in state.tower_slots:
		for s: Variant in state.tower_slots[t]:
			used[int(s)] = true
	for pass_i in 2:
		for i in data.wall_slots.size():
			if not used.has(i) and (pass_i == 1 or data.wall_slot_row[i] == row):
				return i
	return -1 - used.size()


func slot_pos(slot: int) -> Vector2:
	if slot >= 0 and slot < data.wall_slots.size():
		return data.wall_slots[slot]
	var n: int = data.wall_slots.size()
	var base: Vector2 = data.wall_slots[(-slot - 1) % n] if n > 0 else data.fallback_slot()
	return base + Vector2(-10.0, 6.0)


## Position of the i-th tower of a type (after it has a slot).
func tower_pos(t: String, i: int) -> Vector2:
	var slots: Array = state.tower_slots.get(t, [])
	return slot_pos(int(slots[i])) if i < slots.size() else Vector2.ZERO


func tick(dt: float) -> void:
	_producers(dt)
	_spawn(dt)
	_move(dt)
	_dots(dt)
	_abilities(dt)
	_fire_towers(dt)
	_move_projectiles(dt)
	_lenses(dt)
	if _any_dead:
		_cleanup()


# --- spawning --------------------------------------------------------------

func _spawn(dt: float) -> void:
	if boss_enemy != null:
		_boss_t += dt
		while not _boss_queue.is_empty() and float(_boss_queue[0]["at"]) <= _boss_t:
			var q: Dictionary = _boss_queue.pop_front()
			_spawn_group(str(q["type"]), int(q["count"]))
		if bool(data.waves["boss_pauses_packs"]):
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
	var jit: Array = data.waves["speed_jitter"]
	var e := Enemy.new()
	e.uid = _next_uid
	_next_uid += 1
	e.type = t
	e.role = str(es["role"])
	e.max_hp = float(es["hp"])
	e.hp = e.max_hp
	e.speed = float(es["speed"]) * rng.randf_range(float(jit[0]), float(jit[1]))
	e.radius = float(es["radius"])
	e.resist = es["resist"]
	e.loot = es["loot"]
	e.burrow = es["burrow"]
	e.phase = rng.randf() * TAU
	if not e.burrow.is_empty():
		e.burrow_t = float(e.burrow["over"]) * rng.randf_range(0.5, 1.0)
		e.under_speed = float(e.burrow["under_speed"])
	for im: Variant in es["immune"]:
		e.immune[str(im)] = true
	e.front_armor = float(es["front_armor"])
	e.charge = es["charge"]
	if not e.charge.is_empty():
		e.charge_t = float(e.charge["every"])
	e.shield = es["shield"]
	if not e.shield.is_empty():
		e.shield_max = e.max_hp * float(e.shield["frac"])
		e.shield_hp = e.shield_max
	e.split = es["split"]
	e.bait = int(es["bait"])
	if at == Vector2.INF:
		var spread: float = (y_max - y_min) * float(data.waves["pack_y_spread"])
		var y: float = clampf(center_y + rng.randfn(0.0, spread), y_min, y_max)
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
	boss_last_hp = clampf(boss_enemy.hp / boss_enemy.max_hp, 0.0, 1.0)
	if emit:
		events.append({"type": "boss_" + outcome, "boss": boss_id, "pos": boss_enemy.pos, "hp_left": boss_last_hp})
	boss_enemy = null
	_boss_queue = []


# --- movement, moat, damage over time ----------------------------------------

func _move(dt: float) -> void:
	var slow_x: float = moat_x + mods.moat_width
	for e in enemies:
		if not e.alive:
			continue
		e.age += dt
		if e.slow_t > 0.0:
			e.slow_t -= dt
		if e.stun_t > 0.0:
			e.stun_t -= dt
		if not e.charge.is_empty():
			e.charge_t -= dt
			if e.charge_t <= 0.0:
				e.charging = not e.charging
				e.charge_t = float(e.charge["duration" if e.charging else "every"])
				if e.charging and emit:
					events.append({"type": "enemy_charge", "uid": e.uid, "pos": e.pos, "duration": float(e.charge["duration"])})
		var v: float = e.cur_speed()
		if mods.moat_slow > 0.0 and e.pos.x < slow_x:
			v *= 1.0 - mods.moat_slow
		e.pos.x -= v * dt
		if _drift > 0.0:
			e.pos.y = clampf(e.lane_y + sin(e.age * _bob_freq + e.phase) * _drift, y_min, y_max)
		if not e.burrow.is_empty():
			e.burrow_t -= dt
			if e.burrow_t <= 0.0:
				if e.underground:
					_emerge(e, false)
				else:
					e.underground = true
					e.burrow_t = float(e.burrow["under"])
					if emit:
						events.append({"type": "enemy_burrow", "uid": e.uid, "pos": e.pos, "under": true})
		if e.pos.x <= moat_x:
			if e.role == "boss":
				e.alive = false
				_any_dead = true
				_end_boss("retreated")
			else:
				_fall(e)


## A burrowed enemy comes up (end of its tunnel, or `forced` by a dig: lens / shell / jet).
func _emerge(e: Enemy, forced: bool) -> void:
	if not e.underground:
		return
	e.underground = false
	e.burrow_t = float(e.burrow["over"])
	if emit:
		events.append({"type": "enemy_burrow", "uid": e.uid, "pos": e.pos, "under": false})
		events.append({"type": "enemy_emerge", "uid": e.uid, "pos": e.pos, "forced": forced})


func _fall(e: Enemy) -> void:
	e.alive = false
	_any_dead = true
	state.count_event("falls", e.type)
	if emit:
		events.append({"type": "enemy_fell_in_moat", "uid": e.uid, "enemy": e.type, "pos": e.pos})


func _dots(dt: float) -> void:
	var moat_dps: float = mods.moat_dps
	var curtain_x: float = moat_x + mods.moat_width
	for z in zones:
		z.t += dt
	for e in enemies:
		if not e.alive:
			continue
		if e.scald_t > 0.0:
			var d: float = e.scald_dps * minf(dt, e.scald_t)
			e.scald_t -= dt
			var got: float = _dot(e, d, "steam", "scald")
			if got > 0.0:
				state.add_stat_in("dot_by_owner", e.scald_src, got)
		if moat_dps > 0.0 and e.alive and e.pos.x < curtain_x:
			_dot(e, moat_dps * dt, "steam", "moat")
		for z in zones:
			if e.alive and z.t <= z.duration and e.pos.distance_squared_to(z.pos) <= z.radius * z.radius:
				_dot(e, z.dps * dt, z.dmg_type, "zone")
				if e.alive:
					for zs: String in z.statuses:
						_apply_status(e, zs, float(z.statuses[zs]["value"]), float(z.statuses[zs]["duration"]), 0.0)
		if e.alive and emit:
			e.dot_timer += dt
			if e.dot_timer >= _dot_interval:
				_flush_dot(e)
	if not zones.is_empty():
		zones = zones.filter(func(z: Zone) -> bool: return z.t <= z.duration)


func _dot(e: Enemy, amount: float, dmg_type: String, source: String) -> float:
	var dealt: float = damage(e, amount, dmg_type, false, source, true)
	if dealt > 0.0:
		e.dot_total += dealt
		e.dot_acc[source] = float(e.dot_acc.get(source, 0.0)) + dealt
	return dealt


## One aggregated enemy_dot event per source since the last flush.
func _flush_dot(e: Enemy) -> void:
	e.dot_timer = 0.0
	if e.dot_acc.is_empty():
		return
	for src: String in e.dot_acc:
		events.append({"type": "enemy_dot", "uid": e.uid, "pos": e.pos, "source": src,
			"amount": float(e.dot_acc[src]), "total": e.dot_total})
	e.dot_acc.clear()


# --- mechanisms ---------------------------------------------------------------

func _abilities(dt: float) -> void:
	for a: String in mods.abilities:
		var ab: Dictionary = mods.abilities[a]
		var t: float = float(ability_timers.get(a, 0.0)) + dt
		if t < float(ab["interval"]):
			ability_timers[a] = t
			continue
		var reach: float = moat_x + float(ab["reach_x"])
		if str(ab["shape"]) == "line":
			if _line_ability(a, ab, reach):
				ability_timers[a] = 0.0
			else:
				ability_timers[a] = t
			continue
		# targets: the enemies closest to the moat within reach (count = splashes); wait for one
		var r: float = float(ab["radius"])
		var centers: Array[Vector2] = []
		for c in int(ab["count"]):
			var best: Enemy = null
			for e in enemies:
				if not e.alive or e.underground or e.pos.x > reach:
					continue
				var taken: bool = false
				for cpos in centers:
					if e.pos.distance_to(cpos) < r * 2.0:
						taken = true
						break
				if not taken and (best == null or e.pos.x < best.pos.x):
					best = e
			if best == null:
				break
			centers.append(best.pos)
		if centers.is_empty():
			ability_timers[a] = t
			continue
		ability_timers[a] = 0.0
		for center in centers:
			_splash_ability(a, ab, center, r)


func _splash_ability(a: String, ab: Dictionary, center: Vector2, r: float) -> void:
	var hits: int = 0
	var total: float = 0.0
	var hf: float = data.combat_value("splash_hit_factor")
	var boss_k: float = float(ab["boss_pct_mult"])
	for e in enemies:
		if not e.alive or e.underground:
			continue
		var rr: float = r + e.radius * hf
		if e.pos.distance_squared_to(center) > rr * rr:
			continue
		var pct_k: float = boss_k if e.role == "boss" else 1.0
		var d: float = float(ab["dmg"]) + float(ab["dmg_pct_hp"]) * e.max_hp * pct_k
		total += damage(e, d, str(ab["dmg_type"]), false, "ability:" + a)
		hits += 1
		if e.alive:
			var sts: Dictionary = ab["statuses"]
			for sid: String in sts:
				_apply_status(e, sid, float(sts[sid]["value"]), float(sts[sid]["duration"]), d, "ability:" + a)
	var pd: Dictionary = ab["puddle"]
	if not pd.is_empty() and hits > 0:
		# burning coal in the kettle: the splash leaves a boiling puddle (dps = value x mean hit)
		_add_zone(center, float(pd["radius"]), float(pd["value"]) * total / hits, str(pd["dmg_type"]),
			float(pd["duration"]), {}, "ability:" + a)
	if emit:
		# geysers have their own event (the view draws an eruption, not the King's kettle)
		var ev_type: String = str(data.abilities[a].get("event", "ability_fired"))
		events.append({"type": ev_type, "id": a, "pos": center, "radius": r, "hits": hits, "damage": total,
			"shape": "splash"})


## A line mechanism (drill ram): rolls along the busiest lane from the moat to moat + reach_x.
## Returns false when nobody is in reach (waits).
func _line_ability(a: String, ab: Dictionary, reach: float) -> bool:
	var w: float = float(ab["line_width"])
	var cands: Array[Enemy] = []
	for e in enemies:
		if e.alive and not e.underground and e.pos.x <= reach:
			cands.append(e)
	if cands.is_empty():
		return false
	var best_y: float = cands[0].pos.y
	var best_n: int = -1
	for c in cands:
		var n: int = 0
		for o in cands:
			if absf(o.pos.y - c.pos.y) <= w:
				n += 1
		if n > best_n:
			best_n = n
			best_y = c.pos.y
	var hf: float = data.combat_value("splash_hit_factor")
	var boss_k: float = float(ab["boss_pct_mult"])
	var hits: int = 0
	var total: float = 0.0
	for e in cands:
		if not e.alive or absf(e.pos.y - best_y) > w + e.radius * hf:
			continue
		var d: float = float(ab["dmg"]) + float(ab["dmg_pct_hp"]) * e.max_hp * (boss_k if e.role == "boss" else 1.0)
		total += damage(e, d, str(ab["dmg_type"]), false, "ability:" + a)
		hits += 1
		if e.alive:
			var sts: Dictionary = ab["statuses"]
			for sid: String in sts:
				_apply_status(e, sid, float(sts[sid]["value"]), float(sts[sid]["duration"]), d, "ability:" + a)
	if emit:
		events.append({"type": str(data.abilities[a].get("event", "ability_fired")), "id": a,
			"pos": Vector2(moat_x, best_y), "radius": w, "hits": hits, "damage": total, "shape": "line",
			"x_end": reach, "width": w})
	return true


# --- producers (Угольная шахта) -----------------------------------------------

func _producers(dt: float) -> void:
	for pid: String in mods.producers:
		var pr: Dictionary = mods.producers[pid]
		var t: float = float(producer_t.get(pid, 0.0)) + dt
		var interval: float = float(pr["interval"])
		if t >= interval:
			t -= interval
			var out: Dictionary = pr["output"]
			for r: String in out:
				state.add_res(r, float(out[r]))
				state.add_stat_in("produced", r, float(out[r]))
			if emit:
				events.append({"type": "producer_output", "id": pid, "amount": out.duplicate(), "level": int(pr["level"])})
		producer_t[pid] = t


## Cycle progress 0..1 of a producer (0 if not built).
func producer_progress(pid: String) -> float:
	if not mods.producers.has(pid):
		return 0.0
	return clampf(float(producer_t.get(pid, 0.0)) / float(mods.producers[pid]["interval"]), 0.0, 1.0)


# --- towers & projectiles ---------------------------------------------------

func _fire_towers(dt: float) -> void:
	for tw in towers:
		var st: Dictionary = mods.tower_stats[tw.type]
		tw.cd -= dt
		var guard: int = 0
		while tw.cd <= 0.0 and guard < 4:
			guard += 1
			if not _volley(tw, st):
				tw.cd = 0.0
				break
			tw.cd += float(st["reload"])


## One trigger pull: `multishot` projectiles. Returns false if there was no target.
func _volley(tw: Tower, st: Dictionary) -> bool:
	var n: int = int(st["multishot"])
	var kind: String = str(st["projectile"])
	if kind == "rivet":
		var target: Enemy = _pick_target(tw, st)
		if target == null:
			return false
		var spread: float = data.combat_value("multishot_spread")
		for k in n:
			_fire(tw, st, target, (k - (n - 1) * 0.5) * spread)
		return true
	var fired: int = 0
	var chosen: Dictionary = {}
	for k in n:
		# each extra shot prefers a different target; falls back to the same one
		var target: Enemy = _pick_target(tw, st, chosen)
		if target == null:
			target = _pick_target(tw, st)
		if target == null:
			break
		chosen[target.uid] = true
		_fire(tw, st, target, 0.0)
		fired += 1
	return fired > 0


func _targetable(e: Enemy) -> bool:
	return e.alive and not e.underground


func _pick_target(tw: Tower, st: Dictionary, exclude: Dictionary = {}) -> Enemy:
	var rmin: float = float(st["range_min"])
	var rmax: float = float(st["range_max"])
	var best: Enemy = null
	var best_x: float = INF
	if st["projectile"] != "shell":
		# closest to the moat first, but skip enemies this tower cannot finish
		# before they fall in (otherwise a weak defence wastes every shot)
		var dmg: float = maxf(0.001, float(st["dmg"]))
		var reload: float = float(st["reload"])
		var inv_speed: float = 1.0 / maxf(1.0, float(st["proj_speed"]))
		var doomed: Enemy = null
		var doomed_x: float = INF
		for e in enemies:
			if not _targetable(e) or exclude.has(e.uid):
				continue
			var dx: float = e.pos.x - tw.pos.x
			var left: float = e.hp - e.pending
			if dx < rmin or dx > rmax or left <= 0.0 or e.pos.x >= best_x:
				continue
			var eff: float = dmg * (1.0 - float(e.resist.get(st["dmg_type"], 0.0)))
			var shots: float = ceilf(left / maxf(0.001, eff))
			var t_need: float = (shots - 1.0) * reload + dx * inv_speed
			var t_left: float = (e.pos.x - moat_x) / maxf(1.0, e.cur_speed())
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
		if _targetable(e) and e.hp - e.pending > 0.0 and not exclude.has(e.uid):
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


func _fire(tw: Tower, st: Dictionary, target: Enemy, angle_offset: float) -> void:
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
	p.splash = float(st["splash"])
	var lead_t: float = tw.pos.distance_to(target.pos) / maxf(1.0, p.speed)
	var v: float = target.cur_speed()
	match p.kind:
		"rivet":
			p.pierce_left = int(st["pierce"])
			var aim: Vector2 = target.pos + Vector2(-v * lead_t, 0.0)
			p.dir = (aim - tw.pos).normalized().rotated(angle_offset)
			p.dest = tw.pos + p.dir * tw.pos.distance_to(aim)
			p.target = null
		"shell":
			p.flight = clampf(lead_t, data.combat_value("shell_flight_min"), data.combat_value("shell_flight_max"))
			p.dest = target.pos + Vector2(-v * p.flight, 0.0)
			p.expected = p.dmg * (1.0 - float(target.resist.get(p.dmg_type, 0.0)))
			target.pending += p.expected
		"cone":
			p.dir = (target.pos - tw.pos).normalized()
			p.dest = target.pos
			_fire_cone(tw, st, p)
			tw.shots += 1
			tw.aim = p.dest
			return
		"chain":
			p.dest = target.pos
			_fire_chain(tw, st, p, target)
			tw.shots += 1
			tw.aim = p.dest
			return
		"ricochet":
			p.dest = target.pos
			p.bounces_left = int(st["bounces"])
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


## Tesla coil: instant lightning to the target, then jumps to the nearest
## not-yet-hit enemies (chain_range), damage x chain_decay per jump.
func _fire_chain(tw: Tower, st: Dictionary, p: Projectile, target: Enemy) -> void:
	var points: Array = [tw.pos, target.pos]
	var hit: Dictionary = {target.uid: true}
	var cur: Enemy = target
	_tower_hit(cur, p)
	var r2: float = float(st["chain_range"]) * float(st["chain_range"])
	var decay: float = float(st["chain_decay"])
	for j in int(st["chain"]):
		var best: Enemy = null
		var best_d: float = r2
		for e in enemies:
			if not _targetable(e) or hit.has(e.uid):
				continue
			var d2: float = e.pos.distance_squared_to(cur.pos)
			if d2 <= best_d:
				best_d = d2
				best = e
		if best == null:
			break
		hit[best.uid] = true
		p.dmg *= decay
		points.append(best.pos)
		_tower_hit(best, p)
		cur = best
	if emit:
		events.append({"type": "chain_fired", "tower": tw.type, "tower_index": tw.index, "from": tw.pos,
			"points": points, "hits": hit.size(), "crit": p.crit})


## Steam jet: instant cone that hits everyone inside (with "dig": burrowed ones are forced up first).
func _fire_cone(tw: Tower, st: Dictionary, p: Projectile) -> void:
	var length: float = float(st["range_max"])
	var half: float = float(st["cone_angle"])
	var hf: float = data.combat_value("cone_hit_factor")
	var hits: int = 0
	var dig: bool = bool(st["dig"])
	for e in enemies:
		if dig and e.alive and e.underground:
			var vu: Vector2 = e.pos - tw.pos
			if vu.length() <= length and absf(p.dir.angle_to(vu)) <= half:
				_emerge(e, true)
		if not _targetable(e):
			continue
		var v: Vector2 = e.pos - tw.pos
		var dist: float = v.length()
		if dist > length + e.radius * hf or v.x < float(st["range_min"]):
			continue
		if absf(p.dir.angle_to(v)) <= half + atan2(e.radius * hf, maxf(1.0, dist)):
			_tower_hit(e, p)
			hits += 1
	if emit:
		events.append({"type": "cone_fired", "tower": tw.type, "tower_index": tw.index, "from": tw.pos,
			"dir": p.dir, "length": length, "angle": half, "hits": hits, "crit": p.crit})


func _move_projectiles(dt: float) -> void:
	var any_dead: bool = false
	var n: int = projectiles.size()
	for i in n:  # fragments appended during the loop move from the next tick
		var p: Projectile = projectiles[i]
		match p.kind:
			"bullet", "ricochet":
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
			if tgt.underground:
				return  # dove into its burrow: miss
			_tower_hit(tgt, p)
			if p.splash > 0.0:
				_burst(p, tgt)
			if p.kind == "ricochet" and p.bounces_left > 0:
				_ricochet(p, tgt)
	else:
		p.pos = p.pos.move_toward(p.dest, step)


## Ricochet ball: jumps to the nearest enemy not hit yet, +bounce_gain damage per jump.
func _ricochet(p: Projectile, from_e: Enemy) -> void:
	p.hit[from_e.uid] = true
	var st: Dictionary = mods.tower_stats[p.tower]
	var best: Enemy = null
	var best_d: float = float(st["bounce_range"]) * float(st["bounce_range"])
	for e in enemies:
		if not _targetable(e) or p.hit.has(e.uid):
			continue
		var d2: float = e.pos.distance_squared_to(p.pos)
		if d2 <= best_d:
			best_d = d2
			best = e
	if best == null:
		return
	p.alive = true
	p.bounces_left -= 1
	p.bounce += 1
	p.dmg *= 1.0 + float(st["bounce_gain"])
	p.target = best
	p.dest = best.pos
	p.expected = p.dmg * (1.0 - float(best.resist.get(p.dmg_type, 0.0)))
	best.pending += p.expected
	if emit:
		events.append({"type": "ricochet", "uid": p.uid, "tower": p.tower, "from": p.pos, "to": best.pos,
			"bounce": p.bounce})


## Exploding bullets: a small blast around the hit enemy.
func _burst(p: Projectile, center_enemy: Enemy) -> void:
	var k: float = data.combat_value("bullet_splash_dmg")
	var hf: float = data.combat_value("splash_hit_factor")
	for e in enemies:
		if e == center_enemy or not _targetable(e):
			continue
		var rr: float = p.splash + e.radius * hf
		if e.pos.distance_squared_to(p.pos) <= rr * rr:
			damage(e, p.dmg * k, p.dmg_type, false, "tower:" + p.tower)
	if emit:
		events.append({"type": "bullet_burst", "pos": p.pos, "radius": p.splash})


func _move_rivet(p: Projectile, dt: float) -> void:
	var a: Vector2 = p.pos
	var b: Vector2 = a + p.dir * p.speed * dt
	p.pos = b
	var seg: Vector2 = b - a
	var len2: float = maxf(seg.length_squared(), 1e-6)
	var hits: Array = []
	var pad: float = data.combat_value("rivet_hit_pad")
	var minx: float = minf(a.x, b.x) - 30.0
	var maxx: float = maxf(a.x, b.x) + 30.0
	for e in enemies:
		if not _targetable(e) or e.pos.x < minx or e.pos.x > maxx or p.hit.has(e.uid):
			continue
		var tt: float = clampf((e.pos - a).dot(seg) / len2, 0.0, 1.0)
		var closest: Vector2 = a + seg * tt
		var rr: float = e.radius + pad
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
		events.append({"type": "shell_exploded", "uid": p.uid, "tower": p.tower, "pos": p.dest,
			"radius": p.splash, "crit": p.crit, "fragment": p.fragment})
	var hf: float = data.combat_value("splash_hit_factor")
	var st: Dictionary = mods.tower_stats[p.tower]
	var dig: bool = bool(st["dig"]) and not p.fragment
	for e in enemies:
		if dig and e.alive and e.underground and e.pos.distance_squared_to(p.dest) <= p.splash * p.splash:
			_emerge(e, true)  # the blast shakes the tunnel: the mole pops up and takes the hit
		if not _targetable(e):
			continue
		var rr: float = p.splash + e.radius * hf
		if absf(e.pos.x - p.dest.x) <= rr and e.pos.distance_squared_to(p.dest) <= rr * rr:
			_tower_hit(e, p)
	if p.fragment:
		return
	var pd: Dictionary = st["puddle"]
	if not pd.is_empty():
		# the puddle grows with the tower's damage upgrades
		_add_zone(p.dest, float(pd["radius"]), float(pd["dps"]) * float(st["dmg"]) / maxf(0.001, float(data.towers[p.tower]["dmg"])),
			str(pd["dmg_type"]), float(pd["duration"]), st["zone_statuses"], p.tower)
	for k in int(st["cluster"]):
		var f := Projectile.new()
		f.uid = _next_uid
		_next_uid += 1
		f.kind = "shell"
		f.fragment = true
		f.tower = p.tower
		f.start = p.dest
		f.pos = p.dest
		var ang: float = rng.randf() * TAU
		f.dest = p.dest + Vector2(cos(ang), sin(ang)) * p.splash * data.combat_value("cluster_spread") * sqrt(rng.randf())
		f.flight = data.combat_value("cluster_flight")
		f.dmg = p.dmg * data.combat_value("cluster_dmg")
		f.dmg_type = p.dmg_type
		f.splash = p.splash * data.combat_value("cluster_radius")
		projectiles.append(f)


## Boiling / burning ground. owner: tower type or "ability:<id>".
func _add_zone(pos: Vector2, radius: float, dps: float, dmg_type: String, duration: float, sts: Dictionary,
		owner: String) -> void:
	var z := Zone.new()
	z.uid = _next_uid
	_next_uid += 1
	z.pos = pos
	z.radius = radius
	z.dps = dps
	z.dmg_type = dmg_type
	z.duration = duration
	z.statuses = sts
	z.tower = owner
	zones.append(z)
	if emit:
		events.append({"type": "zone_created", "uid": z.uid, "pos": z.pos, "radius": z.radius,
			"duration": z.duration, "dmg_type": z.dmg_type, "tower": owner, "statuses": sts.keys()})


func _tower_hit(e: Enemy, p: Projectile) -> void:
	var st: Dictionary = mods.tower_stats[p.tower]
	var direct: bool = _direct.has(p.kind) and not p.fragment
	var dealt: float = damage(e, p.dmg, p.dmg_type, p.crit, "tower:" + p.tower, false, direct, float(st["armor_pierce"]))
	if p.crit and int(st["crit_chain"]) > 0:
		_crit_chain(e, p, int(st["crit_chain"]))
	if not e.alive:
		return
	var sts: Dictionary = st["statuses"]
	for s: String in sts:
		_apply_status(e, s, float(sts[s]["value"]), float(sts[s]["duration"]), dealt, "tower:" + p.tower)
	var kb: float = float(st["knockback"])
	if kb > 0.0 and not p.fragment and not e.immune.has("knockback"):
		if e.role == "boss":
			kb *= data.combat_value("knockback_boss")
		e.pos.x = minf(e.pos.x + kb, spawn_x + _jitter)


## Statuses: scald = value * hit damage dealt as steam over duration; slow = speed -value;
## stun = stands still for duration (bosses: duration * combat.stun_boss). Immunities: Enemy.immune.
## owner: who applied it ("tower:<t>", "lens", "ability:<id>") — for damage statistics.
func _apply_status(e: Enemy, s: String, value: float, duration: float, dealt: float, owner: String = "") -> void:
	var fresh: bool = false
	if e.immune.has(s):
		return
	match s:
		"stun":
			if e.role == "boss":
				duration *= data.combat_value("stun_boss")
			if duration <= 0.0:
				return
			fresh = e.stun_t <= 0.0
			e.stun_t = maxf(e.stun_t, duration)
		"scald":
			var dps: float = dealt * value / maxf(0.1, duration)
			fresh = e.scald_t <= 0.0
			if fresh or dps > e.scald_dps:
				e.scald_dps = dps
				e.scald_src = owner
			e.scald_t = duration
		"slow":
			fresh = e.slow_t <= 0.0
			e.slow_f = maxf(value, e.slow_f if not fresh else 0.0)
			e.slow_t = duration
	if fresh and emit:
		events.append({"type": "enemy_status", "uid": e.uid, "status": s, "pos": e.pos, "duration": duration})


## Critical hits jump as a spark to the nearest other enemies.
func _crit_chain(from_e: Enemy, p: Projectile, jumps: int) -> void:
	var cur: Enemy = from_e
	var hit: Dictionary = {from_e.uid: true}
	var rng_r: float = data.combat_value("crit_chain_range")
	for j in jumps:
		var best: Enemy = null
		var best_d: float = rng_r * rng_r
		for e in enemies:
			if not _targetable(e) or hit.has(e.uid):
				continue
			var d2: float = e.pos.distance_squared_to(cur.pos)
			if d2 <= best_d:
				best_d = d2
				best = e
		if best == null:
			return
		hit[best.uid] = true
		if emit:
			events.append({"type": "crit_chain", "from": cur.pos, "to": best.pos})
		damage(best, p.dmg * data.combat_value("crit_chain_dmg"), "spark", false, "tower:" + p.tower)
		cur = best


## Deals damage after resistances. Returns the damage actually applied (no overkill).
## quiet = no enemy_hit event (damage over time ticks; see enemy_dot instead).
## direct = direct fire (bullet / rivet / cone / ricochet / chain): frontal armour blocks
## Enemy.front_armor of it, reduced by the tower's armor_pierce (and halved on scalded
## enemies with "Паровая ржавчина"). Shield: only its breaker types wear it down; other
## damage is cut by shield.block while it holds.
func damage(e: Enemy, amount: float, dmg_type: String, crit: bool, source: String, quiet: bool = false,
		direct: bool = false, armor_pierce: float = 0.0) -> float:
	if not e.alive or e.underground or amount <= 0.0:
		return 0.0
	var resist: float = float(e.resist.get(dmg_type, 0.0))
	var shred: bool = mods.scald_shred and e.scald_t > 0.0
	if shred and dmg_type == "impact":
		resist = minf(resist, 0.0)
	var eff: float = amount * (1.0 - resist)
	if dmg_type == "spark" and mods.wet_metal and e.scald_t > 0.0:
		eff *= data.combat_value("wet_metal_mult")
	var armored: bool = false
	if direct and e.front_armor > 0.0:
		var block: float = e.front_armor * (1.0 - armor_pierce) * (0.5 if shred else 1.0)
		eff *= 1.0 - block
		armored = block > 0.0
	var shielded: bool = false
	if e.shield_hp > 0.0:
		if (e.shield["breakers"] as Array).has(dmg_type):
			var absorbed: float = minf(eff, e.shield_hp)
			e.shield_hp -= absorbed
			eff -= absorbed
			_count_damage(source, absorbed)
			if e.shield_hp <= 0.0:
				e.shield_hp = 0.0
				if emit:
					events.append({"type": "enemy_shield_broken", "uid": e.uid, "pos": e.pos})
		else:
			eff *= 1.0 - float(e.shield["block"])
			shielded = true
	if eff <= 0.0:
		return 0.0
	var dealt: float = minf(eff, e.hp)
	e.hp -= eff
	_count_damage(source, dealt)
	if emit and not quiet:
		events.append({"type": "enemy_hit", "uid": e.uid, "amount": eff, "dmg_type": dmg_type,
			"crit": crit, "pos": e.pos, "source": source, "armored": armored, "shielded": shielded})
	if e.hp <= 0.0:
		_kill(e, source)
	return dealt


func _count_damage(source: String, amount: float) -> void:
	var bysrc: Dictionary = state.stats["dmg_by_source"]
	bysrc[source] = float(bysrc.get(source, 0.0)) + amount


func _kill(e: Enemy, source: String = "") -> void:
	e.alive = false
	e.hp = 0.0
	_any_dead = true
	var loot: Dictionary = e.loot
	if source.begins_with("ability:"):
		# moat mechanisms (geysers) return only part of the loot (the rest sinks with the body)
		var k: float = float(mods.abilities.get(source.substr(8), {}).get("kill_loot_mult", 1.0))
		if k < 1.0:
			loot = {}
			for r: String in e.loot:
				loot[r] = float(e.loot[r]) * k
	for r: String in loot:
		state.add_res(r, float(loot[r]))
	state.count_event("kills", e.type)
	kill_x_sum += e.pos.x
	kill_count += 1
	if e.pos.x < moat_x + data.combat_value("near_moat_x"):
		kill_near_moat += 1
	if emit:
		_flush_dot(e)
		events.append({"type": "enemy_killed", "uid": e.uid, "enemy": e.type, "pos": e.pos, "loot": loot,
			"source": source})
	if not e.split.is_empty():
		_split(e)
	if e.role == "boss" and e == boss_enemy:
		_end_boss("defeated")


## Coal golem: breaks into `split.count` embers around the body.
func _split(e: Enemy) -> void:
	var kids: Array = []
	var spread: float = data.combat_value("split_spread")
	var n: int = int(e.split["count"])
	for i in n:
		var off: Vector2 = Vector2(rng.randf_range(-0.3, 0.6), (i - (n - 1) * 0.5)) * spread
		var at: Vector2 = Vector2(e.pos.x + off.x, clampf(e.pos.y + off.y, y_min, y_max))
		var c: Enemy = _spawn_enemy(str(e.split["type"]), at.y, at)
		if c != null:
			c.parent_uid = e.uid
			kids.append(c.uid)
	if emit:
		events.append({"type": "enemy_split", "uid": e.uid, "enemy": e.type, "pos": e.pos,
			"child_type": str(e.split["type"]), "children": kids})


func _cleanup() -> void:
	_any_dead = false
	var keep: Array[Enemy] = []
	for e in enemies:
		if e.alive:
			keep.append(e)
	enemies = keep


# --- steam lenses -------------------------------------------------------------

func in_field(p: Vector2) -> bool:
	return p.x >= moat_x - 40.0 and p.x <= spawn_x + 40.0 and p.y >= y_min - 60.0 and p.y <= y_max + 60.0


func _lenses(dt: float) -> void:
	var idle_to_auto: float = data.lens_value("idle_to_auto")
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
	for l in lenses:
		var is_manual: bool = manual and l.index == 0
		if is_manual:
			l.pos = state.cursor_pos
			l.mode = "manual"
		else:
			_auto_move(l, dt)
		_lens_damage(l, dt, is_manual)


func _auto_move(l: Lens, dt: float) -> void:
	var seek: bool = bool(mods.lens["seek"])
	l.timer -= dt
	if l.timer <= 0.0:
		l.timer = data.lens_value("seek_retarget" if seek else "auto_retarget")
		if seek:
			l.has_target = alive_count() > 0
			if l.has_target:
				l.target = densest_point(float(mods.lens["radius"]), l.index)
		else:
			_auto_band(l)
	if l.has_target and seek:
		l.mode = "seek"
		l.pos = l.pos.move_toward(l.target, data.lens_value("seek_speed") * dt)
		return
	l.mode = "auto"
	var goal: Vector2
	if l.has_target:
		# sweep up and down over the busiest stretch of the road
		l.sweep += dt
		var amp: float = data.lens_value("auto_sweep_amp")
		var y: float = l.target.y + sin(l.sweep * TAU / data.lens_value("auto_sweep_period") + l.index * PI) * amp
		goal = Vector2(l.target.x, clampf(y, y_min, y_max))
	else:
		var ap: Dictionary = data.lens["auto_path"]
		l.phase = fmod(l.phase + dt * TAU / maxf(1.0, float(ap["period"])), TAU)
		goal = Vector2(float(ap["cx"]) + cos(l.phase) * float(ap["rx"]), float(ap["cy"]) + sin(l.phase) * float(ap["ry"]))
	l.pos = l.pos.move_toward(goal, data.lens_value("auto_speed") * dt)


## Basic auto mode: the x-band (auto_band px) with most enemies; target = their mean position.
func _auto_band(l: Lens) -> void:
	var band: float = maxf(10.0, data.lens_value("auto_band"))
	var counts: Dictionary = {}
	for e in enemies:
		if _targetable(e):
			var b: int = int(floor((e.pos.x - moat_x) / band))
			counts[b] = int(counts.get(b, 0)) + 1
	l.has_target = not counts.is_empty()
	if not l.has_target:
		return
	var keys: Array = counts.keys()
	keys.sort()
	var pick: int = int(keys[0])
	var rank: int = l.index  # extra lenses take the 2nd, 3rd... busiest band
	var ordered: Array = keys.duplicate()
	ordered.sort_custom(func(a: int, b: int) -> bool:
		return int(counts[a]) > int(counts[b]) or (int(counts[a]) == int(counts[b]) and a < b))
	pick = int(ordered[mini(rank, ordered.size() - 1)])
	var sx: float = 0.0
	var sy: float = 0.0
	var n: int = 0
	for e in enemies:
		if _targetable(e) and int(floor((e.pos.x - moat_x) / band)) == pick:
			sx += e.pos.x
			sy += e.pos.y
			n += 1
	l.target = Vector2(sx / n, sy / n)


func _lens_damage(l: Lens, dt: float, manual: bool) -> void:
	var L: Dictionary = mods.lens
	l.acc += dt
	var interval: float = float(L["interval"])
	var n: int = 0
	while l.acc >= interval and n < 100:
		l.acc -= interval
		n += 1
	if n == 0:
		return
	var k: float = n * (1.0 if manual else float(L["auto_mult"]))
	var dmg: float = float(L["dmg"]) * k
	var pct: float = float(L["dmg_pct_hp"]) * k
	var boss_k: float = data.lens_value("boss_pct_mult")
	var radius: float = float(L["radius"])
	var hf: float = data.lens_value("hit_radius_factor")
	var sts: Dictionary = L["statuses"]
	var total: float = 0.0
	var hits: int = 0
	if bool(L["dig"]):
		for e in enemies:
			if e.alive and e.underground and e.pos.distance_squared_to(l.pos) <= radius * radius:
				_emerge(e, true)
	for e in enemies:
		if not _targetable(e) or absf(e.pos.x - l.pos.x) > radius + e.radius:
			continue
		var rr: float = radius + e.radius * hf
		if e.pos.distance_squared_to(l.pos) <= rr * rr:
			var d: float = dmg + pct * e.max_hp * (boss_k if e.role == "boss" else 1.0)
			var dealt: float = damage(e, d, str(L["dmg_type"]), false, "lens")
			total += dealt
			hits += 1
			if e.alive:
				for s: String in sts:
					_apply_status(e, s, float(sts[s]["value"]), float(sts[s]["duration"]), dealt, "lens")
	if emit:
		events.append({"type": "lens_tick", "index": l.index, "pos": l.pos, "radius": radius, "mode": l.mode,
			"damage": total, "hits": hits})


## Position of the enemy with the most neighbours within `radius` (ties -> closest
## to the moat). `skip` > 0 picks a group at least 2·radius away from the best one
## (for extra lenses). Sorted sweep, so roughly O(n·k) instead of O(n²).
func densest_point(radius: float, skip: int = 0) -> Vector2:
	var alive: Array[Enemy] = []
	for e in enemies:
		if _targetable(e):
			alive.append(e)
	if alive.is_empty():
		return lens_pos
	alive.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.pos.x < b.pos.x)
	var r2: float = radius * radius
	var count: int = alive.size()
	var scores: Array[int] = []
	scores.resize(count)
	var lo: int = 0
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
		scores[i] = n
	var best: int = 0
	for i in count:
		if scores[i] > scores[best]:
			best = i
	if skip > 0:
		var second: int = -1
		for i in count:
			if alive[i].pos.distance_squared_to(alive[best].pos) > 4.0 * r2 and (second < 0 or scores[i] > scores[second]):
				second = i
		if second >= 0:
			best = second
	return alive[best].pos


## Count of alive enemies (view/sim helper).
func alive_count() -> int:
	var n: int = 0
	for e in enemies:
		if e.alive:
			n += 1
	return n
