class_name Menus
extends RefCounted
## Shared pieces of the plain menus (M11; M12 restyles them): a dimmed full screen backdrop
## with a centered column, titles, buttons and labelled rows.

const WIDTH := 360.0


## A full screen layer: backdrop (dim over the game, opaque in the main menu) and a centered
## column to fill. Returns the column.
static func screen(layer: CanvasLayer, backdrop: Color) -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
