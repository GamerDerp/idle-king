class_name LootFly
extends Node2D
## Top layer (screen pixels, above the UI): loot icons flying in an arc from a
## kill to the matching counter in the resource bar (the counter bumps when
## they arrive), gear fountains (boss), and UI sparks (purchases).

class Coin:
	var a: Vector2 = Vector2.ZERO
	var c: Vector2 = Vector2.ZERO
	var t: float = 0.0
	var dur: float = 0.7
	var res: String = "gears"
	var amount: float = 0.0
	var vel: Vector2 = Vector2.ZERO   ## fountain phase (ballistic) while t < 0
	var pos: Vector2 = Vector2.ZERO
	var spin: int = 0


class Spark:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var t: float = 0.0
	var life: float = 0.4
	var color: Color = Color.WHITE

var kit: ViewKit
var draw_ms: float = 0.0          ## last _draw cost (perf readout)
var coins: Array[Coin] = []
var sparks: Array[Spark] = []
var target_cb: Callable    ## func(res: String) -> Vector2
var arrive_cb: Callable    ## func(res: String, amount: float) -> void
var _time: float = 0.0


func setup(view_kit: ViewKit) -> void:
	kit = view_kit


func _max() -> int:
	return int(kit.f("loot.max_flying", 70))


## n icons carrying `amount` of `res` from screen point `from`.
func fly(from: Vector2, res: String, amount: float, n: int) -> void:
	if amount <= 0.0:
		return
	n = clampi(n, 1, 8)
	if coins.size() + n > _max():
		n = maxi(0, _max() - coins.size())
		if n == 0:
			arrive_cb.call(res, amount)
			return
	var ft: Array = kit.v("loot.fly_time", [0.55, 0.85])
	for i in n:
		var co := Coin.new()
		co.a = from + Vector2(randf_range(-8.0, 8.0), randf_range(-12.0, 0.0))
		co.pos = co.a
		co.res = res
		co.amount = amount / n
		co.dur = randf_range(float(ft[0]), float(ft[1]))
		co.t = -0.05 * i
		co.spin = randi() % 5
		var b: Vector2 = _target(res)
		co.c = (co.a + b) * 0.5 + Vector2(randf_range(-60.0, 60.0), -kit.f("loot.arc_height", 90.0))
		coins.append(co)


## Boss fountain: coins burst upward first, then home in on the counter.
func fountain(from: Vector2, res: String, amount: float, n: int) -> void:
	var ft: Array = kit.v("loot.fly_time", [0.55, 0.85])
	for i in n:
		var co := Coin.new()
		co.pos = from
		co.vel = Vector2(randf_range(-160.0, 160.0), randf_range(-420.0, -220.0))
		co.t = -randf_range(0.45, 0.8)
		co.res = res
		co.amount = amount / n
		co.dur = randf_range(float(ft[0]), float(ft[1]))
		co.spin = randi() % 5
		coins.append(co)


func burst(pos: Vector2, color_names: Array, n: int, speed: float = 220.0) -> void:
	for i in n:
		var s := Spark.new()
		var ang: float = randf() * TAU
		s.pos = pos
		s.vel = Vector2(cos(ang), sin(ang)) * speed * randf_range(0.35, 1.0)
		s.life = randf_range(0.25, 0.5)
		s.color = kit.col(str(color_names[i % color_names.size()]))
		sparks.append(s)


func _target(res: String) -> Vector2:
	return target_cb.call(res) if target_cb.is_valid() else Vector2(40, 20)


func _process(delta: float) -> void:
	_time += delta
	var i: int = coins.size() - 1
	while i >= 0:
		var co: Coin = coins[i]
		co.t += delta
		if co.t < 0.0:
			if co.vel != Vector2.ZERO:
				co.vel.y += 900.0 * delta
				co.pos += co.vel * delta
				co.a = co.pos
				var b0: Vector2 = _target(co.res)
				co.c = (co.a + b0) * 0.5 + Vector2(0, -60.0)
		else:
			var k: float = clampf(co.t / co.dur, 0.0, 1.0)
			var kk: float = k * k
			var b: Vector2 = _target(co.res)
			co.pos = co.a.lerp(co.c, kk).lerp(co.c.lerp(b, kk), kk)
			if k >= 1.0:
				arrive_cb.call(co.res, co.amount)
				coins[i] = coins[coins.size() - 1]
				coins.pop_back()
		i -= 1
	i = sparks.size() - 1
	while i >= 0:
		var s: Spark = sparks[i]
		s.t += delta
		s.vel *= 0.92
		s.vel.y += 300.0 * delta
		s.pos += s.vel * delta
		if s.t >= s.life:
			sparks[i] = sparks[sparks.size() - 1]
			sparks.pop_back()
		i -= 1
	queue_redraw()


func _draw() -> void:
	var _pt0: int = Time.get_ticks_usec()
	_draw_body()
	draw_ms = (Time.get_ticks_usec() - _pt0) / 1000.0


func _draw_body() -> void:
	for co: Coin in coins:
		if co.t < 0.0 and co.vel == Vector2.ZERO:
			continue
		var p: Vector2 = (co.pos * 0.5).round() * 2.0
		if co.res == "gears":
			var fr: int = (int(_time * 14.0) + co.spin) % 5
			var tex: Texture2D = SpriteLib.texture("gear_coin_fly", fr)
			draw_texture_rect(tex, Rect2(p - Vector2(8, 8), Vector2(16, 16)), false)
		else:
			var tex2: Texture2D = SpriteLib.texture(kit.res_icon(co.res))
			draw_texture_rect(tex2, Rect2(p - Vector2(8, 8), Vector2(16, 16)), false)
	for s: Spark in sparks:
		var c: Color = s.color
		c.a = clampf(2.0 * (1.0 - s.t / s.life), 0.0, 1.0)
		draw_rect(Rect2((s.pos * 0.5).round() * 2.0, Vector2(2, 2)), c)
