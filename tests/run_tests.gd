extends SceneTree
## Test runner: godot --headless --path . -s res://tests/run_tests.gd [-- --filter=<substr>]
## Discovers res://tests/test_*.gd, runs every method starting with `test_`
## on a fresh instance, prints a summary, exits 1 on any failure.
## Runs on the first process frame so autoloads (Config, Fmt, ...) are ready.

const TEST_DIR := "res://tests"

var _started: bool = false
var _errors := ErrorCounter.new()


## Counts engine/script errors so a test that hits a runtime error
## (null access, push_error, ...) fails instead of silently passing.
class ErrorCounter extends Logger:
	var count: int = 0
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		count += 1
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	var code: int = run_all()
	quit(code)
	return false


func run_all() -> int:
	var filter: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr("--filter=".length())
	var files: Array[String] = _discover()
	var total: int = 0
	var failed: int = 0
	var asserts: int = 0
	var failed_names: Array[String] = []
	var t0: int = Time.get_ticks_msec()
	OS.add_logger(_errors)
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL  %s: cannot load script (parse error?)" % path)
			failed += 1
			total += 1
			failed_names.append(path)
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (path.get_file() + ":" + name).contains(filter):
				continue
			total += 1
			var inst: Object = script.new()
			inst.set("current_test", name)
			var errors_before: int = _errors.count
			inst.call("before_each")
			inst.call(name)
			inst.call("after_each")
			asserts += int(inst.get("asserts"))
			var errs: Array = inst.get("failures")
			var logged: int = _errors.count - errors_before
			var allowed: int = int(inst.get("expected_errors"))
			if logged != allowed:
				errs.append("engine/script errors logged: %d (expected %d) — see output above" % [logged, allowed])
			var label: String = "%s:%s" % [path.get_file(), name]
			if errs.is_empty():
				print("  ok  %s" % label)
			else:
				failed += 1
				failed_names.append(label)
				print("FAIL  %s" % label)
				for e in errs:
					print("        %s" % e)
	var ms: int = Time.get_ticks_msec() - t0
	OS.remove_logger(_errors)
	print("")
	print("Tests: %d, passed: %d, failed: %d, asserts: %d (%d ms)" % [total, total - failed, failed, asserts, ms])
	if failed > 0:
		print("FAILED: " + ", ".join(failed_names))
		return 1
	if total == 0:
		print("No tests found")
		return 1
	print("ALL TESTS PASSED")
	return 0


func _discover() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			out.append(TEST_DIR.path_join(f))
	out.sort()
	return out
