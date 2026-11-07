class_name ConfigLoader
extends RefCounted
## Loads every `*.json` file of a directory into a Dictionary keyed by file name
## (without extension). Pure static helper: usable from the Config autoload,
## tests and the headless simulation alike.

const DEFAULT_DIR := "res://config"


## Returns { "economy": {...}, "visual": {...}, ... }.
## Malformed or non-object files are reported via push_error and skipped,
## names of failed files are appended to `errors` (if provided).
static func load_dir(dir_path: String = DEFAULT_DIR, errors: Array = []) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Config: cannot open directory %s (%s)" % [dir_path, error_string(DirAccess.get_open_error())])
		errors.append(dir_path)
		return result
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for file_name in files:
		if file_name.get_extension().to_lower() != "json":
			continue
		var path := dir_path.path_join(file_name)
		var data: Variant = load_file(path)
		if data == null:
			errors.append(file_name)
			continue
		result[file_name.get_basename()] = data
	return result


## Parses one JSON file. Returns a Dictionary or null on any error (reported).
static func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Config: file not found: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("Config: malformed JSON in %s, line %d: %s" % [path, json.get_error_line() + 1, json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("Config: %s must contain a JSON object at top level" % path)
		return null
	return json.data


## Reads a nested value by dotted path: get_path_value(cfg, "waves.base_hp", 10.0).
static func get_path_value(data: Dictionary, key_path: String, default: Variant = null) -> Variant:
	var node: Variant = data
	for part in key_path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(part):
			return default
		node = (node as Dictionary)[part]
	return node
