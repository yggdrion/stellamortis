class_name Inventory
extends RefCounted
## One player's items (M23, pure data, no nodes): a bag of 32 cells and, apart from it, 10 gear
## cells that hold what is worn, so worn gear takes no bag space. A cell number is 0 to 31 for
## the bag and 32 and up for gear (Cell). Every operation checks its arguments, because the
## intents come from clients, and returns whether it changed anything; none asserts or throws.
## The server owns one per player; clients keep a copy filled from the server's deltas.

## The gear cells, numbered after the bag.
enum Cell {
	MAIN = 32,
	OFF = 33,
	RANGED = 34,
	HELM = 35,
	CHEST = 36,
	LEGS = 37,
	CAPE = 38,
	TRINKET_A = 39,
	TRINKET_B = 40,
	BOLTS = 41,
}

const BAG_SIZE := 32
const CELLS := 42

## The gear cell of each ItemDef.Slot (TRINKET: the first, see _gear_cell).
const SLOT_CELL := {
	ItemDef.Slot.MAIN: Cell.MAIN,
	ItemDef.Slot.OFF: Cell.OFF,
	ItemDef.Slot.RANGED: Cell.RANGED,
	ItemDef.Slot.HELM: Cell.HELM,
	ItemDef.Slot.CHEST: Cell.CHEST,
	ItemDef.Slot.LEGS: Cell.LEGS,
	ItemDef.Slot.CAPE: Cell.CAPE,
	ItemDef.Slot.TRINKET: Cell.TRINKET_A,
	ItemDef.Slot.BOLTS: Cell.BOLTS,
}

## Cells by number, null where empty.
var cells: Array[Stack] = []


func _init() -> void:
	cells.resize(CELLS)


## The kit a new character starts with, worn.
static func starting_kit() -> Inventory:
	var inventory := Inventory.new()
	inventory.cells[Cell.MAIN] = Stack.new(&"sword", 1)
	inventory.cells[Cell.OFF] = Stack.new(&"shield_wood", 1)
	inventory.cells[Cell.RANGED] = Stack.new(&"crossbow", 1)
	inventory.cells[Cell.BOLTS] = Stack.new(&"bolt", 20)
	return inventory


static func is_gear(cell: int) -> bool:
	return cell >= BAG_SIZE and cell < CELLS


static func valid(cell: int) -> bool:
	return cell >= 0 and cell < CELLS


## Whether a stack of this id may sit in a cell: any item in the bag, only the matching item in
## a gear cell.
static func fits(cell: int, id: StringName) -> bool:
	var def := Items.by_id(id)
	if def == null or not valid(cell):
		return false
	if not is_gear(cell):
		return true
	if def.slot == ItemDef.Slot.TRINKET:
		return cell == Cell.TRINKET_A or cell == Cell.TRINKET_B
	return SLOT_CELL.get(def.slot, -1) == cell


func at(cell: int) -> Stack:
	return cells[cell] if valid(cell) else null


## Moves the stack in `from` to `to`: into an empty cell, merged into the same item with room, or
## swapped with what is there (a swap needs the other stack to fit `from`).
func move(from: int, to: int) -> bool:
	var moving := at(from)
	if moving == null or not valid(to) or from == to or not fits(to, moving.id):
		return false
	var target := cells[to]
	if target == null:
		cells[to] = moving
		cells[from] = null
		return true
	if target.id == moving.id:
		var room := Items.by_id(moving.id).stack - target.count
		if room <= 0:
			return false
		var moved := mini(room, moving.count)
		target.count += moved
		moving.count -= moved
		if moving.count <= 0:
			cells[from] = null
		return true
	if not fits(from, target.id):
		return false
	cells[from] = target
	cells[to] = moving
	return true


## Cuts `count` off a stack into the first empty bag cell.
func split(cell: int, count: int) -> bool:
	var source := at(cell)
	if source == null or count < 1 or count >= source.count:
		return false
	var free := _first_empty()
	if free < 0:
		return false
	source.count -= count
	cells[free] = Stack.new(source.id, count)
	return true


## Wears the bag item in `cell`; what it replaces goes to the bag cell it freed.
func equip(cell: int) -> bool:
	var stack := at(cell)
	if stack == null or is_gear(cell):
		return false
	var target := _gear_cell(Items.by_id(stack.id))
	return target >= 0 and move(cell, target)


## Takes a worn item off into the bag (merging, else the first empty cell).
func unequip(cell: int) -> bool:
	var stack := at(cell)
	if stack == null or not is_gear(cell):
		return false
	var left := _put_in_bag(stack.id, stack.count)
	if left == stack.count:
		return false
	if left == 0:
		cells[cell] = null
	else:
		stack.count = left
	return true


## Removes `count` of a stack and returns what was removed, null when the cell holds less.
func drop(cell: int, count: int) -> Stack:
	var stack := at(cell)
	if stack == null or count < 1 or count > stack.count:
		return null
	stack.count -= count
	var removed := Stack.new(stack.id, count)
	if stack.count <= 0:
		cells[cell] = null
	return removed


## Puts items into the bag (stacks first, then empty cells); returns how many did not fit.
func add(id: StringName, count: int) -> int:
	if not Items.has(id) or count < 1:
		return maxi(count, 0)
	return _put_in_bag(id, count)


## How many of an id the bag holds.
func count_of(id: StringName) -> int:
	var total := 0
	for cell in BAG_SIZE:
		if cells[cell] != null and cells[cell].id == id:
			total += cells[cell].count
	return total


## Orders the bag by kind, rarity (high first) and id, merging stacks (full ones first).
func sort() -> bool:
	var before := to_dict()
	var totals := {}
	for cell in BAG_SIZE:
		if cells[cell] != null:
			totals[cells[cell].id] = totals.get(cells[cell].id, 0) + cells[cell].count
	var ids := totals.keys()
	ids.sort_custom(_before)
	for cell in BAG_SIZE:
		cells[cell] = null
	var next := 0
	for id: StringName in ids:
		var left: int = totals[id]
		var size := Items.by_id(id).stack
		while left > 0:
			var put := mini(left, size)
			cells[next] = Stack.new(id, put)
			next += 1
			left -= put
	return to_dict() != before


## Moves every bag stack whose item `other` already holds into `other`'s bag (a chest's contents).
func store_matching(other: Inventory) -> bool:
	var moved := false
	for cell in BAG_SIZE:
		var stack := cells[cell]
		if stack == null or other.count_of(stack.id) == 0:
			continue
		var left := other.add(stack.id, stack.count)
		if left < stack.count:
			moved = true
			if left == 0:
				cells[cell] = null
			else:
				stack.count = left
	return moved


## {cell number: {"id", "count"}} for every filled cell: what the deltas to clients are made of.
func cell_dict() -> Dictionary:
	var result := {}
	for cell in CELLS:
		if cells[cell] != null:
			result[cell] = cells[cell].to_dict()
	return result


## The cells that differ from an earlier cell_dict(): the new value, or {} for a cleared cell.
func changes_since(old: Dictionary) -> Dictionary:
	var now := cell_dict()
	var result := {}
	for cell: int in now:
		if not old.has(cell) or old[cell] != now[cell]:
			result[cell] = now[cell]
	for cell: int in old:
		if not now.has(cell):
			result[cell] = {}
	return result


## Applies a delta from the server (a client's copy); bad entries are skipped.
func apply_cells(delta: Dictionary) -> void:
	for key: Variant in delta:
		var cell := _cell_number(key)
		if not valid(cell):
			continue
		var stack := Stack.from_variant(delta[key])
		cells[cell] = stack if stack != null and fits(cell, stack.id) else null


## The cells with string keys, as JSON keeps them (the character file, task 4).
func to_dict() -> Dictionary:
	var result := {}
	var all := cell_dict()
	for cell: int in all:
		result[str(cell)] = all[cell]
	return result


## Reads a dictionary made by to_dict() (or cell_dict()), whatever it holds: unknown items,
## counts out of range and cells that do not exist are dropped or clamped, a gear item in the
## wrong cell is dropped.
static func from_dict(data: Variant) -> Inventory:
	var inventory := Inventory.new()
	if not data is Dictionary:
		return inventory
	for key: Variant in data:
		var cell := _cell_number(key)
		var stack := Stack.from_variant(data[key])
		if valid(cell) and stack != null and fits(cell, stack.id):
			inventory.cells[cell] = stack
	return inventory


## Whether two inventories hold the same.
func same_as(other: Inventory) -> bool:
	return cell_dict() == other.cell_dict()


## Order of two ids in sort(): kind, then higher rarity, then the id.
static func _before(a: StringName, b: StringName) -> bool:
	var da := Items.by_id(a)
	var db := Items.by_id(b)
	if da.kind != db.kind:
		return da.kind < db.kind
	if da.rarity != db.rarity:
		return da.rarity > db.rarity
	return String(a) < String(b)


static func _cell_number(key: Variant) -> int:
	if key is int:
		return key
	if key is String or key is StringName:
		var text := String(key)
		return text.to_int() if text.is_valid_int() else -1
	return -1


func _first_empty() -> int:
	for cell in BAG_SIZE:
		if cells[cell] == null:
			return cell
	return -1


## The gear cell an item is worn in: the free one of two trinket cells, else the first.
func _gear_cell(def: ItemDef) -> int:
	if def == null or def.slot == ItemDef.Slot.NONE:
		return -1
	if def.slot == ItemDef.Slot.TRINKET and cells[Cell.TRINKET_A] != null:
		return Cell.TRINKET_B if cells[Cell.TRINKET_B] == null else Cell.TRINKET_A
	return SLOT_CELL.get(def.slot, -1)


func _put_in_bag(id: StringName, count: int) -> int:
	var size := Items.by_id(id).stack
	var left := count
	for cell in BAG_SIZE:
		var stack := cells[cell]
		if left > 0 and stack != null and stack.id == id and stack.count < size:
			var put := mini(left, size - stack.count)
			stack.count += put
			left -= put
	for cell in BAG_SIZE:
		if left > 0 and cells[cell] == null:
			var put := mini(left, size)
			cells[cell] = Stack.new(id, put)
			left -= put
	return left


## One stack of one item.
class Stack:
	extends RefCounted

	var id: StringName
	var count: int

	func _init(item: StringName = &"", amount := 0) -> void:
		id = item
		count = amount

	func to_dict() -> Dictionary:
		return {"id": String(id), "count": count}

	## A stack from {"id", "count"} of any content: null for unknown items and what is not a
	## dictionary, a count below 1 dropped and a big one clamped to the item's stack size.
	static func from_variant(data: Variant) -> Stack:
		if not data is Dictionary:
			return null
		var raw: Variant = (data as Dictionary).get("id")
		if not raw is String and not raw is StringName:
			return null
		var item := Items.by_id(StringName(raw))
		var amount: Variant = (data as Dictionary).get("count")
		if item == null or not (amount is int or amount is float):
			return null
		var count := int(clampf(float(amount), -1.0, 1.0e6))
		return Stack.new(item.id, mini(count, item.stack)) if count >= 1 else null
