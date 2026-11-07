class_name PopupLayer
extends Node2D
## Floating numbers and short labels in screen pixels, drawn in one _draw with the outlined number
## font (integer sizes 24/36/48 only — no blurry scaling). Readability rules (reference criticism:
## numbers merge into mush):
##  - rapid hits on one enemy merge into one rising number (merge window from the number's birth);
##  - lens damage shows one number per lens, DoT one per enemy (moat/puddles only);
##  - every new number is pushed up / aside until it overlaps no live number;
##  - at most `popup.max` on screen; when crowded, plain hits fold into a nearby number of the same
##    type and tiny ones are skipped — crits, loot and labels always win;
##  - numbers stay fully opaque and vanish with a short fade (no grey half-transparent ghosts);
##  - colour = damage type (legend: "?" in the resource bar), crit = bigger + "!".
## Loot: fractions are accumulated per resource and popped as whole numbers.

class Pop:
	var text: String = ""
	var pos: Vector2 = Vector2.ZERO
	var color: Color = Color.WHITE
	var size: int = 24
	var age: float = 0.0
	var life: float = 0.85
	var uid: int = -1
	var kind: String = ""
	var amount: float = 0.0
	var pop_t: float = 9.0
	var width: float = 0.0
	var icon: Texture2D = null
	var prio: int = 0
	var rise: float = 22.0
	var crit: bool = false
	var span: float = 0.0          ## time since creation (merging stops after the merge window)
	var plate: bool = false        ## label on a dark backing plate

var kit: ViewKit
var draw_ms: float = 0.0          ## last _draw cost (perf readout)
var pops: Array[Pop] = []
var _font: FontFile
var _max: int = 24
var _loot_acc: Dictionary = {}    ## res -> fraction not yet shown


func setup(view_kit: ViewKit) -> void:
	kit = view_kit
	_font = ViewKit.FONT_NUMBER
	_max = int(kit.f("popup.max", 24))


func _measure(p: Pop) -> void:
	var w: float = _font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size).x
	if p.icon != null:
		w += p.icon.get_width() * 2.0 + 4.0
	p.width = w


func _cur_y(p: Pop) -> float:
	var k: float = minf(p.age / kit.f("popup.rise_time", 0.6), 1.0)
	return p.pos.y - p.rise * (1.0 - (1.0 - k) * (1.0 - k))


func _find(uid: int, kind: String, win: float) -> Pop:
	for p: Pop in pops:
		if p.uid == uid and p.kind == kind and p.span < win:
			return p
	return null


func _crowded() -> bool:
	return pops.size() >= int(_max * kit.f("popup.crowd", 0.6))


## Moves `pos` up / aside until a box of width `w` overlaps no live popup (current positions).
func _place(pos: Vector2, w: float, h: float) -> Vector2:
	var dy: float = kit.f("popup.stack_dy", 20.0)
	var dx: float = kit.f("popup.stack_dx", 26.0)
	var cands: Array[Vector2] = [pos]
	for i in range(1, 5):
		cands.append(pos + Vector2(0, -dy * i))
	for i in range(1, 4):
		cands.append(pos + Vector2(dx * i + w * 0.3, -dy * 0.5))
		cands.append(pos + Vector2(-dx * i - w * 0.3, -dy * 0.5))
	var best: Vector2 = pos
	var best_hits: int = 1 << 20
	var right: float = 1280.0 - kit.f("panel_width", 380) - 6.0
	for c in cands:
		if c.y < _min_y or c.x - w * 0.5 < 6.0 or c.x + w * 0.5 > right:
			continue   # never place where clamping would push it back onto another number
		var hits: int = 0
		for o: Pop in pops:
			var oy: float = _cur_y(o)
			if absf(o.pos.x - c.x) < (o.width + w) * 0.5 + 4.0 and absf(oy - c.y) < (float(o.size) + h) * 0.5 + 2.0:
				hits += 1
		if hits == 0:
			return c
		if hits < best_hits:
			best_hits = hits
			best = c
	return best


## Keeps a popup fully inside the field (not under the resource bar / panel).
func _clamp(p: Pop) -> void:
	var half: float = p.width * 0.5
	var right: float = 1280.0 - kit.f("panel_width", 380) - 6.0
	p.pos.x = clampf(p.pos.x, half + 6.0, right - half)
	p.pos.y = maxf(p.pos.y, kit.f("bar_height", 40) + 30.0 + p.rise + float(p.size))


var _min_y: float = 0.0


func _add(p: Pop, place: bool = true) -> bool:
	if pops.size() >= _max:
		if p.prio == 0:
			return false
		var victim: int = -1
		for i in pops.size():
			if pops[i].prio < p.prio and (victim < 0 or pops[i].prio < pops[victim].prio
					or (pops[i].prio == pops[victim].prio and pops[i].age > pops[victim].age)):
				victim = i
		if victim < 0:
			return false
		pops.remove_at(victim)
	_measure(p)
	_clamp(p)
	if place:
		_min_y = kit.f("bar_height", 40) + 30.0 + p.rise + float(p.size)
		p.pos = _place(p.pos, p.width, float(p.size))
	pops.append(p)
	return true


## Shown value: whole numbers from 1 up (no "0.8" confetti).
static func _shown(x: float) -> float:
	return roundf(x) if x >= 1.0 else x


## Damage number for enemy `uid` (merged with recent hits of the same type).
## `window` > 0 overrides the merge window (damage over time merges longer).
func damage(uid: int, pos: Vector2, amount: float, dmg_type: String, crit: bool, window: float = -1.0) -> void:
	if amount <= 0.0:
		return
	var kind: String = ("crit:" if crit else "dmg:") + dmg_type
	var win: float = window if window > 0.0 else kit.f("popup.merge_window", 0.4)
	if _crowded():
		win *= kit.f("popup.crowd_merge_k", 2.0)
	var ex: Pop = _find(uid, kind, win)
	if ex == null and not crit and _crowded():
		# crowded: fold into the nearest young number of the same type, or skip tiny hits
		var r: float = kit.f("popup.crowd_merge_px", 110.0)
		var best_d: float = r * r
		for o: Pop in pops:
			if o.kind == kind and o.span < win * 2.0 and o.pos.distance_squared_to(pos) < best_d:
				best_d = o.pos.distance_squared_to(pos)
				ex = o
		if ex == null and amount < kit.f("popup.crowd_min_amount", 2.0):
			return
	if ex != null:
		ex.amount += amount
		ex.text = Fmt.num(_shown(ex.amount)) + ("!" if ex.crit else "")
		ex.age = minf(ex.age, 0.12)
		ex.pop_t = 0.0
		_measure(ex)
		return
	var p := Pop.new()
	p.uid = uid
	p.kind = kind
	p.amount = amount
	p.crit = crit
	p.color = kit.num_color(dmg_type)
	p.text = Fmt.num(_shown(amount)) + ("!" if crit else "")
	p.size = int(kit.f("popup.font_size", 24))
	if crit:
		var n_crit: int = 0
		for o: Pop in pops:
			if o.crit and o.size > p.size:
				n_crit += 1
		if n_crit < int(kit.f("popup.max_big_crits", 5)):
			p.size = int(kit.f("popup.crit_size", 36))
	p.life = kit.f("popup.crit_life", 1.1) if crit else kit.f("popup.life", 0.85)
	p.rise = kit.f("popup.rise", 22.0) * (1.4 if crit else 1.0)
	p.prio = 1 if crit else 0
	p.pop_t = 0.0
	p.pos = pos + Vector2(randf_range(-4.0, 4.0), -10.0)
	_add(p)


## Loot at the kill spot: "+12" with a gear coin, "+5" blueprints. Fractions accumulate.
func loot(pos: Vector2, loot_dict: Dictionary) -> void:
	var y: float = 0.0
	for r: String in loot_dict:
		var acc: float = float(_loot_acc.get(r, 0.0)) + float(loot_dict[r])
		var amt: float = floorf(acc)
		_loot_acc[r] = acc - amt
		if amt < 1.0:
			continue
		var kind: String = "loot:" + r
		var ex: Pop = null
		var rad: float = kit.f("popup.crowd_merge_px", 110.0) if _crowded() else 60.0
		for o: Pop in pops:
			if o.kind == kind and o.span < (0.6 if _crowded() else 0.3) and o.pos.distance_squared_to(pos) < rad * rad:
				ex = o
				break
		if ex != null:
			ex.amount += amt
			ex.text = "+" + Fmt.num(ex.amount)
			ex.age = minf(ex.age, 0.1)
			ex.pop_t = 0.0
			_measure(ex)
			continue
		var p := Pop.new()
		p.kind = kind
		p.amount = amt
		p.text = "+" + Fmt.num(amt)
		p.color = kit.num_color(r)
		p.size = 24
		p.life = 1.0
		p.rise = 26.0
		p.prio = 1
		if r == "gears":
			p.icon = SpriteLib.texture("gear_coin")
		p.pos = pos + Vector2(20.0, -30.0 + y)
		y += 22.0
		_add(p)


## A short label (milestone name, "буль!", "Урон 10 → 13"...). `plate` draws a dark backing.
func text(pos: Vector2, t: String, color: Color, size: int = 24, life: float = 1.4, rise: float = 26.0,
		plate: bool = false) -> void:
	var p := Pop.new()
	p.kind = "label"
	p.text = t
	p.color = color
	p.size = size
	p.life = life
	p.rise = rise
	p.prio = 2
	p.pop_t = 0.0
	p.plate = plate
	p.pos = pos
	_add(p)


func _process(delta: float) -> void:
	var i: int = pops.size() - 1
	while i >= 0:
		var p: Pop = pops[i]
		p.age += delta
		p.span += delta
		p.pop_t += delta
		if p.age >= p.life:
			pops.remove_at(i)
		i -= 1
	queue_redraw()


func _draw() -> void:
	var t0: int = Time.get_ticks_usec()
	var fade: float = kit.f("popup.fade", 0.12)
	var pop_time: float = kit.f("popup.crit_pop_time", 0.08)
	var pop_size: int = int(kit.f("popup.crit_pop_size", 48))
	var plate_bg: Color = Color(kit.col("soot_0"), 0.85)
	var plate_edge: Color = kit.col("brass_1")
	for p: Pop in pops:
		var y: float = _cur_y(p)
		var a: float = clampf((p.life - p.age) / fade, 0.0, 1.0)
		var size: int = p.size
		if p.crit and p.pop_t < pop_time:
			size = pop_size if p.size > 24 else int(kit.f("popup.crit_size", 36))
		elif p.pop_t < 0.06:
			y -= 2.0
		var col: Color = p.color
		col.a = a
		var w: float = p.width if size == p.size else _font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var x: float = p.pos.x - w * 0.5
		if p.plate:
			var r := Rect2(roundf((x - 8.0) * 0.5) * 2.0, roundf((y - float(size) - 2.0) * 0.5) * 2.0,
				roundf((w + 16.0) * 0.5) * 2.0, float(size) + 10.0)
			draw_rect(r, Color(plate_bg, plate_bg.a * a))
			draw_rect(r, Color(plate_edge, a), false, 2.0)
		if p.icon != null:
			var isz: Vector2 = Vector2(p.icon.get_width(), p.icon.get_height()) * 2.0
			draw_texture_rect(p.icon, Rect2(Vector2(roundf(x * 0.5) * 2.0, roundf((y - isz.y + 2.0) * 0.5) * 2.0), isz), false,
				Color(1, 1, 1, a))
			x += isz.x + 4.0
		draw_string(_font, Vector2(roundf(x * 0.5) * 2.0, roundf(y * 0.5) * 2.0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_ms = (Time.get_ticks_usec() - t0) / 1000.0
