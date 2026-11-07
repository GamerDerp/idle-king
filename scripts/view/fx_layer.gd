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
	var rot: float = 0.0
	var life: float = 0.0          ## > 0: loop the frames until this many seconds (retreat, drill ram)
	var fade: float = 0.0          ## > 0: fade out over the last `fade` seconds of `life`


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
	var pts: PackedVector2Array = PackedVector2Array()   ## bolt: muzzle -> every enemy it jumped to (art px)


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
var _low_prio: bool = false


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

func anim(sprite_name: String, pos: Vector2, flip: bool = false, mod: Color = Color.WHITE, vel: Vector2 = Vector2.ZERO,
		rot: float = 0.0) -> Anim:
	if anims.size() >= MAX_ANIMS:
		return null
	var s: Dictionary = _sprite(sprite_name)
	var a := Anim.new()
	a.frames = s["frames"]
	a.fps = maxf(1.0, float(s["fps"]))
	a.anchor = s["anchor"]
	a.pos = pos.round()
	a.flip = flip
	a.mod = mod
	a.vel = vel
	a.rot = rot
	anims.append(a)
	return a


## A looping animation that lives `life` seconds (moves with `vel`, fades at the end).
func loop_anim(sprite_name: String, pos: Vector2, life: float, vel: Vector2 = Vector2.ZERO, flip: bool = false,
		fade: float = 0.3) -> Anim:
	var a: Anim = anim(sprite_name, pos, flip, Color.WHITE, vel)
	if a != null:
		a.life = life
		a.fade = fade
	return a


func particle(pos: Vector2, vel: Vector2, color: Color, life: float, size: float = 1.0, grav: float = 0.0, ground: float = -1.0) -> void:
	if particles.size() >= MAX_PARTICLES:
		return
	if _low_prio and particles.size() >= int(MAX_PARTICLES * kit.f("particles.low_prio_share", 0.6)):
		return   # hit sparks are the first to go when the field is busy
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
	_low_prio = not crit
	_hit_sparks(pos, dmg_type, crit)
	_low_prio = false


func _hit_sparks(pos: Vector2, dmg_type: String, crit: bool) -> void:
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


func explosion(pos: Vector2, radius_art: float, crit: bool, fragment: bool, sprite: String = "explosion") -> void:
	if fragment:
		anim("hit_spark", pos)
		burst(pos, ["ember_2", "brass_3", "soot_2"], 4, 22.0, 0.3, 50.0)
		return
	anim(sprite, pos + Vector2(0, 4))
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


func fall(pos: Vector2, enemy_type: String, fall_sprite: String = "") -> void:
	var sp: Dictionary = kit.enemy_sprites(enemy_type)
	var x: float = bv.bank_x() - 9.0
	var p := Vector2(x, pos.y)
	anim(fall_sprite if fall_sprite != "" else str(sp.get("fall", "scavenger_fall")), p)
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


## Steam jet: the cone sprite at the nozzle, steam puffs rolling out along the real reach, droplets.
## (No flat polygon: a pale triangle over the field read as a UI wedge, not steam.)
func cone(from_screen: Vector2, dir: Vector2, length: float, angle: float) -> void:
	var a: Vector2 = bv.muzzle_for_start(from_screen)
	var r: float = length / kit.art_scale
	anim("steam_cone", a, false, Color(1, 1, 1, 0.9), Vector2.ZERO, dir.angle())
	var reach: float = float(SpriteLib.frame_size("steam_cone").x)
	for k: float in kit.v("fx.cone_puffs", [0.55, 0.8, 1.0]):
		var d: Vector2 = dir.rotated(randf_range(-angle, angle) * 0.6)
		var at: Vector2 = a + d * maxf(reach * 0.8, r * k)
		anim("steam_puff", at + Vector2(0, -4), randf() < 0.5, Color(1, 1, 1, 0.6), d * 16.0)
	for i in 4:
		var d2: Vector2 = dir.rotated(randf_range(-angle, angle))
		var dist: float = randf_range(0.3, 1.0) * r
		particle(a + d2 * dist * 0.3, d2 * dist * 1.6, _c["steam_3"] if i % 2 == 0 else _c["steam_2"], 0.45, 2.0)


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


## Tesla lightning: muzzle -> every enemy in the chain (sprite links stretched along each jump),
## a crackle on every enemy it went through.
func bolt(from_screen: Vector2, points: Array) -> void:
	var l := Line.new()
	l.kind = "bolt"
	l.pts.append(bv.muzzle_for_start(from_screen))
	for p: Variant in points:
		var ap: Vector2 = kit.to_art(p as Vector2) + Vector2(0, -6)
		l.pts.append(ap)
		anim("tesla_arc", ap)
	l.life = kit.f("fx.bolt_time", 0.2)
	lines.append(l)
	anim("tesla_arc", l.pts[0])
	if points.size() > 0:
		burst(l.pts[l.pts.size() - 1], ["teal_2", "steam_3", "brass_3"], 4, 36.0, 0.2)


## Ricochet ball bounced off an enemy: spark at the hit, a faint trail toward the next one.
func ricochet(from_screen: Vector2, to_screen: Vector2, bounce: int) -> void:
	var a: Vector2 = kit.to_art(from_screen) + Vector2(0, -6)
	anim("bounce_spark", a)
	burst(a, ["brass_3", "iron_3", "parchment_2"], 3 + mini(bounce, 3), 34.0, 0.22, 40.0)
	var l := Line.new()
	l.kind = "trail"
	l.a = a
	l.b = kit.to_art(to_screen) + Vector2(0, -6)
	l.life = 0.18
	lines.append(l)


## Geysers: an eruption of boiling water at the busiest spot by the moat.
func geyser(center_screen: Vector2, radius: float) -> void:
	var c: Vector2 = kit.to_art(center_screen)
	var r: float = radius / kit.art_scale
	anim("geyser", c + Vector2(0, 2))
	anim("geyser", c + Vector2(-r * 0.55, -r * 0.25).round(), true)
	anim("geyser", c + Vector2(r * 0.5, r * 0.3).round())
	anim("splash", c + Vector2(0, 3))
	burst(c + Vector2(0, -6), ["steam_3", "teal_2", "steam_2"], 16, 46.0, 0.6, 90.0, 1.0, 40.0)
	for i in 3:
		anim("steam_puff", c + Vector2(randf_range(-r, r) * 0.6, randf_range(-14.0, -4.0)), randf() < 0.5)


## Drill ram (Бур trophy): the drill rolls along one lane from the moat, dust and sparks behind it.
func drill_ram(y_screen: float, x0_screen: float, x1_screen: float) -> void:
	var a: Vector2 = kit.to_art(Vector2(x0_screen, y_screen))
	var b: Vector2 = kit.to_art(Vector2(x1_screen, y_screen))
	var speed: float = kit.f("fx.drill_ram_speed", 260.0)
	var life: float = maxf(0.3, (b.x - a.x) / speed)
	loop_anim(str(kit.v("fx.drill_ram_sprite", "drill_boss_walk")), a, life, Vector2(speed, 0), true, 0.25)
	var l := Line.new()
	l.kind = "furrow"
	l.a = a + Vector2(0, 1)
	l.b = b + Vector2(0, 1)
	l.life = life + 0.6
	l.r = life
	lines.append(l)
	for i in 10:
		var k: float = float(i) / 10.0
		particle(a.lerp(b, k), Vector2(randf_range(-10.0, 10.0), randf_range(-26.0, -10.0)),
			_c["dust_2"] if i % 2 == 0 else _c["soot_2"], 0.6 + k * life, 2.0, 40.0, a.y + 2.0)


## Coal golem shatters: the split animation + embers flying out.
func split(pos_art: Vector2, sprite: String) -> void:
	anim(sprite, pos_art)
	burst(pos_art + Vector2(0, -8), ["ember_2", "ember_1", "brass_3", "soot_2"], 14, 46.0, 0.6, 110.0, 1.0, 30.0)


## A copper diver helmet bursts (shield broken): glass, rivets, the shell rolls away.
func helmet_break(pos_art: Vector2, sprite: String) -> void:
	anim(sprite, pos_art)
	burst(pos_art + Vector2(0, -16), ["copper_3", "copper_2", "steam_3", "teal_2"], 12, 52.0, 0.6, 140.0, 1.0, 34.0)


## Direct fire on frontal armour: a hard "dzing" — iron/brass sparks off the plate (front = left side).
func armor_spark(pos_art: Vector2, crit: bool) -> void:
	_low_prio = not crit
	burst(pos_art, ["brass_3", "iron_3", "parchment_2", "steam_3"], 6 if crit else 4, 58.0, 0.22, 70.0, 1.0, 14.0)
	_low_prio = false


func shield_spark(pos_art: Vector2) -> void:
	_low_prio = true
	burst(pos_art, ["copper_3", "brass_3", "steam_3"], 3, 40.0, 0.2, 60.0, 1.0, 10.0)
	_low_prio = false


## Dash (Бур-Великан): dust bursts behind the treads.
func dust(pos_art: Vector2, n: int) -> void:
	burst(pos_art, ["dust_2", "dust_0", "soot_2"], n, 30.0, 0.5, 40.0, 2.0, 12.0)


# --- update & draw ------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var i: int = anims.size() - 1
	while i >= 0:
		var a: Anim = anims[i]
		a.t += delta
		a.pos += a.vel * delta
		if (a.life > 0.0 and a.t >= a.life) or (a.life <= 0.0 and int(a.t * a.fps) >= a.frames.size()):
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
		var fi: int = (int(a.t * a.fps) % a.frames.size()) if a.life > 0.0 else mini(int(a.t * a.fps), a.frames.size() - 1)
		var tex: Texture2D = a.frames[fi]
		if a.fade > 0.0 and a.life > 0.0:
			a.mod.a = clampf((a.life - a.t) / a.fade, 0.0, 1.0)
		if a.flip or a.rot != 0.0:
			draw_set_transform(a.pos.round(), a.rot, Vector2(-1, 1) if a.flip else Vector2.ONE)
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
	_draw_producers()
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
				var proj: String = str(kit.v("projectile_sprites." + kit.tower_base(p.tower), "shell"))
				var nfr: int = int(SpriteLib.info(proj).get("frames", 1))
				var fr: int = int(_time * 12.0 + p.uid) % maxi(1, nfr)
				draw_texture(SpriteLib.texture(proj, fr), (pos - SpriteLib.anchor(proj)).round())
			"ricochet":
				# the ball flies like a bullet from the muzzle; after a bounce it starts where it hit
				var m4: Vector2 = bv.muzzle_for_start(p.start) if p.bounce == 0 else start
				var dst4: Vector2 = kit.to_art(p.dest)
				var d4: float = maxf(1.0, dst4.distance_to(start))
				var k4: float = clampf(ap.distance_to(start) / d4, 0.0, 1.0) if p.bounce == 0 else 1.0
				var pos4: Vector2 = (ap + (m4 - start) * (1.0 - k4)).round() + Vector2(0, -6 if p.bounce > 0 else 0)
				var fr4: int = int(_time * 14.0 + p.uid) % 4
				draw_texture(SpriteLib.texture("ricochet_ball", fr4), pos4 - SpriteLib.anchor("ricochet_ball"),
					_c["ember_2"] if p.crit else Color.WHITE)
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
		"bolt":
			_draw_bolt(l, k)
		"trail":
			var col3: Color = Color(_c["parchment_2"], 0.7 * (1.0 - k))
			var n2: int = int(l.a.distance_to(l.b) / 4.0)
			for j in n2:
				if j % 2 == 0:
					draw_rect(Rect2(l.a.lerp(l.b, float(j) / maxf(1.0, n2)).round(), Vector2(1, 1)), col3)
		"furrow":
			# the ram's track: a dark furrow that grows behind the drill, then fades
			var grow: float = clampf(l.t / maxf(0.01, l.r), 0.0, 1.0)
			var fade2: float = clampf((l.life - l.t) / 0.6, 0.0, 1.0)
			var e: Vector2 = l.a.lerp(l.b, grow).round()
			draw_rect(Rect2(l.a.round() + Vector2(0, -1), Vector2(e.x - l.a.x, 3)), Color(_c["soot_1"], 0.45 * fade2))
			draw_rect(Rect2(l.a.round() + Vector2(0, -1), Vector2(e.x - l.a.x, 1)), Color(_c["dust_2"], 0.5 * fade2))
		"bubble":
			var rr: float = l.r + 9.0 * k
			var col2: Color = l.color
			col2.a = 0.9 * (1.0 - k)
			_ellipse(l.a, rr, rr * 0.45, col2)


func _draw_bolt(l: Line, k: float) -> void:
	var nfr: int = int(SpriteLib.info("chain_lightning").get("frames", 3))
	var anc: Vector2 = SpriteLib.anchor("chain_lightning")
	var w: float = float(SpriteLib.frame_size("chain_lightning").x)
	var mod: Color = Color(1, 1, 1, clampf(2.0 * (1.0 - k), 0.0, 1.0))
	for j in l.pts.size() - 1:
		var a: Vector2 = l.pts[j]
		var b: Vector2 = l.pts[j + 1]
		var len: float = a.distance_to(b)
		if len < 1.0:
			continue
		var fr: int = (int(l.t * 16.0) + j) % maxi(1, nfr)
		draw_set_transform(a.round(), (b - a).angle(), Vector2(len / w, 1.0))
		draw_texture(SpriteLib.texture("chain_lightning", fr), -anc, mod)
	draw_set_transform(Vector2.ZERO)


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
	var field_w: float = (1280.0 - kit.f("panel_width", 380)) / kit.art_scale
	var new_w: float = kit.FONT_NUMBER.get_string_size(tr("UI_NEW"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	for e: Battle.Enemy in core.battle.enemies:
		if not e.alive or e.underground:
			continue
		var ev: BattleView.EnemyView = bv.enemy_view(e.uid)
		if ev == null:
			continue
		var head: float = _head_of(e.type)
		var top: Vector2 = ev.art_pos + Vector2(0, -head - 3)
		var w: float = 0.0
		if e.uid != boss_uid and e.hp < e.max_hp:
			w = clampf(roundf(e.radius), 8.0, 18.0)
			var x0: float = roundf(top.x - w * 0.5)
			draw_rect(Rect2(x0 - 1, top.y - 1, w + 2, 3), bg)
			var frac: float = clampf(e.hp / e.max_hp, 0.0, 1.0)
			draw_rect(Rect2(x0, top.y, maxf(1.0, roundf(w * frac)), 1), fill if frac > 0.35 else low)
			if e.shield_hp > 0.0 and e.shield_max > 0.0:
				# the copper helmet's own strip right under the health bar
				draw_rect(Rect2(x0 - 1, top.y + 2, w + 2, 2), bg)
				draw_rect(Rect2(x0, top.y + 2, maxf(1.0, roundf(w * e.shield_hp / e.shield_max)), 1), _c["copper_3"])
		_draw_statuses(e, ev, top + (Vector2(0, 10) if e.uid == boss_uid else Vector2.ZERO), w)
		if e.charging and randf() < 0.5:
			# Бур-Великан dashing: dust kicked up behind the treads
			_low_prio = true
			particle(ev.art_pos + Vector2(randf_range(8.0, 24.0), randf_range(-3.0, 1.0)),
				Vector2(randf_range(10.0, 30.0), randf_range(-14.0, -4.0)), _c["dust_2"] if randf() < 0.6 else _c["soot_2"], 0.5, 2.0)
			_low_prio = false
		if e.bait > 0:
			_draw_sacks(ev.art_pos + Vector2(0, -head * 0.7), mini(e.bait, 3))
		if e.scald_t > 0.0 and randf() < 0.12:
			_low_prio = true
			particle(ev.art_pos + Vector2(randf_range(-4.0, 4.0), -head * randf_range(0.3, 0.9)),
				Vector2(randf_range(-2.0, 2.0), -12.0), _c["steam_3"], 0.45, 1.0)
			_low_prio = false
		if ev.new_t > 0.0:
			# kept inside the field: a just-arrived enemy stands at the panel edge
			var bob: float = roundf(sin(_time * 6.0))
			var tw: float = new_w * 0.5 + 2.0
			var cx: float = clampf(top.x, tw, field_w - tw)
			draw_string(kit.FONT_NUMBER, Vector2(roundf(cx - 30), roundf(maxf(top.y - 3, 14.0) + bob)), tr("UI_NEW"),
				HORIZONTAL_ALIGNMENT_CENTER, 60, 12, _c["brass_3"])


## A brass gauge under every workshop in the yard: how far its current batch is (core.producer_progress).
func _draw_producers() -> void:
	for pid: String in bv.buildings:
		var b: AnimatedSprite2D = bv.buildings[pid]
		var w: float = kit.f("producer.gauge_w", 30.0)
		var at: Vector2 = (b.position + Vector2(-w * 0.5, kit.f("producer.gauge_dy", 3.0))).round()
		var k: float = clampf(core.producer_progress(pid), 0.0, 1.0)
		draw_rect(Rect2(at - Vector2(1, 1), Vector2(w + 2, 4)), _c["soot_0"])
		draw_rect(Rect2(at, Vector2(w, 2)), _c["iron_1"])
		draw_rect(Rect2(at, Vector2(roundf(w * k), 2)), _c["brass_3"] if k < 0.92 else _c["ember_2"])
		draw_rect(Rect2(at, Vector2(roundf(w * k), 1)), _c["parchment_2"] if k >= 0.92 else _c["brass_2"])
		# little rivets at the ends
		draw_rect(Rect2(at + Vector2(-2, 0), Vector2(1, 2)), _c["brass_2"])
		draw_rect(Rect2(at + Vector2(w + 1, 0), Vector2(1, 2)), _c["brass_2"])


## A workshop delivered a batch: coal chunks hop out of the building.
func producer_burst(pos_art: Vector2) -> void:
	for i in 4:
		anim("coal_chunk_fly", pos_art + Vector2(randf_range(-8.0, 8.0), randf_range(-30.0, -18.0)), false, Color.WHITE,
			Vector2(randf_range(-6.0, 14.0), randf_range(-28.0, -16.0)))
	burst(pos_art + Vector2(0, -26), ["soot_2", "iron_3", "brass_3"], 8, 30.0, 0.5, 60.0, 1.0, 20.0)
	anim("steam_puff", pos_art + Vector2(6, -40))


## Status icons over the head, baked once into small textures with a 1-px dark outline (readable on any
## ground, one draw call each): stun = brass stars circling the head, slow = a teal chevron, scald = a
## steam drop. `hp_w` > 0: right of the HP bar. Bait sacks use the same baking.
const ICON_SLOW: Array[String] = ["#...#", "##.##", ".###.", "..#.."]
const ICON_SCALD: Array[String] = [".#.", "#o#", "#o#", ".#."]
const ICON_STAR: Array[String] = [".#.", "#o#", ".#."]
const ICON_SACK: Array[String] = [".o.", "###", "###"]
var _icons: Dictionary = {}


func _bake(key: String, px: Array[String], col: Color, col2: Color) -> Texture2D:
	if _icons.has(key):
		return _icons[key]
	var w: int = px[0].length()
	var h: int = px.size()
	var img := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	var dark: Color = _c["soot_0"]
	for yy in h:
		for xx in w:
			if px[yy][xx] != ".":
				for oy in 3:
					for ox in 3:
						img.set_pixel(xx + ox, yy + oy, dark)
	for yy in h:
		for xx in w:
			var ch: String = px[yy][xx]
			if ch == "#":
				img.set_pixel(xx + 1, yy + 1, col)
			elif ch == "o":
				img.set_pixel(xx + 1, yy + 1, col2)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


func _draw_statuses(e: Battle.Enemy, ev: BattleView.EnemyView, top: Vector2, hp_w: float) -> void:
	var x: float = roundf(top.x + hp_w * 0.5 + 2.0) if hp_w > 0.0 else roundf(top.x - 3.0)
	var y: float = top.y - 2.0
	if e.stun_t > 0.0:
		# two stars circling the head (classic "dizzy")
		var head_c: Vector2 = ev.art_pos + Vector2(0, -_head_of(e.type) + 1)
		var rx: float = clampf(e.radius / kit.art_scale + 3.0, 5.0, 14.0)
		var star: Texture2D = _bake("star", ICON_STAR, _c["brass_3"], _c["parchment_2"])
		for j in 2:
			var ang: float = _time * 7.0 + PI * j
			draw_texture(star, (head_c + Vector2(cos(ang) * rx, sin(ang) * 2.0 - 2.0)).round() - Vector2(2, 2))
	if e.slow_t > 0.0 and e.slow_f > 0.0:
		var t1: Texture2D = _bake("slow", ICON_SLOW, _c["teal_2"], _c["teal_2"])
		draw_texture(t1, Vector2(x, y - 1))
		x += t1.get_width()
	if e.scald_t > 0.0:
		var t2: Texture2D = _bake("scald", ICON_SCALD, _c["steam_3"], _c["teal_2"])
		draw_texture(t2, Vector2(x, y - 1))


## Bait: loot sacks on the back of an enemy whose type has bait bought (one per level, max 3).
func _draw_sacks(at: Vector2, n: int) -> void:
	var sack: Texture2D = _bake("sack", ICON_SACK, _c["parchment_2"], _c["brass_3"])
	for j in n:
		draw_texture(sack, (at + Vector2(3 + j * 3, -1 - j * 2)).round())


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
