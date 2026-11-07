class_name MoatFx
extends Node2D
## The boiling moat between the wall and the field, in art pixels (child of BattleView), so it looks
## alive even before the curtain is bought and when nothing falls in (C2b):
##  - layer "water" (above the water tiles, under the curtain sprite): bubbles rise and pop on the
##    water, faster when the curtain burns;
##  - layer "steam" (above the curtain sprite and the bank, under the enemies): a billowing crest of
##    steam along the near bank that rises and drifts east onto the field edge, so the curtain reads
##    as a wall of steam rather than a band of waves. Sparse without the curtain, dense with it.
## Everything is in one _draw per layer. Numbers: config/visual.json → game_view.moat.

class Blob:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var t: float = 0.0
	var life: float = 1.0
	var r0: float = 2.0
	var r1: float = 6.0

var kit: ViewKit
var core: GameCore
var layer: String = "water"
var blobs: Array[Blob] = []
var _acc: float = 0.0
var _moat: Vector2 = Vector2(108, 137)
var _bank: float = 138.0
var _h: float = 340.0
var _c: Dictionary = {}
var _puff: Array[Texture2D] = []
var _puff_anchor: Vector2 = Vector2(8, 12)


func setup(view_kit: ViewKit, which: String) -> void:
	kit = view_kit
	core = kit.core
	layer = which
	var lay: Dictionary = SpriteLib.layout()
	var mx: Array = lay.get("moat_x", [108, 137])
	_moat = Vector2(float(mx[0]), float(mx[1]))
	_bank = float((lay.get("bank_x", [138, 145]) as Array)[0])
	_h = float((lay.get("size", [450, 340]) as Array)[1])
	for n: String in ["steam_1", "steam_2", "steam_3", "teal_1", "teal_2"]:
		_c[n] = kit.col(n)
	for k in range(int(SpriteLib.info("steam_puff").get("frames", 4))):
		_puff.append(SpriteLib.texture("steam_puff", k))
	_puff_anchor = SpriteLib.anchor("steam_puff")
	# start with the moat already busy (no empty first second)
	for i in int(kit.f("moat.%s.prewarm" % layer, 20)):
		_spawn(randf())


## 0 without the curtain, 1 with a fresh one, up to ~2 when it is hot.
func heat() -> float:
	if core.mods.moat_dps <= 0.0:
		return 0.0
	return clampf(core.mods.moat_dps / kit.f("moat.hot_dps", 30.0), 0.0, 1.0) + 1.0


func _spawn(age_k: float = 0.0) -> void:
	var b := Blob.new()
	if layer == "water":
		b.pos = Vector2(randf_range(_moat.x + 2.0, _moat.y - 2.0), randf_range(2.0, _h - 2.0))
		b.vel = Vector2(randf_range(-1.0, 1.0), randf_range(-3.0, -1.0))
		b.life = randf_range(0.5, 1.1)
		b.r0 = 1.0
		b.r1 = randf_range(1.5, 3.0)
	else:
		var w: float = kit.f("moat.steam.spread", 10.0)
		b.pos = Vector2(_bank + randf_range(-6.0, w * 0.4), randf_range(-4.0, _h + 4.0))
		b.vel = Vector2(randf_range(2.0, 6.0) * (1.0 + 0.5 * heat()), randf_range(-7.0, -3.0))
		b.life = randf_range(1.6, 3.0)
	b.t = b.life * age_k
	blobs.append(b)


func _process(delta: float) -> void:
	var h: float = heat()
	var rate: float = kit.f("moat.%s.per_s" % layer, 10.0) * (1.0 + kit.f("moat.%s.heat_k" % layer, 1.0) * h)
	_acc += rate * delta
	var cap: int = int(kit.f("moat.%s.max" % layer, 80))
	while _acc >= 1.0:
		_acc -= 1.0
		if blobs.size() < cap:
			_spawn()
	var i: int = blobs.size() - 1
	while i >= 0:
		var b: Blob = blobs[i]
		b.t += delta
		b.pos += b.vel * delta
		if b.t >= b.life:
			blobs[i] = blobs[blobs.size() - 1]
			blobs.pop_back()
		i -= 1
	queue_redraw()


func _draw() -> void:
	if layer == "water":
		_draw_bubbles()
	else:
		_draw_steam()


func _draw_bubbles() -> void:
	for b: Blob in blobs:
		var k: float = b.t / b.life
		var p: Vector2 = b.pos.round()
		if k < 0.75:
			# a bubble swelling on the surface: light dot with a dark rim below
			var s: float = 1.0 if k < 0.35 else 2.0
			draw_rect(Rect2(p + Vector2(0, s), Vector2(s, 1)), Color(_c["teal_1"], 0.8))
			draw_rect(Rect2(p, Vector2(s, s)), Color(_c["steam_3"], 0.85))
		else:
			# pop: a small ring that widens and fades
			var kk: float = (k - 0.75) / 0.25
			draw_arc(p, b.r0 + (b.r1 - b.r0) * kk, 0.0, TAU, 10, Color(_c["steam_2"], 0.8 * (1.0 - kk)), 1.0)


func _draw_steam() -> void:
	# pixel-art puffs (steam_puff frames: small → billowing → thinning), crisp in art pixels
	var base_a: float = kit.f("moat.steam.alpha", 0.75)
	var nfr: int = _puff.size()
	for b: Blob in blobs:
		var k: float = b.t / b.life
		var fi: int = mini(int(k * nfr), nfr - 1)
		var tex: Texture2D = _puff[fi]
		# fade in quickly, out slowly; thinner as it drifts away from the bank onto the field
		var a: float = base_a * minf(1.0, k * 6.0) * (1.0 - k * k)
		draw_texture(tex, (b.pos - _puff_anchor).round(), Color(1, 1, 1, a))
