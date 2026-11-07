class_name FxLayer
extends Node2D
## Everything transient above the units, drawn in one canvas item (_draw) in
## art pixels so hundreds of effects batch into a few draw calls: projectiles
## (read from battle.projectiles every frame, starting at the tower's visual
## muzzle), one-shot sprite animations (explosions, sparks, splashes, falls,
## scrap), pixel particles, steam cones, spark chains, the kettle's water arc,
## the steam lens reticle, enemy HP bars (only when damaged) and "new!" marks.

class Anim:
	var frames: Array = []
	var fps: float = 10.0
	var anchor: Vector2 = Vector2.ZERO
	var pos: Vector2 = Vector2.ZERO
	var t: float = 0.0
	var flip: bool = false
	var mod: Color = Color.WHITE
	var vel: Vector2 = Vector2.ZERO


class Particle:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var t: float = 0.0
	var life: float = 0.5
	var color: Color = Color.WHITE
	var size: float = 1.0
	var grav: float = 0.0
	var ground: float = -1.0       ## y where it lands and stops (-1 = never)
	var fade: bool = true


class Line:
	var a: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO
	var t: float = 0.0
	var life: float = 0.15
	var kind: String = "chain"     ## chain / cone / ring / bubble
	var color: Color = Color.WHITE
	var r: float = 0.0
	var dir: Vector2 = Vector2.RIGHT
	var angle: float = 0.0


class Arc:
	var a: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO
	var t: float = 0.0
	var dur: float = 0.3
	var h: float = 20.0

const MAX_ANIMS: int = 180
const MAX_PARTICLES: int = 450

var kit: ViewKit
var draw_ms: float = 0.0          ## last _draw cost (perf readout)
var bv: BattleView
var core: GameCore
var anims: Array[Anim] = []
var particles: Array[Particle] = []
var lines: Array[Line] = []
var arcs: Array[Arc] = []
var _info: Dictionary = {}
var _head: Dictionary = {}      ## enemy type -> sprite height above feet (art px)
var _time: float = 0.0
var _c: Dictionary = {}


func setup(view_kit: ViewKit, battle_view: BattleView) -> void:
	kit = view_kit
	bv = battle_view
	core = kit.core
	for n: String in ["soot_0", "soot_1", "soot_2", "iron_1", "iron_2", "iron_3", "brass_1", "brass_2", "brass_3",
			"copper_1", "copper_2", "copper_3", "steam_1", "steam_2", "steam_3", "teal_1", "teal_2", "ember_1",
			"ember_2", "verdigris_1", "verdigris_2", "parchment_2", "dust_0", "dust_2"]:
		_c[n] = kit.col(n)


func _sprite(sprite_name: String) -> Dictionary:
	if not _info.has(sprite_name):
		var i: Dictionary = SpriteLib.info(sprite_name)
		var frames: Array = []
		for k in range(int(i.get("frames", 1))):
			frames.append(SpriteLib.texture(sprite_name, k))
		_info[sprite_name] = {"frames": frames, "fps": float(i.get("fps", 10.0)), "anchor": SpriteLib.anchor(sprite_name)}
	return _info[sprite_name]


# --- spawning --------------------------------------------------------------------

func anim(sprite_name: String, pos: Vector2, flip: bool = false, mod: Color = Color.WHITE, vel: Vector2 = Vector2.ZERO) -> void:
	if anims.size() >= MAX_ANIMS:
		return
	var s: Dictionary = _sprite(sprite_name)
	var a := Anim.new()
	a.frames = s["frames"]
	a.fps = maxf(1.0, float(s["fps"]))
	a.anchor = s["anchor"]
	a.pos = pos.round()
	a.flip = flip
	a.mod = mod
	a.vel = vel
	anims.append(a)


func particle(pos: Vector2, vel: Vector2, color: Color, life: float, size: float = 1.0, grav: float = 0.0, ground: float = -1.0) -> void:
	if particles.size() >= MAX_PARTICLES:
		return
	var p := Particle.new()
	p.pos = pos
	p.vel = vel
	p.color = color
	p.life = life
	p.size = size
	p.grav = grav
	p.ground = ground
	particles.append(p)


func burst(pos: Vector2, colors: Array, n: int, speed: float, life: float, grav: float = 0.0, size: float = 1.0, up_bias: float = 0.0) -> void:
	for i in n:
		var ang: float = randf() * TAU
		var v := Vector2(cos(ang), sin(ang)) * speed * randf_range(0.4, 1.0) + Vector2(0, -up_bias)
		particle(pos, v, kit.col(str(colors[i % colors.size()])), life * randf_range(0.7, 1.2), size, grav,
			pos.y + randf_range(1.0, 4.0) if grav > 0.0 else -1.0)


func hit_sparks(pos: Vector2, dmg_type: String, crit: bool) -> void:
	var n: int = 5 if crit else 2
	match dmg_type:
		"steam":
			burst(pos, ["steam_3", "steam_2"], n, 14.0, 0.35, 0.0, 1.0, 8.0)
		"spark":
			burst(pos, ["brass_3", "teal_2", "steam_3"], n + 2, 40.0, 0.22)
		"blast":
			burst(pos, ["ember_2", "brass_3"], n, 30.0, 0.3, 60.0)
		_:
			burst(pos, ["brass_3", "parchment_2"], n, 34.0, 0.18, 40.0)
	if crit:
		anim("hit_spark", pos)


func explosion(pos: Vector2, radius_art: float, crit: bool, fragment: bool) -> void:
	if fragment:
		anim("hit_spark", pos)
		burst(pos, ["ember_2", "brass_3", "soot_2"], 4, 22.0, 0.3, 50.0)
		return
	anim("explosion", pos + Vector2(0, 4))
	burst(pos, ["ember_2", "brass_3", "ember_1", "soot_2"], 10 if crit else 7, radius_art * 2.2, 0.45, 70.0, 1.0, 10.0)
	bv.decals.scorch(pos, radius_art)


func muzzle_smoke(pos: Vector2) -> void:
	particle(pos + Vector2(1, 0), Vector2(randf_range(8.0, 14.0), randf_range(-6.0, -2.0)), _c["steam_2"], 0.3, 2.0)
	particle(pos, Vector2(randf_range(2.0, 6.0), -8.0), _c["steam_1"], 0.4, 1.0)
	particle(pos + Vector2(2, 0), Vector2(30, 0), _c["brass_3"], 0.05, 1.0)


func steam_burst(pos: Vector2, n: int) -> void:
	for i in n:
		anim("steam_puff", pos + Vector2(randf_range(-9.0, 9.0), randf_range(-4.0, 3.0)), randf() < 0.5)
	burst(pos, ["steam_3", "steam_2"], n * 2, 24.0, 0.5, 0.0, 1.0, 10.0)


func curtain_puff(pos: Vector2) -> void:
	particle(pos, Vector2(randf_range(-2.0, 4.0), randf_range(-16.0, -9.0)), _c["steam_3"], randf_range(0.5, 0.9), 2.0)
	particle(pos + Vector2(2, 1), Vector2(randf_range(0.0, 3.0), randf_range(-12.0, -7.0)), _c["steam_2"], randf_range(0.6, 1.0), 1.0)


func tier_ring(center: Vector2) -> void:
	var l := Line.new()
	l.kind = "ring"
	l.a = center
	l.r = kit.f("tier_ring.radius", 18.0)
	l.life = kit.f("tier_ring.time", 0.6)
	l.color = _c["brass_3"]
	lines.append(l)
	for i in 14:
		var ang: float = TAU * i / 14.0
		particle(center + Vector2(cos(ang), sin(ang)) * 4.0, Vector2(cos(ang), sin(ang)) * 34.0,
			_c["brass_3"] if i % 2 == 0 else _c["parchment_2"], 0.45, 1.0)


func sparkle(center: Vector2, n: int = 6) -> void:
	burst(center, ["brass_3", "parchment_2", "brass_2"], n, 22.0, 0.4, 0.0, 1.0, 14.0)


func kill(pos: Vector2, enemy_type: String, big: bool) -> void:
	anim("scrap_burst", pos + Vector2(0, -2))
	var cols: Array = kit.enemy_sprites(enemy_type).get("pieces", ["iron_2", "copper_2", "brass_2", "soot_2", "copper_3"])
	burst(pos + Vector2(0, -5), cols, 14 if big else 7, 42.0 if big else 30.0, 0.7, 120.0, 1.0, 26.0)


func fall(pos: Vector2, enemy_type: String) -> void:
	var sp: Dictionary = kit.enemy_sprites(enemy_type)
	var x: float = bv.bank_x() - 9.0
	var p := Vector2(x, pos.y)
	anim(str(sp.get("fall", "scavenger_fall")), p)
	anim("splash", p + Vector2(0, 1))
	anim("steam_puff", p + Vector2(-3, -10))
	var ring := Line.new()
	ring.kind = "bubble"
	ring.a = p + Vector2(0, 1)
	ring.r = 3.0
	ring.life = kit.f("moat.bubble_ring_time", 0.6)
	ring.color = _c["steam_3"]
	lines.append(ring)
	burst(p + Vector2(0, -2), ["steam_3", "teal_2", "steam_2"], 6, 26.0, 0.45, 80.0, 1.0, 20.0)


func cone(from_screen: Vector2, dir: Vector2, length: float, angle: float) -> void:
	var l := Line.new()
	l.kind = "cone"
	l.a = bv.muzzle_for_start(from_screen)
	l.dir = dir
	l.r = length / kit.art_scale
	l.angle = angle
	l.life = 0.22
	lines.append(l)
	for i in 5:
		var d: Vector2 = dir.rotated(randf_range(-angle, angle))
		var dist: float = randf_range(0.25, 0.95) * l.r
		particle(l.a + d * dist * 0.3, d * dist * 2.2, _c["steam_3"] if i % 2 == 0 else _c["steam_2"], 0.4, 2.0)


func chain(a_screen: Vector2, b_screen: Vector2) -> void:
	var l := Line.new()
	l.kind = "chain"
	l.a = kit.to_art(a_screen) + Vector2(0, -5)
	l.b = kit.to_art(b_screen) + Vector2(0, -5)
	l.life = 0.16
	lines.append(l)


func kettle_arc(from_art: Vector2, to_screen: Vector2) -> void:
	var a := Arc.new()
	a.a = from_art
	a.b = kit.to_art(to_screen)
	a.dur = 0.32
	a.h = 26.0
	arcs.append(a)


# --- update & draw ------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var i: int = anims.size() - 1
	while i >= 0:
		var a: Anim = anims[i]
		a.t += delta
		a.pos += a.vel * delta
		if int(a.t * a.fps) >= a.frames.size():
			anims[i] = anims[anims.size() - 1]
			anims.pop_back()
		i -= 1
	i = particles.size() - 1
	while i >= 0:
		var p: Particle = particles[i]
		p.t += delta
		if p.t >= p.life:
			particles[i] = particles[particles.size() - 1]
			particles.pop_back()
		else:
			p.vel.y += p.grav * delta
			p.pos += p.vel * delta
			if p.ground >= 0.0 and p.pos.y > p.ground and p.vel.y > 0.0:
				p.pos.y = p.ground
				p.vel = Vector2(p.vel.x * 0.4, -p.vel.y * 0.25)
				if absf(p.vel.y) < 6.0:
					p.vel = Vector2.ZERO
					p.grav = 0.0
		i -= 1
	i = lines.size() - 1
	while i >= 0:
		var l: Line = lines[i]
		l.t += delta
		if l.t >= l.life:
			lines[i] = lines[lines.size() - 1]
			lines.pop_back()
		i -= 1
	i = arcs.size() - 1
	while i >= 0:
		var arc: Arc = arcs[i]
		arc.t += delta
		if arc.t >= arc.dur:
			anim("splash", arc.b + Vector2(0, 2))
			anim("steam_puff", arc.b + Vector2(3, -4))
			burst(arc.b, ["steam_3", "teal_2"], 8, 30.0, 0.4, 70.0, 1.0, 16.0)
			arcs[i] = arcs[arcs.size() - 1]
			arcs.pop_back()
		i -= 1


func _draw() -> void:
	var _pt0: int = Time.get_ticks_usec()
	_draw_body()
	draw_ms = (Time.get_ticks_usec() - _pt0) / 1000.0


func _draw_body() -> void:
	_draw_projectiles()
	for l: Line in lines:
		_draw_line_fx(l)
	for arc: Arc in arcs:
		var k: float = arc.t / arc.dur
		for j in 4:
			var kk: float = clampf(k - j * 0.06, 0.0, 1.0)
			var p: Vector2 = arc.a.lerp(arc.b, kk) + Vector2(0, -sin(PI * kk) * arc.h)
			draw_rect(Rect2(p.round(), Vector2(2, 2) if j == 0 else Vector2(1, 1)), _c["steam_3"] if j == 0 else _c["teal_2"])
	for a: Anim in anims:
		var fi: int = mini(int(a.t * a.fps), a.frames.size() - 1)
		var tex: Texture2D = a.frames[fi]
		if a.flip:
			draw_set_transform(a.pos.round(), 0.0, Vector2(-1, 1))
			draw_texture(tex, -a.anchor, a.mod)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_texture(tex, (a.pos - a.anchor).round(), a.mod)
	for p: Particle in particles:
		var col: Color = p.color
		if p.fade:
			col.a *= clampf(2.0 * (1.0 - p.t / p.life), 0.0, 1.0)
		draw_rect(Rect2(p.pos.round(), Vector2(p.size, p.size)), col)
	_draw_enemy_marks()
	_draw_lenses()


func _draw_projectiles() -> void:
	var tex_b: Texture2D = SpriteLib.texture("bullet")
	var tex_r: Texture2D = SpriteLib.texture("rivet")
	var anc_b: Vector2 = SpriteLib.anchor("bullet")
	var anc_r: Vector2 = SpriteLib.anchor("rivet")
	var anc_s: Vector2 = SpriteLib.anchor("shell")
	var shadow: Texture2D = SpriteLib.texture("shadow_s")
	var anc_sh: Vector2 = SpriteLib.anchor("shadow_s")
	var arc_k: float = kit.f("shell_arc.k", 0.22)
	var arc_max: float = kit.f("shell_arc.max", 46.0)
	var arc_frag: float = kit.f("shell_arc.fragment", 10.0)
	for p: Battle.Projectile in core.battle.projectiles:
		var ap: Vector2 = kit.to_art(p.pos)
		var start: Vector2 = kit.to_art(p.start)
		match p.kind:
			"shell":
				var k: float = clampf(p.t / maxf(0.01, p.flight), 0.0, 1.0)
				var m: Vector2 = start if p.fragment else bv.muzzle_for_start(p.start)
				var ground: Vector2 = ap + (m - start) * (1.0 - k)
				var dist: float = kit.to_art(p.dest).distance_to(start)
				var h: float = arc_frag if p.fragment else minf(arc_max, dist * arc_k)
				var pos: Vector2 = ground + Vector2(0, -sin(PI * k) * h)
				if not p.fragment:
					draw_texture(shadow, (ground - anc_sh).round(), Color(1, 1, 1, 0.5))
				var fr: int = int(_time * 10.0 + p.uid) % 2
				draw_texture(SpriteLib.texture("shell", fr), (pos - anc_s).round())
			"rivet":
				var m2: Vector2 = bv.muzzle_for_start(p.start)
				var d0: float = maxf(1.0, kit.to_art(p.dest).distance_to(start))
				var k2: float = clampf(ap.distance_to(start) / d0, 0.0, 1.0)
				var pos2: Vector2 = (ap + (m2 - start) * (1.0 - k2)).round()
				draw_set_transform(pos2, p.dir.angle())
				draw_texture(tex_r, -anc_r)
				draw_set_transform(Vector2.ZERO)
			_:
				var m3: Vector2 = bv.muzzle_for_start(p.start)
				var dst: Vector2 = kit.to_art(p.dest)
				var d1: float = maxf(1.0, dst.distance_to(start))
				var k3: float = clampf(ap.distance_to(start) / d1, 0.0, 1.0)
				var pos3: Vector2 = (ap + (m3 - start) * (1.0 - k3)).round()
				var ang: float = (dst - pos3).angle() if dst.distance_squared_to(pos3) > 1.0 else 0.0
				draw_set_transform(pos3, snappedf(ang, PI / 8.0))
				draw_texture(tex_b, -anc_b, _c["ember_2"] if p.crit else Color.WHITE)
				draw_set_transform(Vector2.ZERO)


func _draw_line_fx(l: Line) -> void:
	var k: float = l.t / l.life
	match l.kind:
		"chain":
			var pts := PackedVector2Array()
			var n: int = 6
			for j in n + 1:
				var p: Vector2 = l.a.lerp(l.b, float(j) / n)
				if j > 0 and j < n:
					p += Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
				pts.append(p.round())
			draw_polyline(pts, _c["brass_3"] if k < 0.5 else _c["teal_2"], 1.0)
		"cone":
			var a: float = 0.35 * (1.0 - k)
			var tip: Vector2 = l.a
			var p1: Vector2 = tip + l.dir.rotated(-l.angle) * l.r
			var p2: Vector2 = tip + l.dir.rotated(l.angle) * l.r
			draw_colored_polygon(PackedVector2Array([tip, p1, p2]), Color(_c["steam_2"], a))
			draw_colored_polygon(PackedVector2Array([tip, tip.lerp(p1, 0.6), tip.lerp(p2, 0.6)]), Color(_c["steam_3"], a))
		"ring":
			var r: float = 4.0 + l.r * k
			var col: Color = l.color
			col.a = 1.0 - k
			draw_arc(l.a, r, 0.0, TAU, 24, col, 1.0)
			draw_arc(l.a, r * 0.6, 0.0, TAU, 16, Color(_c["parchment_2"], col.a * 0.6), 1.0)
		"bubble":
			var rr: float = l.r + 9.0 * k
			var col2: Color = l.color
			col2.a = 0.9 * (1.0 - k)
			_ellipse(l.a, rr, rr * 0.45, col2)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for j in 17:
		var ang: float = TAU * j / 16.0
		pts.append((c + Vector2(cos(ang) * rx, sin(ang) * ry)).round())
	draw_polyline(pts, col, 1.0)


func _head_of(enemy_type: String) -> float:
	if not _head.has(enemy_type):
		var walk: String = str(kit.enemy_sprites(enemy_type).get("walk", "scavenger_walk"))
		_head[enemy_type] = SpriteLib.anchor(walk).y
	return float(_head[enemy_type])


func _draw_enemy_marks() -> void:
	var boss_uid: int = core.battle.boss_enemy.uid if core.battle.boss_enemy != null else -1
	var bg: Color = _c["soot_0"]
	var fill: Color = _c["verdigris_2"]
	var low: Color = _c["ember_2"]
	for e: Battle.Enemy in core.battle.enemies:
		if not e.alive or e.underground:
			continue
		var ev: BattleView.EnemyView = bv.enemy_view(e.uid)
		if ev == null:
			continue
		var head: float = _head_of(e.type)
		var top: Vector2 = ev.art_pos + Vector2(0, -head - 3)
		if e.uid != boss_uid and e.hp < e.max_hp:
			var w: float = clampf(roundf(e.radius), 8.0, 18.0)
			var x0: float = roundf(top.x - w * 0.5)
			draw_rect(Rect2(x0 - 1, top.y - 1, w + 2, 3), bg)
			var frac: float = clampf(e.hp / e.max_hp, 0.0, 1.0)
			draw_rect(Rect2(x0, top.y, maxf(1.0, roundf(w * frac)), 1), fill if frac > 0.35 else low)
		if e.scald_t > 0.0 and randf() < 0.12:
			particle(ev.art_pos + Vector2(randf_range(-4.0, 4.0), -head * randf_range(0.3, 0.9)),
				Vector2(randf_range(-2.0, 2.0), -12.0), _c["steam_3"], 0.45, 1.0)
		if ev.new_t > 0.0:
			var bob: float = roundf(sin(_time * 6.0))
			draw_string(kit.FONT_NUMBER, Vector2(roundf(top.x - 30), roundf(top.y - 3 + bob)), tr("UI_NEW"),
				HORIZONTAL_ALIGNMENT_CENTER, 60, 12, _c["brass_3"])


func _draw_lenses() -> void:
	var radius: float = float(core.mods.lens["radius"]) / kit.art_scale
	for l: Battle.Lens in core.battle.lenses:
		_draw_lens(kit.to_art(l.pos).round(), radius, l.mode, l.index)


func _draw_lens(c: Vector2, r: float, mode: String, index: int) -> void:
	var dark: Color = _c["soot_0"]
	var hi: Color = _c["brass_3"]
	var mid: Color = _c["brass_2"]
	var lo: Color = _c["brass_1"]
	var notch: Color = _c["brass_3"]
	if mode == "auto":
		hi = _c["iron_3"]
		mid = _c["iron_2"]
		lo = _c["iron_1"]
		notch = _c["steam_3"]
	elif mode == "seek":
		notch = _c["teal_2"]
	var ga: float = kit.f("lens.glass_alpha", 0.1)
	draw_circle(c, r - 1.0, Color(_c["teal_2"], ga))
	draw_arc(c, r + 2.0, 0.0, TAU, 48, dark, 1.0)
	draw_arc(c, r + 1.0, 0.0, TAU, 48, mid, 1.0)
	draw_arc(c, r + 1.0, PI * 0.95, PI * 1.55, 16, hi, 1.0)
	draw_arc(c, r, 0.0, TAU, 48, lo, 1.0)
	draw_arc(c, r, PI * 0.9, PI * 1.6, 16, mid, 1.0)
	draw_arc(c, r - 1.0, 0.0, TAU, 48, dark, 1.0)
	# turning notches (the ring rotates slowly; faster in manual mode)
	var spin: float = _time * (0.9 if mode == "manual" else 0.35) + index * 0.5
	for j in 4:
		var ang: float = spin + TAU * j / 4.0
		var d := Vector2(cos(ang), sin(ang))
		var p: Vector2 = (c + d * (r + 3.0)).round()
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), dark)
		draw_rect(Rect2(p, Vector2(1, 1)), notch)
	draw_rect(Rect2(c + Vector2(-2, 0), Vector2(5, 1)), Color(hi, 0.6))
	draw_rect(Rect2(c + Vector2(0, -2), Vector2(1, 5)), Color(hi, 0.6))
	if index == 0 and mode != "manual":
		var txt: String = tr("UI_LENS_" + mode.to_upper())
		draw_string(kit.FONT_NUMBER, Vector2(c.x - 30, c.y + r + 12), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, 12,
			Color(_c["steam_2"] if mode == "auto" else _c["teal_2"], kit.f("lens.label_alpha", 0.75)))


func lens_tick(screen_pos: Vector2, hits: int) -> void:
	if hits <= 0:
		return
	var c: Vector2 = kit.to_art(screen_pos)
	var r: float = float(core.mods.lens["radius"]) / kit.art_scale
	for j in mini(hits, int(kit.f("lens.spark_max", 4))):
		var ang: float = randf() * TAU
		var p: Vector2 = c + Vector2(cos(ang), sin(ang)) * r * sqrt(randf()) * 0.85
		particle(p, Vector2(randf_range(-3.0, 3.0), randf_range(-22.0, -12.0)),
			_c["ember_2"] if j % 2 == 0 else _c["brass_3"], 0.35, 1.0)
	if randf() < 0.3:
		particle(c + Vector2(randf_range(-r, r) * 0.5, 0), Vector2(0, -10), _c["steam_2"], 0.6, 2.0)
