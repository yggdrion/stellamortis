class_name MainMenu
extends CanvasLayer
## The start screen (PLAN §6 M11): Solo, Host (a lobby room), Join by code, Settings, the
## player name, Quit. `message` shows why the last game ended ("The host left").

## mode: "solo", "host" or "join" (code set for join).
signal chosen(mode: String, code: String)

var message := ""
var _main: VBoxContainer
var _settings: SettingsPanel
var _name: LineEdit
var _code: LineEdit


func _ready() -> void:
	var column := Menus.screen(self, Color(0.03, 0.04, 0.05))
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	column.add_child(_main)
	_main.add_child(Menus.title("STELLAMORTIS", 44))
	if message != "":
		var note := Menus.title(message, 18)
		note.add_theme_color_override("font_color", Color(0.9, 0.55, 0.45))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_main.add_child(note)

	_name = LineEdit.new()
	_name.text = Settings.player_name
	_name.max_length = Settings.NAME_LENGTH
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(_on_name)
	_main.add_child(Menus.row("Name", _name))

	_main.add_child(Menus.button("Solo", func() -> void: chosen.emit("solo", "")))
	_main.add_child(Menus.button("Host", func() -> void: chosen.emit("host", "")))
	_code = LineEdit.new()
	_code.placeholder_text = "Room code"
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.text_submitted.connect(func(_text: String) -> void: _join())
	var join := HBoxContainer.new()
	join.add_child(_code)
	join.add_child(Menus.button("Join", _join))
	_main.add_child(join)
	_main.add_child(Menus.button("Settings", _show_settings.bind(true)))
	_main.add_child(Menus.button("Quit", func() -> void: get_tree().quit()))

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_show_settings.bind(false))
	column.add_child(_settings)


func _join() -> void:
	var code := _code.text.strip_edges().to_upper()
	if code != "":
		chosen.emit("join", code)


func _on_name(text: String) -> void:
	Settings.player_name = Settings.clean_name(text)
	Settings.save()


func _show_settings(shown: bool) -> void:
	_settings.visible = shown
	_main.visible = not shown
