class_name Inventories
extends Node
## The server's inventories, one per player (M23). Clients send intents (Net.inventory_intent),
## this applies them to the player's Inventory and answers with the cells that changed; the
## inventory itself is not rolled back. What combat reads from it (Loadout: the worn weapons and
## the armor total) is written to the SimPlayer after every rollback step, because a state
## written before the tick loop would be overwritten by netfox restoring the recorded one; set
## in after_process_tick it is recorded for the next tick, and set again (same value) in a
## resimulated tick it keeps what an earlier equip changed.

## Cells of a player's inventory that changed (GameServer sends them as Net.inventory_changed).
signal changed(peer_id: int, cells: Dictionary)
## A stack a player dropped (Looting puts it on the ground in front of the player).
signal dropped(peer_id: int, stack: Inventory.Stack)

## Intents a player may send per second; more are dropped.
const MAX_INTENTS_PER_SECOND := 30

var net: Net
var world: World

var _inventories := {}
## Peer id -> [main_hand, off_hand, ranged, armor], from Loadout.of at the last change.
var _gear := {}
## Peer id -> [second, intents counted in it].
var _rate := {}


func _ready() -> void:
	net.inventory_intent_received.connect(_on_intent)
	NetworkRollback.after_process_tick.connect(_apply_gear)


## Makes the inventory of a joining player (its kit; task 4 reads the client's character).
func add_peer(peer_id: int, inventory := Inventory.starting_kit()) -> void:
	_inventories[peer_id] = inventory
	_gear[peer_id] = _loadout_ints(inventory)


## Adds items to a player's bag (a pickup); returns how many did not fit.
func give(peer_id: int, id: StringName, count: int) -> int:
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return count
	var before := inv.cell_dict()
	var left := inv.add(id, count)
	var delta := inv.changes_since(before)
	if not delta.is_empty():
		changed.emit(peer_id, delta)
	return left


func remove_peer(peer_id: int) -> void:
	_inventories.erase(peer_id)
	_gear.erase(peer_id)
	_rate.erase(peer_id)


func inventory(peer_id: int) -> Inventory:
	return _inventories.get(peer_id)


## The whole inventory of a player, for its snapshot (Net.inventory_snapshot).
func snapshot(peer_id: int) -> Dictionary:
	return _inventories[peer_id].cell_dict() if _inventories.has(peer_id) else {}


## Applies one intent for a player; returns whether it changed anything. Everything a client
## sends is checked here (Inventory checks the cells and counts).
func apply(peer_id: int, op: int, a: int, b: int) -> bool:
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null or world.player(peer_id) == null:
		return false
	var before := inv.cell_dict()
	var done := false
	match op:
		Net.Op.MOVE:
			done = inv.move(a, b)
		Net.Op.SPLIT:
			done = inv.split(a, b)
		Net.Op.EQUIP:
			done = inv.equip(a)
		Net.Op.UNEQUIP:
			done = inv.unequip(a)
		Net.Op.DROP:
			var removed := inv.drop(a, b)
			done = removed != null
			if done:
				dropped.emit(peer_id, removed)
		Net.Op.SORT:
			done = inv.sort()
		Net.Op.STORE_MATCHING:
			# A chest or grave to store into comes with the world objects (M23 task 2).
			done = false
	if done:
		_gear[peer_id] = _loadout_ints(inv)
		var delta := inv.changes_since(before)
		if not delta.is_empty():
			changed.emit(peer_id, delta)
	return done


func _on_intent(peer_id: int, op: int, a: int, b: int) -> void:
	var now := floori(Time.get_ticks_msec() / 1000.0)
	var rate: Array = _rate.get(peer_id, [now, 0])
	if rate[0] != now:
		rate = [now, 0]
	rate[1] += 1
	_rate[peer_id] = rate
	if rate[1] <= MAX_INTENTS_PER_SECOND:
		apply(peer_id, op, a, b)


func _loadout_ints(inv: Inventory) -> Array[int]:
	var loadout := Loadout.of(inv)
	return [loadout.main_hand, loadout.off_hand, loadout.ranged, loadout.armor]


## After every rollback step, before netfox records the tick: the players wear what their
## inventory says. A few integer compares per player.
func _apply_gear(_tick: int) -> void:
	for peer_id: int in _gear:
		var player := world.player(peer_id)
		if player == null:
			continue
		var ints: Array[int] = _gear[peer_id]
		if (
			player.main_hand != ints[0]
			or player.off_hand != ints[1]
			or player.ranged != ints[2]
			or player.armor != ints[3]
		):
			player.main_hand = ints[0]
			player.off_hand = ints[1]
			player.ranged = ints[2]
			player.armor = ints[3]
