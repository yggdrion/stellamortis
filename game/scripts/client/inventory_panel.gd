class_name InventoryPanel
extends Control
## The inventory screen (M23 task 3): the worn gear around a figure beside the 8 by 4 bag, a
## weight line and the action buttons. Opens with I or Tab, frees the mouse and does not pause
## the game. It only shows the client's copy of the inventory (GameClient.inventory) and never
## changes it: every action emits `intent_sent` (GameClient sends it as Net.inventory_intent)
## and the answer is the server's delta. Every action has a key (Controls inv_*, E, arrows) and a
## mouse way (drag and drop, right click or shift click, ctrl click, the buttons).

## An action the player asked for, before it goes to the server.
signal intent_sent(op: int, a: int, b: int)
## The junk list changed (the client writes the character file).
signal junk_changed

const COLUMNS := 8
## The equip load line by Loadout.Burden.
const BURDEN_NAMES: Array[String] = [
	"Light roll", "Medium roll", "Heavy roll", "Overloaded, no roll"
]
const BURDEN_COLORS: Array[Color] = [
	Color(0.86, 0.8, 0.68), Color(0.86, 0.8, 0.68), Color(0.9, 0.7, 0.35), Color(0.9, 0.45, 0.38)
]
## Gear cells on the paper doll as grid positions (column 0 left of the figure, 2 right of it).
const GEAR_POS := {
	Inventory.Cell.HELM: Vector2i(0, 0),
	Inventory.Cell.CHEST: Vector2i(0, 1),
	Inventory.Cell.LEGS: Vector2i(0, 2),
	Inventory.Cell.CAPE: Vector2i(0, 3),
	Inventory.Cell.MAIN: Vector2i(2, 0),
	Inventory.Cell.OFF: Vector2i(2, 1),
	Inventory.Cell.RANGED: Vector2i(2, 2),
	Inventory.Cell.BOLTS: Vector2i(2, 3),
	Inventory.Cell.TRINKET_A: Vector2i(0, 4),
	Inventory.Cell.TRINKET_B: Vector2i(2, 4),
}
const CAPTIONS := {
	Inventory.Cell.HELM: "HELM",
	Inventory.Cell.CHEST: "CHEST",
	Inventory.Cell.LEGS: "LEGS",
	Inventory.Cell.CAPE: "CAPE",
	Inventory.Cell.MAIN: "MAIN",
	Inventory.Cell.OFF: "OFF",
	Inventory.Cell.RANGED: "BOW",
	Inventory.Cell.BOLTS: "BOLTS",
	Inventory.Cell.TRINKET_A: "CHARM",
	Inventory.Cell.TRINKET_B: "CHARM",
}
## Key actions the panel takes while open, first match wins.
const ACTIONS: Array[StringName] = [
	&"inv_sort",
	&"inv_drop",
	&"inv_split",
	&"inv_junk",
	&"inv_grab",
	&"interact",
	&"ui_left",
	&"ui_right",
	&"ui_up",
	&"ui_down",
]
const HINT := (
	"Arrows move the cursor   Enter lifts a stack and puts it down   E or right click equips,"
	+ " unequips or uses\nV or ctrl click splits   X drops   F stars junk (sorted last)"
	+ "   R sorts   I, Tab or Esc closes"
)

## What the panel shows: set by GameClient on every update.
var inventory := Inventory.new()
## Whether starring junk is written to settings.cfg (tests turn it off).
var persist := true
## The cell keys act on: the one the mouse is over, or moved by the arrows. -1 for none.
var cursor := -1
## The cell lifted with Enter, waiting for its target.
var held := -1

var _slots: Array[ItemSlot] = []
var _weight: Label
var _tooltip: ItemTooltip


func _ready() -> void:
	theme = Menus.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.0, 0.5)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallows clicks, so they do not recapture the mouse for the game.
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.045, 0.038, 0.035, 0.96)
	box.border_color = Color(Menus.PARCHMENT, 0.28)
	box.set_border_width_all(1)
	box.set_content_margin_all(18)
	frame.add_theme_stylebox_override("panel", box)
	center.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	frame.add_child(column)

	var head := HBoxContainer.new()
	head.add_child(Menus.title("INVENTORY", 26))
	head.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.get_child(0).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_weight = Label.new()
	head.add_child(_weight)
	column.add_child(head)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	column.add_child(body)
	body.add_child(_doll())
	body.add_child(_bag())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	for entry: Array in [
		["Sort  R", func() -> void: sort()],
		["Use  E", func() -> void: activate(cursor)],
		["Split  V", func() -> void: split_half(cursor)],
		["Star junk  F", func() -> void: toggle_junk(cursor)],
		["Drop  X", func() -> void: drop(cursor)],
	]:
		var button := Menus.button(entry[0], entry[1])
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(button)
	column.add_child(buttons)
	var hint := Label.new()
	hint.text = HINT
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.55)
	column.add_child(hint)

	_tooltip = ItemTooltip.new()
	_tooltip.z_index = 10
	add_child(_tooltip)
	show_inventory(inventory)


## The 10 gear cells around the figure.
func _doll() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var cells := {}
	for cell: int in GEAR_POS:
		cells[GEAR_POS[cell]] = _slot(cell, CAPTIONS[cell])
	var figure := Figure.new()
	figure.custom_minimum_size = Vector2(96.0, 0.0)
	for row in 5:
		for column in 3:
			if column == 1:
				if row == 0:
					figure.size_flags_vertical = Control.SIZE_EXPAND_FILL
					grid.add_child(figure)
				else:
					var gap := Control.new()
					gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
					grid.add_child(gap)
			elif cells.has(Vector2i(column, row)):
				grid.add_child(cells[Vector2i(column, row)])
			else:
				var gap := Control.new()
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grid.add_child(gap)
	return grid


func _bag() -> Control:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for cell in Inventory.BAG_SIZE:
		grid.add_child(_slot(cell, ""))
	return grid


func _slot(cell: int, caption: String) -> ItemSlot:
	var slot := ItemSlot.new()
	slot.cell = cell
	slot.panel = self
	slot.caption = caption
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.mouse_entered.connect(set_cursor.bind(cell))
	if _slots.size() < Inventory.CELLS:
		_slots.resize(Inventory.CELLS)
	_slots[cell] = slot
	return slot


## Shows `value` (the client's copy; never changed here).
func show_inventory(value: Inventory) -> void:
	inventory = value
	if _weight == null:
		return
	for cell in Inventory.CELLS:
		var stack := inventory.at(cell)
		_slots[cell].show_stack(stack, stack != null and Settings.junk.has(stack.id))
		_slots[cell].mark(cell == cursor, cell == held)
	_show_load()
	_update_tooltip()


## "Equip load 9.0 / 25  Light roll": worn gear only, colored by class.
func _show_load() -> void:
	var t := Tuning.data()
	var load_value := Loadout.equip_load(inventory)
	var burden := Loadout.burden_of(load_value, t)
	var max_text := str(roundi(t.equip_load_max))
	_weight.text = "Equip load  %.1f / %s  %s" % [load_value, max_text, BURDEN_NAMES[burden]]
	_weight.add_theme_color_override("font_color", BURDEN_COLORS[burden])


func set_cursor(cell: int) -> void:
	cursor = cell
	for i in _slots.size():
		if _slots[i] != null:
			_slots[i].mark(i == cursor, i == held)
	_update_tooltip()


## The stack the tooltip would describe, and the worn one it is compared with.
func _update_tooltip() -> void:
	var stack := inventory.at(cursor)
	if _tooltip == null or stack == null or not visible:
		if _tooltip != null:
			_tooltip.visible = false
		return
	var worn: Inventory.Stack = null
	var wearable := not Inventory.is_gear(cursor) and Items.by_id(stack.id).slot != 0
	if wearable:
		worn = inventory.at(worn_cell(stack.id))
	_tooltip.show_item(stack, worn, wearable)
	_place_tooltip.call_deferred()


## Beside the cursor's cell, kept inside the screen; after layout, so the cell has its place.
func _place_tooltip() -> void:
	if cursor < 0 or not _tooltip.visible:
		return
	var slot := _slots[cursor]
	var at := slot.global_position + Vector2(slot.size.x + 8.0, 0.0)
	var room := get_viewport_rect().size - _tooltip.get_combined_minimum_size()
	_tooltip.global_position = Vector2(minf(at.x, room.x), clampf(at.y, 0.0, room.y))


## The gear cell an item of this id would go to: the first trinket cell for trinkets.
static func worn_cell(id: StringName) -> int:
	var def := Items.by_id(id)
	return Inventory.SLOT_CELL.get(def.slot, -1) if def != null else -1


# --- actions: each one only emits an intent -------------------------------------------------


func send(op: int, a := 0, b := 0) -> void:
	intent_sent.emit(op, a, b)


## Whether dragging `from` onto `to` would do anything (the server decides for real).
func can_move(from: int, to: int) -> bool:
	if from == to or not Inventory.valid(from) or not Inventory.valid(to):
		return false
	return Inventory.from_dict(inventory.cell_dict()).move(from, to)


func move(from: int, to: int) -> void:
	held = -1
	if can_move(from, to):
		send(Net.Op.MOVE, from, to)
	set_cursor(cursor)


## Right click, shift click or E: unequip a worn item, use a consumable, equip anything else
## that can be worn.
func activate(cell: int) -> void:
	var stack := inventory.at(cell)
	if stack == null:
		return
	var def := Items.by_id(stack.id)
	if Inventory.is_gear(cell):
		send(Net.Op.UNEQUIP, cell)
	elif def.kind == ItemDef.Kind.CONSUMABLE:
		send(Net.Op.USE, cell)
	elif def.slot != ItemDef.Slot.NONE:
		send(Net.Op.EQUIP, cell)


func split_half(cell: int) -> void:
	var stack := inventory.at(cell)
	if stack != null and stack.count >= 2:
		send(Net.Op.SPLIT, cell, stack.count / 2)


## Drops the whole stack in the cell on the ground in front of the player.
func drop(cell: int) -> void:
	var stack := inventory.at(cell)
	if stack != null:
		send(Net.Op.DROP, cell, stack.count)


func sort() -> void:
	send(Net.Op.SORT, Settings.junk_mask())


## Stars (or unstars) the kind of item in the cell: junk sorts last.
func toggle_junk(cell: int) -> void:
	var stack := inventory.at(cell)
	if stack == null:
		return
	if Settings.junk.has(stack.id):
		Settings.junk.erase(stack.id)
	else:
		Settings.junk.append(stack.id)
	if persist:
		junk_changed.emit()
	show_inventory(inventory)


## Enter: lifts the stack under the cursor, then puts it down on the next cell Enter is pressed on.
func grab() -> void:
	if held < 0:
		if inventory.at(cursor) != null:
			held = cursor
			set_cursor(cursor)
	elif held == cursor:
		held = -1
		set_cursor(cursor)
	else:
		move(held, cursor)


# --- keys -------------------------------------------------------------------------------------


## The panel's action a key event means, &"" for none.
func action_for(event: InputEvent) -> StringName:
	for action in ACTIONS:
		if InputMap.has_action(action) and event.is_action_pressed(action, false, true):
			return action
	return &""


## Does what a key asks; returns whether the panel took the event.
func handle_event(event: InputEvent) -> bool:
	var action := action_for(event)
	match action:
		&"inv_sort":
			sort()
		&"inv_drop":
			drop(cursor)
		&"inv_split":
			split_half(cursor)
		&"inv_junk":
			toggle_junk(cursor)
		&"inv_grab":
			grab()
		&"interact":
			activate(cursor)
		&"ui_left":
			set_cursor(neighbor(cursor, Vector2i.LEFT))
		&"ui_right":
			set_cursor(neighbor(cursor, Vector2i.RIGHT))
		&"ui_up":
			set_cursor(neighbor(cursor, Vector2i.UP))
		&"ui_down":
			set_cursor(neighbor(cursor, Vector2i.DOWN))
		_:
			return false
	return true


## The cell one step from `cell` in a direction: along the bag grid, down the gear columns, and
## across from the gear's right column into the bag's first column (and back). No cell yet: the
## first bag cell.
static func neighbor(cell: int, step: Vector2i) -> int:
	if not Inventory.valid(cell):
		return 0
	if not Inventory.is_gear(cell):
		var column := cell % COLUMNS
		var row := cell / COLUMNS
		if column == 0 and step == Vector2i.LEFT:
			return _gear_at(Vector2i(2, mini(row, 4)))
		column = clampi(column + step.x, 0, COLUMNS - 1)
		row = clampi(row + step.y, 0, Inventory.BAG_SIZE / COLUMNS - 1)
		return row * COLUMNS + column
	var at: Vector2i = GEAR_POS[cell]
	if step == Vector2i.RIGHT and at.x == 2:
		return mini(at.y, 3) * COLUMNS
	var target := Vector2i(at.x + step.x * 2, at.y + step.y)
	target.x = clampi(target.x, 0, 2)
	var found := _gear_at(target)
	return found if found >= 0 else cell


static func _gear_at(position: Vector2i) -> int:
	for cell: int in GEAR_POS:
		if GEAR_POS[cell] == position:
			return cell
	return -1


## A plain silhouette between the two gear columns.
class Figure:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var color := Color(Menus.PARCHMENT, 0.16)
		var x := size.x / 2.0
		var top := 14.0
		draw_circle(Vector2(x, top + 18.0), 15.0, color)
		draw_rect(Rect2(x - 20.0, top + 40.0, 40.0, 78.0), color)
		draw_line(Vector2(x - 28.0, top + 46.0), Vector2(x - 36.0, top + 118.0), color, 9.0)
		draw_line(Vector2(x + 28.0, top + 46.0), Vector2(x + 36.0, top + 118.0), color, 9.0)
		draw_line(Vector2(x - 10.0, top + 120.0), Vector2(x - 12.0, top + 200.0), color, 14.0)
		draw_line(Vector2(x + 10.0, top + 120.0), Vector2(x + 12.0, top + 200.0), color, 14.0)
