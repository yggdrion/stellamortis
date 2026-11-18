class_name WeaponBar
extends HBoxContainer
## Weapon sets 1 and 2 beside the hotbar (M42): set 1 is the main and off hand (sword and
## shield), set 2 the crossbow with the bolt count. The active set (`SimPlayer.weapon`) is lit.
## Only shown, like the hotbar.

## Slots in order: main hand, off hand, ranged.
var slots: Array[ItemSlot] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	var cells := [Inventory.Cell.MAIN, Inventory.Cell.OFF, Inventory.Cell.RANGED]
	var hints := ["1", "", "2"]
	for i in cells.size():
		var slot := ItemSlot.new()
		slot.cell = cells[i]
		slot.custom_minimum_size = Vector2(44.0, 44.0)
		slot.key_hint = hints[i]
		slots.append(slot)
		if i == 2:  # a wider gap between the two sets
			var gap := Control.new()
			gap.custom_minimum_size.x = 8.0
			add_child(gap)
		add_child(slot)


func show_inventory(inventory: Inventory) -> void:
	slots[0].show_stack(inventory.at(Inventory.Cell.MAIN))
	slots[1].show_stack(inventory.at(Inventory.Cell.OFF))
	var ranged := inventory.at(Inventory.Cell.RANGED)
	var bolts := inventory.at(Inventory.Cell.BOLTS)
	if ranged != null:
		ranged = Inventory.Stack.new(ranged.id, bolts.count if bolts != null else 1)
	slots[2].show_stack(ranged)


## Lights set `weapon` (a SimPlayer.Weapon).
func set_active(weapon: int) -> void:
	var crossbow := weapon == SimPlayer.Weapon.CROSSBOW
	slots[0].mark(not crossbow, false)
	slots[1].mark(not crossbow, false)
	slots[2].mark(crossbow, false)
