class_name Looting
extends Node
## What lies in the world and who may take it (M23): drops from kills and from players, the
## elite camps' chests. Server only and outside rollback: it keeps a WorldObjects registry,
## decides pickups and chest openings, and emits what happened for GameServer to send as RPCs
## (Net.object_added and friends). Like Inventories it has no RPC calls of its own.

## A drop or chest appeared; `data` is Entry.to_net() plus "from", where a drop's arc starts.
signal added(id: int, data: Dictionary)
## An object is gone; `by` is the peer that took it, 0 when it expired.
signal removed(id: int, by: int)
signal updated(id: int, data: Dictionary)
## What a pickup gave a player, and a line for one player's HUD.
signal toast(peer_id: int, item_id: StringName, count: int)
signal notice(peer_id: int, text: String)

## Materials lying this close (m) to a living player go into its bag by themselves.
const AUTO_REACH := 1.2
## The most a pickup or opening may be away on the server (the client's prompt shows at 2.5 m).
const PICKUP_REACH := 3.5
const CHEST_REACH := 3.0
## Seconds before an item a player dropped can be taken again (so it is not picked up at once).
const DROP_HOLD := 3.0
## Stacks land this far (m) from the spot they burst from.
const SCATTER_MIN := 0.7
const SCATTER_MAX := 1.7
## Seconds between expiry and auto pickup checks.
const PERIOD := 0.2
## Heights (m) above the spot a burst's arc starts: an enemy's chest height, a chest's lid.
const KILL_LIFT := 0.9
const CHEST_LIFT := 0.7
const CHEST_TABLE := &"chest_elite"
## World seconds a grave opens for its owner only.
const GRAVE_LOCK := 600.0

var world: World
var inventories: Inventories
var objects := WorldObjects.new()
## World seconds the server ran (task 4 saves it); the clock of born and expiry.
var world_seconds := 0.0
var _since := 0.0
var _fields := {}


func _ready() -> void:
	world.spawner.dropped.connect(_on_loot)
	inventories.dropped.connect(_on_player_drop)
	seed_chests()


func _process(delta: float) -> void:
	advance(delta)


## Moves the clock on; every PERIOD seconds drops expire and materials are taken.
func advance(delta: float) -> void:
	world_seconds += delta
	_since += delta
	if _since >= PERIOD:
		_since = 0.0
		update()


## One chest per elite camp the world has, unless the loaded world holds it already.
func seed_chests() -> void:
	for spot in world.spawner.chest_spots:
		if objects.has_chest(spot.key()):
			continue
		var flags := {
			"key": spot.key(),
			"realm": String(spot.realm.id),
			"camp": spot.camp,
			"yaw": spot.yaw,
			"opened": false,
		}
		var chest := WorldObjects.Kind.CHEST
		objects.add(chest, Inventory.new(), spot.position, spot.up, world_seconds, "", flags)


## Expires old drops and lets close players take the materials.
func update() -> void:
	for id in objects.expired(world_seconds):
		_remove(id, 0)
	var players := _living_players()
	if players.is_empty():
		return
	for id: int in objects.entries.keys():
		var entry := objects.at(id)
		if entry == null or entry.kind != WorldObjects.Kind.DROP:
			continue
		var held := entry.stack()
		if held == null or Items.by_id(held.id).kind != ItemDef.Kind.MATERIAL:
			continue
		if world_seconds < entry.hold_until:
			continue
		for player in players:
			if player.global_position.distance_to(entry.position) <= AUTO_REACH:
				_take(player.peer_id, id, false)
				break


## A player takes the drop `id` (key E): false when it is gone, too far or the bag is full.
func pickup(peer_id: int, id: int) -> bool:
	var entry := objects.at(id)
	var player := world.player(peer_id)
	if entry == null or entry.kind != WorldObjects.Kind.DROP or not _alive(player):
		return false
	if world_seconds < entry.hold_until:
		return false
	if player.global_position.distance_to(entry.position) > PICKUP_REACH:
		return false
	return _take(peer_id, id, true)


## A player opens the chest `id`: only when its camp is clear and the player stands close; it
## gives its table once, as a burst of drops around it.
func open(peer_id: int, id: int) -> bool:
	var entry := objects.at(id)
	var player := world.player(peer_id)
	if entry == null or entry.kind == WorldObjects.Kind.DROP or not _alive(player):
		return false
	if entry.kind == WorldObjects.Kind.GRAVE:
		return _open_grave(peer_id, id, entry, player)
	if entry.flags.get("opened", false):
		return false
	if player.global_position.distance_to(entry.position) > CHEST_REACH:
		return false
	var unit := world.spawner.unit_of(
		str(entry.flags.get("realm", "")), int(entry.flags.get("camp", -1))
	)
	if not world.spawner.camp_clear(unit):
		notice.emit(peer_id, "The guards still stand")
		return false
	objects.update(id, {"opened": true})
	updated.emit(id, entry.to_net())
	var table := LootTable.by_id(CHEST_TABLE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:chest" % [world.world_seed, entry.flags.get("key", "")])
	if table != null:
		_scatter(entry.position, entry.up, table.roll(rng), int(rng.seed), CHEST_LIFT, 0.0)
	return true


## A dead player's bag becomes a grave where the body fell; returns its object id.
func bury(owner: String, contents: Inventory, at: Vector3, up: Vector3) -> int:
	var id := objects.add(WorldObjects.Kind.GRAVE, contents, ground(at), up, world_seconds, owner)
	added.emit(id, objects.at(id).to_net())
	return id


## A grave gives its things back to its owner, or to anyone once GRAVE_LOCK has passed; what the
## bag cannot hold stays in it, an empty grave goes.
func _open_grave(peer_id: int, id: int, entry: WorldObjects.Entry, player: SimPlayer) -> bool:
	if player.global_position.distance_to(entry.position) > CHEST_REACH:
		return false
	var left_locked := entry.born + GRAVE_LOCK - world_seconds
	if entry.owner != inventories.player_id(peer_id) and left_locked > 0.0:
		notice.emit(peer_id, "Not your grave (%d min)" % ceili(left_locked / 60.0))
		return false
	var full := false
	for cell in Inventory.CELLS:
		var stack := entry.contents.cells[cell]
		if stack == null:
			continue
		var left := inventories.give(peer_id, stack.id, stack.count)
		if left < stack.count:
			toast.emit(peer_id, stack.id, stack.count - left)
		if left == 0:
			entry.contents.cells[cell] = null
		else:
			stack.count = left
			full = true
	if not full:
		_remove(id, peer_id)
		return true
	notice.emit(peer_id, "Bag full")
	return false


## The snapshot a joining client gets.
func snapshot() -> Dictionary:
	return objects.snapshot()


func _on_loot(position: Vector3, up: Vector3, stacks: Array, loot_seed: int) -> void:
	_scatter(position, up, stacks, loot_seed, KILL_LIFT, 0.0)


func _on_player_drop(peer_id: int, stack: Inventory.Stack) -> void:
	var player := world.player(peer_id)
	if player == null:
		return
	var forward := SimPlayer._tangent(player.facing, player.up)
	var at := player.global_position + forward * 1.5
	_scatter(at, player.up, [stack], peer_id + int(world_seconds * 10.0), KILL_LIFT, DROP_HOLD)


## Puts stacks on the ground around a spot (a seeded ring of landing places) and announces them,
## their arc starting `lift` meters above `spot`. `hold` seconds pass before they can be taken.
func _scatter(
	spot: Vector3, up: Vector3, stacks: Array, loot_seed: int, lift: float, hold: float
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = loot_seed + 1
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := up.cross(east)
	var turn := rng.randf() * TAU
	for i in stacks.size():
		var angle := turn + i * TAU / stacks.size()
		var radius := SCATTER_MIN + (SCATTER_MAX - SCATTER_MIN) * rng.randf()
		if stacks.size() == 1:
			radius *= 0.5
		var landing := ground(spot + (east * cos(angle) + north * sin(angle)) * radius)
		_announce(landing, up, stacks[i], spot + up * lift, hold)


## A drop lands at a point, its arc starting at `from`.
func _announce(
	landing: Vector3, up: Vector3, stack: Inventory.Stack, from: Vector3, hold: float
) -> void:
	var id := objects.add_drop(stack, landing, up, world_seconds)
	var entry := objects.at(id)
	entry.hold_until = world_seconds + hold
	var data := entry.to_net()
	data["from"] = from
	added.emit(id, data)


## Debug (--debug-loot): a row of items of every look 6 m ahead of a spot, for screenshots.
func debug_pile(spot: Vector3, up: Vector3, forward: Vector3) -> void:
	var ids: Array[StringName] = [
		&"hide",
		&"shield_wood",
		&"bone",
		&"axe_bronze",
		&"ember",
		&"sword_runed",
		&"charm_bone",
		&"legs_barrow",
		&"ring_ember"
	]
	var side := forward.cross(up).normalized()
	for i in ids.size():
		var at := spot + forward * 6.0 + side * (i - ids.size() / 2.0) * 1.3
		var landing := ground(at)
		var stack := Inventory.Stack.new(ids[i], 1)
		_announce(landing, up, stack, spot + up * 1.4, DROP_HOLD)


## Debug (--debug-loot=open): every chest opens as if its guards had fallen.
func debug_open_chests() -> void:
	for id: int in objects.entries:
		var entry := objects.at(id)
		if entry.kind == WorldObjects.Kind.CHEST and not entry.flags.get("opened", false):
			objects.update(id, {"opened": true})
			updated.emit(id, entry.to_net())


## The point put on its realm's ground along its direction, a hand above it.
func ground(point: Vector3) -> Vector3:
	var realm := Layout.realm_at(point)
	if realm == null:
		return point
	if not _fields.has(realm.id):
		_fields[realm.id] = Terrain.Field.new(realm, world.world_seed)
	var direction := (point - realm.center).normalized()
	var field: Terrain.Field = _fields[realm.id]
	return realm.center + field.surface(direction) + direction * 0.05


func _take(peer_id: int, id: int, asked: bool) -> bool:
	var entry := objects.at(id)
	var held := entry.stack()
	var left := inventories.give(peer_id, held.id, held.count)
	if left >= held.count:
		if asked or not entry.warned:
			notice.emit(peer_id, "Bag full")
		entry.warned = true
		return false
	toast.emit(peer_id, held.id, held.count - left)
	if left == 0:
		_remove(id, peer_id)
	else:
		held.count = left
		updated.emit(id, entry.to_net())
	return true


func _remove(id: int, by: int) -> void:
	if objects.remove(id):
		removed.emit(id, by)


func _living_players() -> Array[SimPlayer]:
	var found: Array[SimPlayer] = []
	for node in world.players.get_children():
		var player := node as SimPlayer
		if _alive(player):
			found.append(player)
	return found


static func _alive(player: SimPlayer) -> bool:
	return player != null and player.action != SimPlayer.Action.DEAD
