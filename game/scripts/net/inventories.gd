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
## Peer id -> [[tick, health], ...]: heals still to be written at their tick (see _apply_gear).
var _heals := {}


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
	_heals.erase(peer_id)


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
			done = inv.sort(a)
		Net.Op.USE:
			done = _use(peer_id, inv, a)
		Net.Op.STORE_MATCHING:
			# A chest or grave to store into comes with the world objects (M23 task 2).
			done = false
	if done:
		_gear[peer_id] = _loadout_ints(inv)
		var delta := inv.changes_since(before)
		if not delta.is_empty():
			changed.emit(peer_id, delta)
	return done


## A consumable heals (and is used up); anything wearable is worn (like EQUIP).
func _use(peer_id: int, inv: Inventory, cell: int) -> bool:
	var stack := inv.at(cell)
	var player := world.player(peer_id)
	if stack == null or player.action == SimPlayer.Action.DEAD:
		return false
	var def := Items.by_id(stack.id)
	if def.kind != ItemDef.Kind.CONSUMABLE:
		return inv.equip(cell)
	if def.heal <= 0.0 or player.health >= Tuning.data().max_health:
		return false
	inv.drop(cell, 1)
	var list: Array = _heals.get(peer_id, [])
	list.append([NetworkTime.tick + 1, def.heal])
	_heals[peer_id] = list
	return true


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
func _apply_gear(tick: int) -> void:
	_apply_heals(tick)
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


## A heal belongs to the tick it was asked in: applied there every time that tick runs, so a
## resimulation (which restores older health first) gives it again. Old ones are forgotten.
func _apply_heals(tick: int) -> void:
	for peer_id: int in _heals:
		var player := world.player(peer_id)
		var list: Array = _heals[peer_id]
		for i in range(list.size() - 1, -1, -1):
			if list[i][0] < tick - 60:
				list.remove_at(i)
			elif list[i][0] == tick and player != null:
				player.health = minf(player.health + list[i][1], Tuning.data().max_health)
