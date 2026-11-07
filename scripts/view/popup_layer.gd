class_name PopupLayer
extends Node2D
## Floating numbers and short labels in screen pixels, drawn in one _draw with
## the outlined number font (integer sizes 24/36/48 only — no blurry scaling).
## Readability rules (reference criticism: numbers merge into mush):
##  - rapid hits on one enemy merge into one rising number (merge window);
##  - lens damage shows one number per lens, DoT one per enemy;
##  - new numbers are pushed up/aside if they would overlap a young one;
##  - at most `popup.max` on screen, crits/loot/labels win over plain hits;
##  - colour = damage type (legend in the enemy tooltip), crit = bigger + "!".

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
	var span: float = 0.0          ## time since creation (merging stops after merge_window)

var kit: ViewKit
var draw_ms: float = 0.0          ## last _draw cost (perf readout)
var pops: Array[Pop] = []
var _font: FontFile
var _max: int = 30


func setup(view_kit: ViewKit) -> void:
	kit = view_kit
	_font = ViewKit.FONT_NUMBER
	_max = int(kit.f("popup.max", 30))


func _measure(p: Pop) -> void:
	var w: float = _font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size).x
	if p.icon != null:
		w += p.icon.get_width() * 2.0 + 4.0
	p.width = w


func _find(uid: int, kind: String, win: float) -> Pop:
	for p: Pop in pops:
		if p.uid == uid and p.kind == kind and p.span < win:
			return p
	return null


## Moves `pos` up/aside until it does not overlap a young popup.
func _place(pos: Vector2) -> Vector2:
	var gx: float = kit.f("popup.min_gap_x", 34.0)
	var gy: float = kit.f("popup.min_gap_y", 22.0)
	var dy: float = kit.f("popup.stack_dy", 20.0)
	var dx: float = kit.f("popup.stack_dx", 26.0)
	var p: Vector2 = pos
	for attempt in 6:
		var hit: bool = false
		for o: Pop in pops:
			if o.age > 0.35:
				continue
			var op: Vector2 = o.pos + Vector2(0, -o.rise * minf(o.age / 0.6, 1.0))
			if absf(op.x - p.x) < gx and absf(op.y - p.y) < gy:
				hit = true
				break
		if not hit:
			return p
		if attempt < 3:
			p.y -= dy
		else:
			p = pos + Vector2(dx * (1.0 if attempt % 2 == 1 else -1.0) * float(attempt - 2), -dy * 0.5)
	return p


## Keeps a popup fully inside the field (not under the resource bar / panel).
func _clamp(p: Pop) -> void:
	var half: float = p.width * 0.5
	var right: float = 1280.0 - kit.f("panel_width", 380) - 6.0
	p.pos.x = clampf(p.pos.x, half + 6.0, right - half)
	p.pos.y = maxf(p.pos.y, kit.f("bar_height", 40) + 30.0 + p.rise + float(p.size))


func _add(p: Pop) -> bool:
	if pops.size() >= _max:
		# make room: drop the oldest plain hit; plain hits never evict others
		if p.prio == 0:
			return false
		var victim: int = -1
		for i in pops.size():
			if pops[i].prio == 0 and (victim < 0 or pops[i].age > pops[victim].age):
				victim = i
		if victim < 0:
			return false
		pops.remove_at(victim)
	_measure(p)
	_clamp(p)
	pops.append(p)
	return true


## Shown value: whole numbers from 1 up (no "0.8" confetti), Fmt.num for big ones.
static func _shown(x: float) -> float:
	return roundf(x) if x >= 1.0 else x


## Damage number for enemy `uid` (merged with recent hits of the same type).
## `window` > 0 overrides the merge window (damage over time merges longer).
func damage(uid: int, pos: Vector2, amount: float, dmg_type: String, crit: bool, window: float = -1.0) -> void:
	if amount <= 0.0:
		return
	var kind: String = ("crit:" if crit else "dmg:") + dmg_type
	var ex: Pop = _find(uid, kind, window if window > 0.0 else kit.f("popup.merge_window", 0.4))
	if ex == null and not crit and pops.size() >= _max:
		# over the cap: fold into the nearest number of the same kind
		var best_d: float = 80.0 * 80.0
		for o: Pop in pops:
			if o.kind == kind and o.pos.distance_squared_to(pos) < best_d:
				best_d = o.pos.distance_squared_to(pos)
				ex = o
		if ex == null:
			return
	if ex != null:
		ex.amount += amount
		ex.text = Fmt.num(_shown(ex.amount)) + ("!" if crit else "")
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
		# crits are big and pop — unless a crit storm is already on screen
		var n_crit: int = 0
		for o: Pop in pops:
			if o.crit:
				n_crit += 1
		if n_crit < int(kit.f("popup.max_big_crits", 6)):
			p.size = int(kit.f("popup.crit_size", 36))
	p.life = kit.f("popup.crit_life", 1.1) if crit else kit.f("popup.life", 0.85)
	p.rise = kit.f("popup.rise", 22.0) * (1.4 if crit else 1.0)
	p.prio = 1 if crit else 0
	p.pop_t = 0.0
	p.pos = _place(pos + Vector2(randf_range(-6.0, 6.0), -10.0))
	_add(p)


## Loot at the kill spot: "+12" with a gear coin, "+5" blueprints below.
func loot(pos: Vector2, loot_dict: Dictionary) -> void:
	var y: float = 0.0
	for r: String in loot_dict:
		var amt: float = float(loot_dict[r])
		if amt <= 0.0:
			continue
		var kind: String = "loot:" + r
		# merge with a nearby fresh loot popup of the same resource
		var ex: Pop = null
		for o: Pop in pops:
			if o.kind == kind and o.age < 0.3 and o.pos.distance_squared_to(pos) < 50.0 * 50.0:
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
		p.pos = _place(pos + Vector2(20.0, -30.0 + y))
		y += 22.0
		_add(p)


## A short label (milestone name, "буль!", "+40% урон"...).
func text(pos: Vector2, t: String, color: Color, size: int = 24, life: float = 1.4, rise: float = 26.0) -> void:
	var p := Pop.new()
	p.kind = "label"
	p.text = t
	p.color = color
	p.size = size
	p.life = life
	p.rise = rise
	p.prio = 2
	p.pop_t = 0.0
	p.pos = _place(pos)
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
	var _pt0: int = Time.get_ticks_usec()
	_draw_body()
	draw_ms = (Time.get_ticks_usec() - _pt0) / 1000.0


func _draw_body() -> void:
	var fade: float = kit.f("popup.fade", 0.3)
	var rise_t: float = kit.f("popup.rise_time", 0.6)
	var pop_time: float = kit.f("popup.crit_pop_time", 0.08)
	var pop_size: int = int(kit.f("popup.crit_pop_size", 48))
	for p: Pop in pops:
		var k: float = minf(p.age / rise_t, 1.0)
		var ease_k: float = 1.0 - (1.0 - k) * (1.0 - k)
		var y: float = p.pos.y - p.rise * ease_k
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
		if p.icon != null:
			var isz: Vector2 = Vector2(p.icon.get_width(), p.icon.get_height()) * 2.0
			draw_texture_rect(p.icon, Rect2(Vector2(roundf(x * 0.5) * 2.0, roundf((y - isz.y + 2.0) * 0.5) * 2.0), isz), false,
				Color(1, 1, 1, a))
			x += isz.x + 4.0
		draw_string(_font, Vector2(roundf(x * 0.5) * 2.0, roundf(y * 0.5) * 2.0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
