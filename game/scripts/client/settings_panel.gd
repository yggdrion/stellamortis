class_name SettingsPanel
extends VBoxContainer
## Graphics, sensitivity, volume, fullscreen, vsync and frame cap, saved as they change. Shown by
## the main menu and the pause menu; on_graphics re-applies the preset to a running game.

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

	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = Settings.volume
	volume.custom_minimum_size.x = 160
	volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume.value_changed.connect(_on_volume)
	add_child(Menus.row("Volume", volume))

	var fullscreen := CheckBox.new()
	fullscreen.button_pressed = get_window().mode == Window.MODE_FULLSCREEN
	fullscreen.toggled.connect(_on_fullscreen)
	add_child(Menus.row("Fullscreen (F11)", fullscreen))

	var vsync := CheckBox.new()
	vsync.button_pressed = Settings.vsync
	vsync.toggled.connect(_on_vsync)
	add_child(Menus.row("Vsync", vsync))

	var cap := OptionButton.new()
	for fps: int in Settings.FPS_CAPS:
		cap.add_item("Unlimited" if fps == 0 else str(fps))
	cap.selected = maxi(Settings.FPS_CAPS.find(Settings.max_fps), 0)
	cap.item_selected.connect(_on_cap)
	add_child(Menus.row("Frame cap", cap))

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


func _on_volume(value: float) -> void:
	Settings.volume = value
	Sounds.apply_volume()
	Settings.save()


func _on_fullscreen(on: bool) -> void:
	Settings.fullscreen = on
	Settings.apply_window(get_window())
	Settings.save()


func _on_vsync(on: bool) -> void:
	Settings.vsync = on
	Settings.apply_pacing()
	Settings.save()


func _on_cap(index: int) -> void:
	Settings.max_fps = Settings.FPS_CAPS[index]
	Settings.apply_pacing()
	Settings.save()
