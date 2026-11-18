class_name Hotbar
extends HBoxContainer
## The first 8 bag cells at the bottom of the HUD (M23). Keys 3 to 8 use the items in cells 0 to
## 5 (a bandage heals, wearable gear is worn); keys 1 and 2 stay the weapon select. The cells are
## the bag's own, so moving an item to the left of the bag puts it on the bar.

const CELLS := 8
## Width of the bar: slots of 44 px with 4 px gaps.
const WIDTH := CELLS * 44.0 + (CELLS - 1) * 4.0
## Keys that use cell 0 to 5 (Controls use_1 .. use_6).
const USE_ACTIONS: Array[StringName] = [&"use_1", &"use_2", &"use_3", &"use_4", &"use_5", &"use_6"]
const KEY_LABELS: Array[String] = ["3", "4", "5", "6", "7", "8"]

var _slots: Array[ItemSlot] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	for cell in CELLS:
		var slot := ItemSlot.new()
		slot.cell = cell
		slot.custom_minimum_size = Vector2(44.0, 44.0)
		slot.key_hint = KEY_LABELS[cell] if cell < KEY_LABELS.size() else ""
		_slots.append(slot)
		add_child(slot)


func show_inventory(inventory: Inventory) -> void:
	for cell in CELLS:
		var stack := inventory.at(cell)
		_slots[cell].show_stack(stack, stack != null and Settings.junk.has(stack.id))


## The bag cell a key event uses, -1 for none.
static func cell_for(event: InputEvent) -> int:
	for cell in USE_ACTIONS.size():
		if InputMap.has_action(USE_ACTIONS[cell]) and event.is_action_pressed(USE_ACTIONS[cell]):
			return cell
	return -1
