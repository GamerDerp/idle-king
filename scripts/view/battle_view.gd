class_name BattleView
extends Node2D
## The battlefield in art pixels (this node is scaled ×2 and offset under the
## resource bar). Static scenery from the manifest, the wall with towers in
## visual slots, the King, chimney smoke, the boiling moat with its steam
## curtain, and one pooled AnimatedSprite2D per enemy (y-sorted, shadows,
## hit flash, knockback wobble). Transient effects live in FxLayer (above
## units) and DecalLayer (below units). Reads the core every frame; never
## changes it. See docs/VIEW.md.

class EnemyView:
	var uid: int = 0
	var type: String = ""
	var node: AnimatedSprite2D
	var shadow: AnimatedSprite2D
	var flash_t: float = 0.0
	var last_flash: float = -1.0
	var wobble_t: float = 0.0
	var new_t: float = 0.0
	var stamp: int = 0
	var art_pos: Vector2 = Vector2.ZERO


class TowerView:
	var key: String = ""
	var type: String = ""
	var tier: int = 1
	var node: AnimatedSprite2D
	var feet: Vector2 = Vector2.ZERO
	var core_pos: Vector2 = Vector2.ZERO
	var fire_t: float = 0.0
	var drop_t: float = 0.0
	var flash_t: float = 0.0
	var smoke_at: float = -9.0
	var stamp: int = 0

var kit: ViewKit
var core: GameCore
var fx: FxLayer
var decals: DecalLayer
var king: AnimatedSprite2D
var lay: Dictionary = {}
var enemies: Dictionary = {}        ## uid -> EnemyView
var towers: Dictionary = {}         ## "type#index" -> TowerView
var tower_by_core_pos: Dictionary = {}   ## Vector2i(core slot pos) -> TowerView
var seen_enemy_types: Dictionary = {}  ## type -> game time until which spawns get the "new!" marker
var shake_cb: Callable

var _wall: Node2D
var _units: Node2D
var _pool: Array[EnemyView] = []
var _stamp: int = 0
var _time: float = 0.0
var _king_timer: float = 0.0
var _king_next: float = 8.0
var _king_tea: bool = false
var _slot_used: Dictionary = {}
var _ready_done: bool = false
var _curtain_t: float = 0.0
var _bank_x: float = 138.0
var _bg: Sprite2D
var _bg_name: String = ""
var _curtain: AnimatedSprite2D
var _furnaces: Array[AnimatedSprite2D] = []
var _region_t: float = 0.0


func setup(view_kit: ViewKit) -> void:
	kit = view_kit
	core = kit.core
	lay = SpriteLib.layout()
	scale = Vector2(kit.art_scale, kit.art_scale)
	position = kit.origin
	_bank_x = float((lay.get("bank_x", [138, 145]) as Array)[0])
	_build_scenery()
	for t: String in core.mods.unlocked_enemies:
		seen_enemy_types[t] = -1.0
	for e: Battle.Enemy in core.battle.enemies:
		seen_enemy_types[e.type] = -1.0
	sync_towers()
	_ready_done = true


func _arr2(key: String) -> Vector2:
	var a: Array = lay.get(key, [0, 0])
	return Vector2(float(a[0]), float(a[1]))


func _build_scenery() -> void:
	# layer order (docs/ART.md): bg → water → pipes → furnaces → wall (towers, King) → steam curtain
	# → decals → units → fx → wisps
	_bg = Sprite2D.new()
	_bg.centered = false
	add_child(_bg)
	_update_region()
	var moat_x: Array = lay.get("moat_x", [108, 137])
	var size: Array = lay.get("size", [450, 340])
	var tile_h: int = SpriteLib.frame_size("moat_water").y
	for y in range(0, int(size[1]), tile_h):
		var w := SpriteLib.make("moat_water", (y / tile_h) % 4)
		w.position = Vector2(float(moat_x[0]), float(y))
		add_child(w)
	var vents: Array = lay.get("steam_vents_y", [])
	var pipe_x: float = float(lay.get("pipe_x", 101))
	var gate_y: float = float(lay.get("gate_y", 196))
	for i in range(vents.size()):
		var vy: float = float(vents[i])
		if absf(vy - gate_y) < 30.0:
			continue
		var pipe := SpriteLib.make("steam_pipe_valve" if i % 4 == 1 else "steam_pipe")
		pipe.position = Vector2(pipe_x, vy)
		add_child(pipe)
	var face: Array = lay.get("face_x", [96, 107])
	for fy: Variant in lay.get("furnace_y", []):
		var fu := SpriteLib.make("moat_furnace_off")
		fu.position = Vector2(float(face[0]), float(fy))
		fu.visible = false
		add_child(fu)
		_furnaces.append(fu)
	_wall = Node2D.new()
	_wall.name = "Wall"
	_wall.y_sort_enabled = true
	add_child(_wall)
	king = SpriteLib.make("king_idle")
	king.position = _arr2("king_pos")
	_wall.add_child(king)
	king.animation_finished.connect(_on_king_anim_done)
	var k: int = 0
	for p: Array in lay.get("smoke_points", []):
		var sm := SpriteLib.make("chimney_smoke", k % 4)
		sm.position = Vector2(float(p[0]), float(p[1]))
		add_child(sm)
		k += 1
	# the whole steam curtain (plumes + shadow on the water) is one sprite
	_curtain = SpriteLib.make("steam_curtain")
	_curtain.position = Vector2(float(lay.get("steam_curtain_x", 112)), 0.0)
	add_child(_curtain)
	decals = DecalLayer.new()
	decals.name = "Decals"
	add_child(decals)
	decals.setup(kit, self)
	_units = Node2D.new()
	_units.name = "Units"
	_units.y_sort_enabled = true
	add_child(_units)
	fx = FxLayer.new()
	fx.name = "Fx"
	add_child(fx)
	fx.setup(kit, self)
	# loose wisps drifting over the east bank, above everything on the field
	var n_wisps: int = int(kit.f("moat.wisps", 7))
	for i in range(n_wisps):
		var wsp := SpriteLib.make("steam_wisps", (i * 3) % 8)
		wsp.position = Vector2(_bank_x - 8.0, 30.0 + i * (float(size[1]) - 40.0) / n_wisps + float((i * 13) % 17))
		add_child(wsp)


## Battlefield background of the newest unlocked region (manifest.regions), furnace doors.
func _update_region() -> void:
	var regs: Dictionary = SpriteLib.manifest().get("regions", {})
	var best: int = -1
	for r: int in core.mods.regions:
		if regs.has(str(r)) and r > best:
			best = r
	var bg_name: String = str((regs.get(str(best), {}) as Dictionary).get("bg", "battlefield_bg")) if best >= 0 else "battlefield_bg"
	if bg_name != _bg_name:
		_bg_name = bg_name
		_bg.texture = SpriteLib.texture(bg_name)
	var base_w: float = float(core.data.waves["curtain_width"])
	var state: String = ""
	if core.mods.is_region_unlocked(2):
		state = "moat_furnace_hot" if core.mods.moat_width > base_w else "moat_furnace_off"
	for fu: AnimatedSprite2D in _furnaces:
		fu.visible = state != ""
		if state != "" and fu.sprite_frames != SpriteLib.sprite_frames(state):
			fu.sprite_frames = SpriteLib.sprite_frames(state)
			fu.play(&"default")


# --- towers ----------------------------------------------------------------------

## Creates / updates tower sprites from battle.towers (new ones drop in).
func sync_towers() -> void:
	_stamp += 1
	tower_by_core_pos.clear()
	for tw: Battle.Tower in core.battle.towers:
		var key: String = "%s#%d" % [tw.type, tw.index]
		var tv: TowerView = towers.get(key, null)
		if tv == null:
			tv = _make_tower(tw, key)
		tv.stamp = _stamp
		tv.core_pos = tw.pos
		tower_by_core_pos[Vector2i(tw.pos.round())] = tv
		var tier: int = core.tower_tier(tw.type)
		if tier != tv.tier:
			tv.tier = tier
			tv.node.sprite_frames = SpriteLib.sprite_frames(kit.tower_sprite(tw.type, tier))
			tv.node.frame = 0
			tv.flash_t = 0.12
			fx.tier_ring(tv.feet + Vector2(0, -16))
	var gone: Array = []
	for key: String in towers:
		if (towers[key] as TowerView).stamp != _stamp:
			gone.append(key)
	for key: String in gone:
		var tv: TowerView = towers[key]
		tv.node.queue_free()
		towers.erase(key)
	_slot_used.clear()
	for key: String in towers:
		_slot_used[_slot_id((towers[key] as TowerView).feet)] = true


func _slot_id(p: Vector2) -> String:
	return "%d,%d" % [int(p.x), int(p.y)]


func _make_tower(tw: Battle.Tower, key: String) -> TowerView:
	var tv := TowerView.new()
	tv.key = key
	tv.type = tw.type
	tv.tier = core.tower_tier(tw.type)
	tv.feet = _free_visual_slot(tw)
	_slot_used[_slot_id(tv.feet)] = true
	tv.node = SpriteLib.make(kit.tower_sprite(tw.type, tv.tier))
	tv.node.position = tv.feet
	var sh := SpriteLib.make("shadow_l")
	sh.position = Vector2(2, -2)
	sh.show_behind_parent = true
	tv.node.add_child(sh)
	_wall.add_child(tv.node)
	towers[key] = tv
	if _ready_done:
		tv.drop_t = kit.f("tower_drop.time", 0.22)
		tv.node.position = tv.feet + Vector2(0, -kit.f("tower_drop.height", 14))
	return tv


func _free_visual_slot(tw: Battle.Tower) -> Vector2:
	var row: int = 0
	if tw.slot >= 0 and tw.slot < core.data.wall_slot_row.size():
		row = core.data.wall_slot_row[tw.slot]
	var col_name: String = str((kit.v("wall.row_column", {}) as Dictionary).get(str(row), "front"))
	var cols: Dictionary = kit.v("wall.columns", {})
	var order: Array[String] = [col_name]
	for c: Variant in kit.v("wall.order", ["front", "mid", "back"]):
		if not order.has(str(c)):
			order.append(str(c))
	for c: String in order:
		var cd: Dictionary = cols.get(c, {})
		for y: Variant in cd.get("ys", []):
			var p := Vector2(float(cd.get("x", 80)), float(y))
			if not _slot_used.has(_slot_id(p)):
				return p
	# wall completely full: stack slightly behind the core position
	return kit.to_art(tw.pos).round() + Vector2(-6, 3)


func tower_view(tower_type: String, index: int) -> TowerView:
	return towers.get("%s#%d" % [tower_type, index], null)


func muzzle_of(tv: TowerView) -> Vector2:
	return tv.feet + kit.muzzle(tv.type, tv.tier)


## Visual muzzle (art) for a projectile that started at core position `start`.
func muzzle_for_start(start: Vector2) -> Vector2:
	var tv: TowerView = tower_by_core_pos.get(Vector2i(start.round()), null)
	if tv == null:
		return kit.to_art(start)
	return muzzle_of(tv)


func on_tower_fired(tower_type: String, index: int) -> void:
	var tv: TowerView = tower_view(tower_type, index)
	if tv == null:
		return
	tv.fire_t = kit.f("tower_fire.fire", 0.07) + kit.f("tower_fire.recover", 0.1)
	tv.node.frame = 1
	# muzzle smoke at most every smoke_every s per tower (fast guns would fill the anim budget)
	if _time - tv.smoke_at >= kit.f("tower_fire.smoke_every", 0.3):
		tv.smoke_at = _time
		fx.anim("muzzle_smoke", muzzle_of(tv))


func towers_of(tower_type: String) -> Array[TowerView]:
	var out: Array[TowerView] = []
	for key: String in towers:
		var tv: TowerView = towers[key]
		if tv.type == tower_type:
			out.append(tv)
	return out


func _update_towers(delta: float) -> void:
	for key: String in towers:
		var tv: TowerView = towers[key]
		var pos: Vector2 = tv.feet
		if tv.drop_t > 0.0:
			tv.drop_t -= delta
			var total: float = kit.f("tower_drop.time", 0.22)
			var k: float = clampf(1.0 - tv.drop_t / total, 0.0, 1.0)
			pos = tv.feet + Vector2(0, -kit.f("tower_drop.height", 14) * (1.0 - k * k))
			if tv.drop_t <= 0.0:
				pos = tv.feet
				tv.flash_t = 0.05
				fx.steam_burst(tv.feet + Vector2(0, -4), 5)
				if shake_cb.is_valid():
					shake_cb.call(kit.f("shake.tower_drop", 2.5))
		if tv.fire_t > 0.0:
			# frame 1 (shot, recoil) → frame 2 (recover, smoke) → frame 0
			tv.fire_t -= delta
			var frames: int = tv.node.sprite_frames.get_frame_count(&"default")
			if tv.fire_t <= 0.0:
				tv.node.frame = 0
			elif tv.fire_t < kit.f("tower_fire.recover", 0.1) and frames > 2:
				tv.node.frame = 2
		if tv.flash_t > 0.0:
			tv.flash_t -= delta
			tv.node.material = kit.flash_mat
			if tv.flash_t <= 0.0:
				tv.node.material = null
		tv.node.position = pos.round()


# --- enemies ---------------------------------------------------------------------

func _acquire(e: Battle.Enemy) -> EnemyView:
	var ev: EnemyView
	if _pool.is_empty():
		ev = EnemyView.new()
		ev.node = AnimatedSprite2D.new()
		ev.node.centered = false
		ev.node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ev.shadow = AnimatedSprite2D.new()
		ev.shadow.centered = false
		ev.shadow.show_behind_parent = true
		ev.shadow.position = Vector2(1, 0)
		ev.node.add_child(ev.shadow)
		_units.add_child(ev.node)
	else:
		ev = _pool.pop_back()
		ev.node.visible = true
	var sp: Dictionary = kit.enemy_sprites(e.type)
	var walk: String = str(sp.get("walk", "scavenger_walk"))
	var shadow_name: String = str(sp.get("shadow", "shadow_s"))
	ev.node.sprite_frames = SpriteLib.sprite_frames(walk)
	ev.node.offset = -SpriteLib.anchor(walk)
	ev.node.play(&"default")
	ev.node.frame = e.uid % 4
	ev.node.material = null
	ev.node.speed_scale = 1.0
	ev.node.modulate = Color.WHITE
	ev.shadow.sprite_frames = SpriteLib.sprite_frames(shadow_name)
	ev.shadow.offset = -SpriteLib.anchor(shadow_name)
	ev.uid = e.uid
	ev.type = e.type
	ev.flash_t = 0.0
	ev.last_flash = -1.0
	ev.wobble_t = 0.0
	ev.new_t = 0.0
	if not seen_enemy_types.has(e.type) or float(seen_enemy_types[e.type]) > _time:
		# first pack of a new type: everyone in it gets the "new!" marker
		if not seen_enemy_types.has(e.type):
			seen_enemy_types[e.type] = _time + 3.0
		ev.new_t = kit.f("new_marker_time", 4.0)
	enemies[e.uid] = ev
	return ev


func _release(ev: EnemyView) -> void:
	enemies.erase(ev.uid)
	ev.node.visible = false
	ev.node.material = null
	ev.node.stop()
	_pool.append(ev)


func _update_enemies(delta: float) -> void:
	_stamp += 1
	for e: Battle.Enemy in core.battle.enemies:
		if not e.alive:
			continue
		var ev: EnemyView = enemies.get(e.uid, null)
		if ev == null:
			ev = _acquire(e)
		ev.stamp = _stamp
		var ap: Vector2 = kit.to_art(e.pos).round()
		if ev.wobble_t > 0.0:
			ev.wobble_t -= delta
			ap.x += kit.f("wobble.px", 1)
		ev.art_pos = ap
		ev.node.position = ap
		ev.node.visible = not e.underground
		ev.node.speed_scale = 1.0 - (e.slow_f if e.slow_t > 0.0 else 0.0)
		if ev.new_t > 0.0:
			ev.new_t -= delta
		if ev.flash_t > 0.0:
			ev.flash_t -= delta
			if ev.flash_t <= 0.0:
				ev.node.material = null
	var gone: Array[EnemyView] = []
	for uid: int in enemies:
		var ev: EnemyView = enemies[uid]
		if ev.stamp != _stamp:
			gone.append(ev)
	for ev in gone:
		_release(ev)


func flash_enemy(uid: int, crit: bool) -> void:
	var ev: EnemyView = enemies.get(uid, null)
	if ev == null:
		return
	var is_boss: bool = core.battle.boss_enemy != null and core.battle.boss_enemy.uid == uid
	if not is_boss:
		ev.wobble_t = kit.f("wobble.time", 0.08)
	# bosses get hit by everything: a rare short white blink instead of a permanent orange blob
	var gap: float = kit.f("flash.boss_interval", 0.6) if is_boss else kit.f("flash.min_interval", 0.1)
	if _time - ev.last_flash < gap and not (crit and not is_boss):
		return
	ev.last_flash = _time
	ev.flash_t = kit.f("flash.boss_time", 0.05) if is_boss else kit.f("flash.time", 0.07)
	ev.node.material = kit.crit_flash_mat if crit and not is_boss else kit.flash_mat


func enemy_view(uid: int) -> EnemyView:
	return enemies.get(uid, null)


## Enemy under a screen point (for tooltips), or null.
func enemy_at(screen_pos: Vector2, pad: float = 8.0) -> Battle.Enemy:
	var best: Battle.Enemy = null
	var best_d: float = INF
	for e: Battle.Enemy in core.battle.enemies:
		if not e.alive:
			continue
		var c: Vector2 = e.pos + Vector2(0, -e.radius)   # sprites stand on their feet
		var d: float = c.distance_squared_to(screen_pos)
		var r: float = e.radius + pad
		if d <= r * r and d < best_d:
			best_d = d
			best = e
	return best


# --- King, curtain -------------------------------------------------------------------

func king_tea() -> void:
	if _king_tea:
		return
	_king_tea = true
	king.sprite_frames = SpriteLib.sprite_frames("king_tea")
	king.play(&"default")


func _on_king_anim_done() -> void:
	_king_tea = false
	king.sprite_frames = SpriteLib.sprite_frames("king_idle")
	king.play(&"default")


func king_pos() -> Vector2:
	return king.position


func _update_king(delta: float) -> void:
	_king_timer += delta
	if _king_timer >= _king_next:
		_king_timer = 0.0
		var r: Array = kit.v("king_tea_every", [6.0, 11.0])
		_king_next = randf_range(float(r[0]), float(r[1]))
		king_tea()


func _update_curtain(delta: float) -> void:
	if core.mods.moat_dps <= 0.0:
		return
	_curtain_t -= delta
	if _curtain_t > 0.0:
		return
	# hotter curtain = more puffs rising along the near bank
	var heat: float = clampf(core.mods.moat_dps / 30.0, 0.5, 3.0)
	_curtain_t = kit.f("moat.curtain_puff_every", 0.35) / heat
	var size: Array = lay.get("size", [450, 340])
	var y: float = randf_range(6.0, float(size[1]) - 6.0)
	var w: float = core.mods.moat_width / kit.art_scale
	fx.curtain_puff(Vector2(_bank_x + randf_range(0.0, maxf(4.0, w * 0.5)), y))


func bank_x() -> float:
	return _bank_x


func update_view(delta: float) -> void:
	_time += delta
	sync_towers()
	_update_towers(delta)
	_update_enemies(delta)
	_update_king(delta)
	_update_curtain(delta)
	_region_t -= delta
	if _region_t <= 0.0:
		_region_t = 0.5
		_update_region()
	fx.queue_redraw()
	decals.queue_redraw()


func enemy_by_uid(uid: int) -> Battle.Enemy:
	for e: Battle.Enemy in core.battle.enemies:
		if e.uid == uid and e.alive:
			return e
	return null
