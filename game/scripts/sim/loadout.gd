class_name Loadout
extends RefCounted
## What combat needs from an Inventory (M23): five small ints that travel in the rolled back
## state (SimPlayer.GEAR) and the rules that read them. Nothing else about items reaches the
## simulation. Item indices are Items.IDS; 0 is "nothing worn".

## How heavy the worn gear is (M42): the roll and stamina classes. Not Class: that shadows a
## native name.
enum Burden { LIGHT, MEDIUM, HEAVY, OVERLOADED }

var main_hand := 0
var off_hand := 0
var ranged := 0
## Sum of the worn armor pieces' defense, 0 to 255.
var armor := 0
## The Burden of the worn gear (equip_load against Tuning.equip_load_max).
var burden := 0


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
	loadout.burden = burden_of(equip_load(inventory), Tuning.data())
	return loadout


## The weight of everything worn (the gear cells, bolts by count); the bag weighs nothing.
static func equip_load(inventory: Inventory) -> float:
	var total := 0.0
	for cell in range(Inventory.Cell.MAIN, Inventory.Cell.BOLTS + 1):
		var stack := inventory.at(cell)
		var def := Items.by_id(stack.id) if stack else null
		if def:
			total += def.weight * stack.count
	return total


## The class of a load: a ratio below a limit is the lower class.
static func burden_of(load_value: float, t: Tuning) -> int:
	var ratio := load_value / t.equip_load_max
	if ratio < t.load_light_ratio:
		return Burden.LIGHT
	if ratio < t.load_medium_ratio:
		return Burden.MEDIUM
	return Burden.HEAVY if ratio < 1.0 else Burden.OVERLOADED


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
