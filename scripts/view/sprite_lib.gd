class_name SpriteLib
extends RefCounted
## Access to generated sprites via assets/sprites/manifest.json (written by tools/art/gen_art.py).
##   SpriteLib.make("scavenger_walk")      -> AnimatedSprite2D, playing, origin at the sprite's anchor
##   SpriteLib.texture("res_gears")        -> Texture2D (frame 0; AtlasTexture for strips)
##   SpriteLib.sprite_frames("explosion")  -> SpriteFrames with animation "default"
##   SpriteLib.layout()                    -> battlefield geometry in art px (see tools/art/layout.py)
## Art is 1x; the world node is scaled by SpriteLib.scale() (2).

const MANIFEST_PATH := "res://assets/sprites/manifest.json"

static var _manifest: Dictionary = {}
static var _frames_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		if f == null:
			push_error("SpriteLib: cannot open %s" % MANIFEST_PATH)
			return {}
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_manifest = parsed
		else:
			push_error("SpriteLib: bad manifest JSON")
	return _manifest


static func info(sprite_name: String) -> Dictionary:
	var sprites: Dictionary = manifest().get("sprites", {})
	if not sprites.has(sprite_name):
		push_error("SpriteLib: unknown sprite '%s'" % sprite_name)
		return {}
	return sprites[sprite_name]


static func scale() -> int:
	return int(manifest().get("scale", 2))


static func layout() -> Dictionary:
	return manifest().get("battlefield", {})


static func anchor(sprite_name: String) -> Vector2:
	var a: Array = info(sprite_name).get("anchor", [0, 0])
	return Vector2(float(a[0]), float(a[1]))


static func frame_size(sprite_name: String) -> Vector2i:
	var s: Array = info(sprite_name).get("frame_size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))


## Single frame as a texture (AtlasTexture region of the strip).
static func texture(sprite_name: String, frame: int = 0) -> Texture2D:
	var key := "%s:%d" % [sprite_name, frame]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex := _make_texture(sprite_name, frame)
	if tex != null:
		_tex_cache[key] = tex
	return tex


static func _make_texture(sprite_name: String, frame: int) -> Texture2D:
	var i := info(sprite_name)
	if i.is_empty():
		return null
	var sheet: Texture2D = load(str(i["file"]))
	if int(i.get("frames", 1)) <= 1:
		return sheet
	var fs := frame_size(sprite_name)
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(fs.x * frame, 0, fs.x, fs.y)
	return at


static func sprite_frames(sprite_name: String) -> SpriteFrames:
	if _frames_cache.has(sprite_name):
		return _frames_cache[sprite_name]
	var i := info(sprite_name)
	var sf := SpriteFrames.new()
	sf.set_animation_speed(&"default", maxf(0.001, float(i.get("fps", 0.0))))
	sf.set_animation_loop(&"default", bool(i.get("loop", true)))
	for k in range(int(i.get("frames", 1))):
		sf.add_frame(&"default", texture(sprite_name, k))
	_frames_cache[sprite_name] = sf
	return sf


## AnimatedSprite2D whose origin is the sprite's anchor (feet/pivot). Starts playing if fps > 0.
static func make(sprite_name: String, start_frame: int = 0) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = sprite_frames(sprite_name)
	s.centered = false
	s.offset = -anchor(sprite_name)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.frame = start_frame
	if float(info(sprite_name).get("fps", 0.0)) > 0.0:
		s.play(&"default")
		s.frame = start_frame
	return s
