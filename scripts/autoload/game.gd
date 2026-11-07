extends Node
## Autoload `Game`: owner of the core game state (placeholder).
## The core simulation (scripts/core) will be created and ticked here once
## DESIGN.md specifies gameplay. The view reads state and listens to signals.

signal state_ready


func _ready() -> void:
	var locale: String = str(Config.value("visual", "default_locale", "ru"))
	var lang_arg: String = DevTools.get_arg("lang", "")
	TranslationServer.set_locale(lang_arg if lang_arg != "" else locale)
	state_ready.emit()
