extends SceneTree
## Headless balance simulation entry point (placeholder).
## Run via tools/simulate.sh [minutes]. Will drive scripts/core with a bot
## and write a timeline to res://sim_out/ once gameplay exists.

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	print("sim not implemented yet (args: %s)" % str(args))
	quit(0)
	return false
