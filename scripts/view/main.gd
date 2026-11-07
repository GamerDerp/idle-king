extends Control
## Placeholder main screen: proves config, palette, i18n, Fmt and sprites work.

@onready var _bg: ColorRect = $Background
@onready var _title: Label = $Center/Title
@onready var _subtitle: Label = $Center/Subtitle
@onready var _gear_holder: Control = $Center/GearHolder
@onready var _gear: Sprite2D = $Center/GearHolder/Gear
@onready var _status: Label = $Center/Status
@onready var _numbers: Label = $Center/Numbers

var _spin_speed: float = 0.0


func _ready() -> void:
	var vis: Dictionary = Config.get_cfg("visual")
	_bg.color = Config.color(str(vis.get("background_color", "soot_1")))
	_style(_title, "title", vis)
	_style(_subtitle, "subtitle", vis)
	_style(_status, "status", vis)
	_style(_numbers, "status", vis)
	_title.add_theme_color_override("font_shadow_color", Config.color(str(vis.get("title_shadow_color", "soot_0"))))
	_title.add_theme_constant_override("shadow_offset_x", 4)
	_title.add_theme_constant_override("shadow_offset_y", 4)
	_title.add_theme_color_override("font_outline_color", Config.color("brass_0"))
	_title.add_theme_constant_override("outline_size", 6)

	_title.text = tr("GAME_TITLE")
	_subtitle.text = tr("GAME_SUBTITLE")
	_status.text = tr("PLACEHOLDER_STATUS")
	var samples: Array[float] = [12.5, 1234.0, 5.6e6, 7.89e33, 5.6e35, -42000.0]
	var parts: PackedStringArray = []
	for s in samples:
		parts.append(Fmt.num(s))
	parts.append(Fmt.time(3912.0))
	_numbers.text = "  ·  ".join(parts)

	var scale_k: float = float(vis.get("sprite_preview_scale", 6))
	_gear.scale = Vector2(scale_k, scale_k)
	_gear_holder.custom_minimum_size = _gear.texture.get_size() * scale_k
	_spin_speed = float(vis.get("gear_spin_speed", 0.0))
	print("Main scene ready (locale %s)" % TranslationServer.get_locale())


func _style(label: Label, prefix: String, vis: Dictionary) -> void:
	label.add_theme_font_size_override("font_size", int(vis.get(prefix + "_font_size", 16)))
	label.add_theme_color_override("font_color", Config.color(str(vis.get(prefix + "_color", "parchment_2"))))


func _process(delta: float) -> void:
	_gear.position = _gear_holder.size / 2.0
	_gear.rotation += _spin_speed * delta
