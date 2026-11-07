extends Node
## Autoload `Config`: every config/*.json, loaded once at startup.
## Usage: Config.get_cfg("economy") -> Dictionary
##        Config.value("economy", "start.gold", 0.0)

signal reloaded

var _data: Dictionary = {}
var load_errors: Array = []


func _init() -> void:
	reload()


## Re-reads all files (e.g. for a debug hotkey). Emits `reloaded`.
func reload() -> void:
	load_errors = []
	_data = ConfigLoader.load_dir(ConfigLoader.DEFAULT_DIR, load_errors)
	if not load_errors.is_empty():
		push_error("Config: failed to load %s — fix the JSON, defaults will be used" % str(load_errors))
	reloaded.emit()


func has_cfg(cfg_name: String) -> bool:
	return _data.has(cfg_name)


## Whole config file as a Dictionary. Unknown name -> error + empty dict.
func get_cfg(cfg_name: String) -> Dictionary:
	if not _data.has(cfg_name):
		push_error("Config: unknown config '%s' (have: %s)" % [cfg_name, str(_data.keys())])
		return {}
	return _data[cfg_name]


## Nested value by dotted path, with default if missing.
func value(cfg_name: String, key_path: String, default: Variant = null) -> Variant:
	if not _data.has(cfg_name):
		return default
	return ConfigLoader.get_path_value(_data[cfg_name], key_path, default)


func names() -> Array:
	return _data.keys()


## Palette color by name from config/palette.json ("brass_3"); magenta if unknown.
func color(color_name: String) -> Color:
	var hex: Variant = value("palette", "colors." + color_name, null)
	if hex == null:
		push_error("Config: unknown palette color '%s'" % color_name)
		return Color.MAGENTA
	return Color.html(str(hex))
