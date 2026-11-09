class_name Menus
extends RefCounted
## Shared look of the menus and the HUD (M11, restyled in M12): Cinzel (OFL) for titles, buttons
## and HUD capitals, Alegreya (OFL) for running text, parchment on near black, flat dark buttons
## with a thin rim. Also the pieces: a backdrop with a centered column, titles, buttons, rows.

const WIDTH := 380.0
const TITLE_FONT := "res://assets/fonts/Cinzel.ttf"
const BODY_FONT := "res://assets/fonts/Alegreya.ttf"
const PARCHMENT := Color(0.86, 0.8, 0.68)
const BACKDROP := Color(0.035, 0.03, 0.03)


## Cinzel spaced for capitals: titles, buttons, HUD.
static func title_font() -> Font:
	var font := FontVariation.new()
	font.base_font = load(TITLE_FONT)
	font.spacing_glyph = 2
	font.variation_opentype = {"wght": 600}
	return font


static func body_font() -> Font:
	return load(BODY_FONT)


## The theme for a menu (body text in Alegreya) or the HUD (all Cinzel).
static func theme(hud := false) -> Theme:
	var look := Theme.new()
	look.default_font = title_font() if hud else body_font()
	look.default_font_size = 18
	look.set_color("font_color", "Label", PARCHMENT)
	look.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.75))
	look.set_constant("outline_size", "Label", 4)
	look.set_font("font", "Button", title_font())
	for state: String in [
		"font_color", "font_hover_color", "font_pressed_color", "font_focus_color"
	]:
		look.set_color(state, "Button", PARCHMENT if state == "font_color" else Color.WHITE)
	var states := {
		"normal": Color(0.09, 0.075, 0.065, 0.92),
		"hover": Color(0.2, 0.12, 0.08, 0.95),
		"pressed": Color(0.32, 0.12, 0.08),
		"focus": Color(0, 0, 0, 0),
	}
	for state: String in states:
		var box := StyleBoxFlat.new()
		box.bg_color = states[state]
		box.border_color = Color(PARCHMENT, 0.5 if state == "focus" else 0.18)
		box.set_border_width_all(1)
		box.draw_center = state != "focus"
		box.content_margin_left = 12
		box.content_margin_right = 12
		look.set_stylebox(state, "Button", box)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.05, 0.045, 0.04, 0.95)
	field.border_color = Color(PARCHMENT, 0.25)
	field.set_border_width_all(1)
	field.content_margin_left = 8
	look.set_stylebox("normal", "LineEdit", field)
	look.set_color("font_color", "LineEdit", PARCHMENT)
	return look


## A full screen layer: backdrop (dim over the game, opaque in the main menu) and a centered
## column to fill. Returns the column.
static func screen(layer: CanvasLayer, backdrop: Color) -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = theme()
	layer.add_child(root)
	var back := ColorRect.new()
	back.color = backdrop
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallows clicks, so they don't recapture the mouse for the game behind.
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	return column


static func title(text: String, size := 40) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", title_font())
	label.add_theme_font_size_override("font_size", size)
	return label


static func button(text: String, pressed: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 36
	node.pressed.connect(pressed)
	return node


## A label on the left, a control on the right.
static func row(text: String, control: Control) -> HBoxContainer:
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	line.add_child(control)
	return line
