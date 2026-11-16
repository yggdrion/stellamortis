class_name Loadout
extends RefCounted
## What combat needs from an Inventory (M23): four small ints that travel in the rolled back
## state (SimPlayer.GEAR) and the rules that read them. Nothing else about items reaches the
## simulation. Item indices are Items.IDS; 0 is "nothing worn".

var main_hand := 0
var off_hand := 0
var ranged := 0
## Sum of the worn armor pieces' defense, 0 to 255.
var armor := 0


static func of(inventory: Inventory) -> Loadout:
	var loadout := Loadout.new()
	loadout.main_hand = _worn(inventory, Inventory.Cell.MAIN)
	loadout.off_hand = _worn(inventory, Inventory.Cell.OFF)
	loadout.ranged = _worn(inventory, Inventory.Cell.RANGED)
	var total := 0.0
	for cell: int in [Inventory.Cell.HELM, Inventory.Cell.CHEST, Inventory.Cell.LEGS]:
		var def := Items.def(_worn(inventory, cell))
		total += def.defense if def else 0.0
	loadout.armor = clampi(roundi(total), 0, 255)
	return loadout


## The item index in a gear cell, 0 when empty.
static func _worn(inventory: Inventory, cell: int) -> int:
	var stack := inventory.at(cell)
	return Items.index(stack.id) if stack else 0


## Multiplier on the damage of the attack or bolt of a weapon (main hand or crossbow).
static func damage_scale(item_index: int) -> float:
	var def := Items.def(item_index)
	return def.damage if def else Tuning.data().unarmed_damage


## A hit's damage after armor: flat armor off, never below a quarter of it.
static func damage_taken(amount: float, armor_value: int) -> float:
	return maxf(amount - armor_value, amount * 0.25)


## The share of a hit a block stops with this off hand item (a shield adds its defense).
static func block_share(off_hand_index: int) -> float:
	var t := Tuning.data()
	var def := Items.def(off_hand_index)
	var bonus := def.defense if def and def.kind == ItemDef.Kind.SHIELD else 0.0
	return clampf(t.block_reduction + bonus, 0.0, maxf(t.block_cap, t.block_reduction))
