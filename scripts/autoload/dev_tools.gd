extends Node
## Autoload `DevTools`: command-line user args (after `--`) for automation.
##   --shot=<path>        save a PNG of the viewport ...
##   --shot-time=<sec>    ... after this much GAME time (default 1.0; scaled by --timescale)
##   --timescale=<k>      Engine.time_scale = k (speeds up game time)
##   --quit-after=<sec>   quit after this much REAL time (safety timeout)
##   --lang=<ru|en>       override locale
## With --shot and no --quit-after, the game quits right after saving the shot.
## Any other `--key=value` / `--flag` is kept and readable via get_arg().

var args: Dictionary = {}
var shot_path: String = ""
var shot_time: float = 1.0
var quit_after: float = -1.0
var game_time: float = 0.0

var _shot_done: bool = false
var _start_msec: int = 0


func _init() -> void:
	args = parse_args(OS.get_cmdline_user_args())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_msec = Time.get_ticks_msec()
	shot_path = get_arg("shot", "")
	shot_time = maxf(0.0, get_arg("shot-time", "1.0").to_float())
	quit_after = get_arg("quit-after", "-1").to_float()
	var ts: float = get_arg("timescale", "1.0").to_float()
	if ts > 0.0:
		Engine.time_scale = ts
	if not args.is_empty():
		print("DevTools: args ", args)


## Parses ["--a=1", "--flag", "x"] -> {"a": "1", "flag": "true"}.
static func parse_args(user_args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for raw in user_args:
		var a := raw.strip_edges()
		if not a.begins_with("--"):
			continue
		a = a.substr(2)
		var eq := a.find("=")
		if eq >= 0:
			out[a.left(eq)] = a.substr(eq + 1)
		else:
			out[a] = "true"
	return out


func has_arg(key: String) -> bool:
	return args.has(key)


func get_arg(key: String, default: String = "") -> String:
	return str(args.get(key, default))


func _process(delta: float) -> void:
	game_time += delta  # delta is already multiplied by Engine.time_scale
	if shot_path != "" and not _shot_done and game_time >= shot_time:
		_shot_done = true
		_take_shot()
	if quit_after >= 0.0 and (Time.get_ticks_msec() - _start_msec) / 1000.0 >= quit_after:
		print("DevTools: quit-after reached")
		get_tree().quit(0)


func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	var path := shot_path
	if DisplayServer.get_name() == "headless":
		print("DevTools: headless display, screenshot skipped (%s)" % path)
	else:
		var img := get_viewport().get_texture().get_image()
		var abs_path := path if path.is_absolute_path() else ProjectSettings.globalize_path(path)
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		var err := img.save_png(abs_path)
		if err == OK:
			print("DevTools: screenshot saved %s (%dx%d, game time %.2fs)" % [abs_path, img.get_width(), img.get_height(), game_time])
		else:
			push_error("DevTools: failed to save screenshot %s: %s" % [abs_path, error_string(err)])
	if quit_after < 0.0:
		get_tree().quit(0)
