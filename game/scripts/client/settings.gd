class_name Settings
extends RefCounted
## The player's settings besides the graphics preset (Graphics keeps that one), saved in the
## same user://settings.cfg: name, mouse sensitivity, fullscreen.

const SENSITIVITY_MIN := 0.2
const SENSITIVITY_MAX := 3.0
const NAME_LENGTH := 16

static var player_name := "player"
## Multiplier on Controls.MOUSE_SENSITIVITY.
static var sensitivity := 1.0
static var fullscreen := true


static func load_saved() -> void:
	var config := ConfigFile.new()
	if config.load(Graphics.SETTINGS) != OK:
		return
	player_name = clean_name(str(config.get_value("player", "name", player_name)))
	sensitivity = clampf(
		float(config.get_value("input", "sensitivity", sensitivity)),
		SENSITIVITY_MIN,
		SENSITIVITY_MAX
	)
	fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))


static func save() -> void:
	var config := ConfigFile.new()
	config.load(Graphics.SETTINGS)
	config.set_value("player", "name", player_name)
	config.set_value("input", "sensitivity", sensitivity)
	config.set_value("display", "fullscreen", fullscreen)
	config.save(Graphics.SETTINGS)


## A name as shown to others: trimmed, at most NAME_LENGTH characters, "player" when empty.
static func clean_name(text: String) -> String:
	var cleaned := text.strip_edges().left(NAME_LENGTH)
	return cleaned if cleaned != "" else "player"


static func apply_window(window: Window) -> void:
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
