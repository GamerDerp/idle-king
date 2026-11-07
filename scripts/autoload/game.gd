extends Node
## Autoload `Game`: owns the running GameCore and ticks it every frame.
## The view calls Game.start() once, then reads Game.core (state, battle,
## mods) and drains Game.core.drain_events() each frame. See docs/CORE.md.
##
## Debug args (after `--`):
##   --bot[=idle]   SimBot plays (active cursor, or idle = no cursor)
##   --ff=<sec>     fast-forward this many game seconds at start (no events)
##   --seed=<n>     RNG seed for a new game

signal state_ready
signal started

var core: GameCore = null
var bot: SimBot = null
var running: bool = false


func _ready() -> void:
	var locale: String = str(Config.value("visual", "default_locale", "ru"))
	var lang_arg: String = DevTools.get_arg("lang", "")
	TranslationServer.set_locale(lang_arg if lang_arg != "" else locale)
	state_ready.emit()


## Creates a new game (content from the Config autoload) and starts ticking.
func start(seed_value: int = -1) -> GameCore:
	var cfg: Dictionary = {}
	for n: String in Config.names():
		cfg[n] = Config.get_cfg(n)
	if DevTools.has_arg("seed"):
		seed_value = DevTools.get_arg("seed").to_int()
	core = GameCore.create(seed_value, GameData.new(cfg))
	if DevTools.has_arg("bot"):
		bot = SimBot.new(core, DevTools.get_arg("bot") != "idle")
	var ff: float = DevTools.get_arg("ff", "0").to_float()
	if ff > 0.0:
		fast_forward(ff)
	running = true
	started.emit()
	return core


## Simulates `seconds` of game time immediately (events suppressed).
func fast_forward(seconds: float, dt: float = 0.05) -> void:
	core.emit_events = false
	var end_t: float = core.state.time + seconds
	while core.state.time < end_t - 1e-6:
		if bot != null:
			bot.step(dt)
		core.tick(dt)
	core.emit_events = true


func _process(delta: float) -> void:
	if not running or core == null:
		return
	if bot != null:
		bot.step(delta)
	core.tick(delta)
