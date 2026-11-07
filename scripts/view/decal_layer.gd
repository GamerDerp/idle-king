class_name DecalLayer
extends Node2D
## Ground marks under the units (art pixels): fading scorch marks of blasts,
## boiling puddles (battle.zones) and dirt mounds of burrowed enemies.

class Scorch:
	var pos: Vector2 = Vector2.ZERO
	var r: float = 8.0
	var t: float = 0.0
	var life: float = 4.0

const MAX_SCORCH: int = 40

var kit: ViewKit
var draw_ms: float = 0.0          ## last _draw cost (perf readout)
var bv: BattleView
var scorches: Array[Scorch] = []
var _time: float = 0.0


func setup(view_kit: ViewKit, battle_view: BattleView) -> void:
	kit = view_kit
	bv = battle_view


func scorch(pos: Vector2, radius_art: float) -> void:
	if scorches.size() >= MAX_SCORCH:
		scorches.pop_front()
	var s := Scorch.new()
	s.pos = pos.round()
	s.r = clampf(radius_art * 0.45, 4.0, 14.0)
	s.life = kit.f("scorch.life", 4.0)
	scorches.append(s)


func _process(delta: float) -> void:
	_time += delta
	var i: int = scorches.size() - 1
	while i >= 0:
		scorches[i].t += delta
		if scorches[i].t >= scorches[i].life:
			scorches.remove_at(i)
		i -= 1


var _unit: PackedVector2Array = PackedVector2Array()
var _pts: PackedVector2Array = PackedVector2Array()


## Irregular filled ellipse (a fixed wobbly outline, scaled).
func _blob(c: Vector2, rx: float, ry: float, col: Color) -> void:
	if _unit.is_empty():
		for j in 12:
			var ang: float = TAU * j / 12.0
			var wob: float = 1.0 + 0.12 * sin(ang * 3.0 + 0.7)
			_unit.append(Vector2(cos(ang) * wob, sin(ang) * wob))
		_pts.resize(12)
	for j in 12:
		_pts[j] = (c + _unit[j] * Vector2(rx, ry)).round()
	draw_colored_polygon(_pts, col)


func _draw() -> void:
	var _pt0: int = Time.get_ticks_usec()
	_draw_body()
	draw_ms = (Time.get_ticks_usec() - _pt0) / 1000.0


func _draw_body() -> void:
	var a0: float = kit.f("scorch.alpha", 0.45)
	var soot: Color = kit.col("soot_1")
	var soot2: Color = kit.col("soot_2")
	for s: Scorch in scorches:
		var k: float = 1.0 - s.t / s.life
		_blob(s.pos, s.r, s.r * 0.5, Color(soot2, a0 * k))
		_blob(s.pos, s.r * 0.6, s.r * 0.3, Color(soot, a0 * k))
	var core: GameCore = kit.core
	var teal: Color = kit.col("teal_1")
	var teal2: Color = kit.col("teal_2")
	var steam: Color = kit.col("steam_3")
	for z: Battle.Zone in core.battle.zones:
		var c: Vector2 = kit.to_art(z.pos).round()
		var r: float = z.radius / kit.art_scale
		var left: float = clampf(1.0 - z.t / maxf(0.01, z.duration), 0.0, 1.0)
		var fade: float = clampf(left * 4.0, 0.0, 1.0)
		_blob(c, r, r * 0.5, Color(teal, 0.55 * fade))
		_blob(c, r * 0.7, r * 0.33, Color(teal2, 0.5 * fade))
		for j in 3:
			var ph: float = fmod(_time * 1.7 + j * 0.37 + z.uid * 0.13, 1.0)
			var bp: Vector2 = c + Vector2(sin(j * 2.1 + z.uid) * r * 0.5, cos(j * 1.7) * r * 0.2 - ph * 3.0)
			draw_rect(Rect2(bp.round(), Vector2(1, 1)), Color(steam, fade * (1.0 - ph)))
	var dust0: Color = kit.col("dust_0")
	var dust2: Color = kit.col("dust_2")
	for e: Battle.Enemy in core.battle.enemies:
		if not e.alive or not e.underground:
			continue
		var m: Vector2 = kit.to_art(e.pos).round()
		_blob(m + Vector2(1, 0), 6.0, 3.0, dust0)
		_blob(m + Vector2(0, -1), 5.0, 2.5, dust2)
		var wig: float = roundf(sin(_time * 14.0 + e.uid) * 1.0)
		draw_rect(Rect2(m + Vector2(-2 + wig, -3), Vector2(2, 1)), dust2)
