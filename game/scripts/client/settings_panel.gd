class_name SettingsPanel
extends VBoxContainer
## Graphics preset, mouse sensitivity and fullscreen, saved as they change. Shown by the main
## menu and the pause menu; on_graphics re-applies the preset to a running game.

signal closed

## Called after the preset changes (the game re-applies it); unset in the main menu.
var on_graphics: Callable

var _sensitivity_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(Menus.title("SETTINGS", 28))

	var graphics := OptionButton.new()
	for preset_name: String in Graphics.NAMES:
		graphics.add_item(preset_name)
	graphics.selected = Graphics.preset
	graphics.item_selected.connect(_on_graphics)
	add_child(Menus.row("Graphics", graphics))

	_sensitivity_label = Label.new()
	var slider := HSlider.new()
	slider.min_value = Settings.SENSITIVITY_MIN
	slider.max_value = Settings.SENSITIVITY_MAX
	slider.step = 0.05
	slider.value = Settings.sensitivity
	slider.custom_minimum_size.x = 160
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_sensitivity)
	var sensitivity := HBoxContainer.new()
	sensitivity.add_child(slider)
	sensitivity.add_child(_sensitivity_label)
	_on_sensitivity(Settings.sensitivity)
	add_child(Menus.row("Mouse sensitivity", sensitivity))

	var fullscreen := CheckBox.new()
	fullscreen.button_pressed = get_window().mode == Window.MODE_FULLSCREEN
	fullscreen.toggled.connect(_on_fullscreen)
	add_child(Menus.row("Fullscreen (F11)", fullscreen))

	add_child(Menus.button("Back", func() -> void: closed.emit()))


func _on_graphics(index: int) -> void:
	Graphics.preset = index as Graphics.Preset
	Graphics.save()
	if on_graphics.is_valid():
		on_graphics.call()


func _on_sensitivity(value: float) -> void:
	_sensitivity_label.text = "%.2f" % value
	if not is_equal_approx(value, Settings.sensitivity):
		Settings.sensitivity = value
		Settings.save()


func _on_fullscreen(on: bool) -> void:
	Settings.fullscreen = on
	Settings.apply_window(get_window())
	Settings.save()
