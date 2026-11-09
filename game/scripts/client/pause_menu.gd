class_name PauseMenu
extends CanvasLayer
## Esc in game (PLAN §6 M11): Resume, Settings, Leave to menu, Quit. The game keeps running
## behind it (it is shared with other players); the own player gets no input meanwhile.

signal resumed
signal left_game

## Re-applies the graphics preset to the running game (GameClient).
var on_graphics: Callable
var _main: VBoxContainer
var _settings: SettingsPanel


func _ready() -> void:
	layer = 20
	visible = false
	var column := Menus.screen(self, Color(0.0, 0.0, 0.0, 0.55))
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	column.add_child(_main)
	_main.add_child(Menus.title("PAUSED", 36))
	_main.add_child(Menus.button("Resume", func() -> void: resumed.emit()))
	_main.add_child(Menus.button("Settings", _show_settings.bind(true)))
	_main.add_child(Menus.button("Leave to menu", func() -> void: left_game.emit()))
	_main.add_child(Menus.button("Quit", func() -> void: get_tree().quit()))
	_settings = SettingsPanel.new()
	_settings.on_graphics = on_graphics
	_settings.visible = false
	_settings.closed.connect(_show_settings.bind(false))
	column.add_child(_settings)


func open() -> void:
	_show_settings(false)
	visible = true


## Esc inside the menu: back from the settings, else resume.
func back() -> void:
	if _settings.visible:
		_show_settings(false)
	else:
		resumed.emit()


func _show_settings(shown: bool) -> void:
	_settings.visible = shown
	_main.visible = not shown
