# gdlint: ignore=max-public-methods
class_name Net
extends Node
## Our own RPCs, at /root/Main/Net on server and client so they line up. Movement state and
## input go through netfox (RollbackSynchronizer on each SimPlayer), not through here.

# Server side.
signal hello_received(peer_id: int, version: int, player_name: String)
signal pinged(peer_id: int, sent_ms: int)
signal world_ready_received(peer_id: int)
signal inventory_intent_received(peer_id: int, op: int, a: int, b: int)
# Client side.
signal rejected(reason: String)
signal ponged(sent_ms: int)
signal server_stats_received(tps: float, tick_ms: float, tick_avg_ms: float, out_kbps: float)
signal world_received(world_seed: int, world_name: String)
signal room_received(code: String)
signal notice_received(text: String)
signal cleared_camps_requested(peer_id: int, realm_id: String)
signal cleared_camps_received(cleared: Dictionary)
signal inventory_snapshot_received(data: Dictionary)
signal inventory_changed_received(cells: Dictionary)
signal pickup_requested(peer_id: int, object_id: int)
signal open_object_requested(peer_id: int, object_id: int)
signal objects_snapshot_received(all: Dictionary)
signal object_added_received(id: int, data: Dictionary)
signal object_removed_received(id: int, by: int)
signal object_updated_received(id: int, data: Dictionary)
signal item_toast_received(item_id: String, count: int)

## What a client asks of its inventory (inventory_intent). Append only.
enum Op { MOVE, SPLIT, EQUIP, UNEQUIP, DROP, SORT, STORE_MATCHING, USE }

## Bump on any change to the RPCs here or to what netfox synchronizes (SimPlayer.STATE,
## PlayerControls) or to what both sides simulate (Layout, Gravity, Tuning).
const PROTOCOL_VERSION := 31

@rpc("any_peer", "reliable")
func hello(version: int, player_name: String) -> void:
	hello_received.emit(multiplayer.get_remote_sender_id(), version, player_name)


@rpc("authority", "reliable")
func reject(reason: String) -> void:
	rejected.emit(reason)


@rpc("any_peer", "unreliable")
func ping(sent_ms: int) -> void:
	pinged.emit(multiplayer.get_remote_sender_id(), sent_ms)


@rpc("authority", "unreliable")
func pong(sent_ms: int) -> void:
	ponged.emit(sent_ms)


@rpc("authority", "unreliable")
## out_kbps: kB per second the server sends to each player (ENet only, 0 over WebRTC).
func server_stats(tps: float, tick_ms: float, tick_avg_ms: float, out_kbps: float) -> void:
	server_stats_received.emit(tps, tick_ms, tick_avg_ms, out_kbps)


## The world to build, sent on joining before anything else is spawned. The client builds it
## (World.build), then answers world_ready; only then does the server spawn its player.
@rpc("authority", "reliable")
func world(world_seed: int, world_name: String) -> void:
	world_received.emit(world_seed, world_name)


@rpc("any_peer", "reliable")
func world_ready() -> void:
	world_ready_received.emit(multiplayer.get_remote_sender_id())


## Player host: the lobby room code friends join with, on joining and whenever it changes.
@rpc("authority", "reliable")
func room(code: String) -> void:
	room_received.emit(code)


## A line for every player's HUD ("Ana joined", "Ana lost the connection").
@rpc("authority", "reliable")
func notice(text: String) -> void:
	notice_received.emit(text)


## Debug map (M33): a client asks which camps of a realm are cleared; the server answers
## (camp id -> seconds left) only to the host or with --debug-map, else not at all.
@rpc("any_peer", "unreliable")
func request_cleared_camps(realm_id: String) -> void:
	cleared_camps_requested.emit(multiplayer.get_remote_sender_id(), realm_id)


@rpc("authority", "unreliable")
func cleared_camps(cleared: Dictionary) -> void:
	cleared_camps_received.emit(cleared)


## A client wants to change its inventory: a and b are cell numbers (Inventory.Cell) or a count,
## by op (MOVE from to, SPLIT cell count, EQUIP cell, UNEQUIP cell, DROP cell count, SORT
## junk-mask (bit n set: Items.IDS[n] sorts last), STORE_MATCHING, USE cell: a consumable's
## effect, or equip). The server checks everything and answers with inventory_changed.
@rpc("any_peer", "reliable")
func inventory_intent(op: int, a: int, b: int) -> void:
	inventory_intent_received.emit(multiplayer.get_remote_sender_id(), op, a, b)


## The own inventory, whole, once after the player spawned (Inventory.cell_dict()).
@rpc("authority", "reliable")
func inventory_snapshot(data: Dictionary) -> void:
	inventory_snapshot_received.emit(data)


## The cells of the own inventory that changed (Inventory.changes_since()): cell number to
## {"id", "count"}, or {} for an emptied cell.
@rpc("authority", "reliable")
func inventory_changed(cells: Dictionary) -> void:
	inventory_changed_received.emit(cells)


## A client picks up the drop it points at (key E); the server checks the reach, adds to the
## inventory (inventory_changed), removes the object and says item_toast.
@rpc("any_peer", "reliable")
func pickup(object_id: int) -> void:
	pickup_requested.emit(multiplayer.get_remote_sender_id(), object_id)


## A client opens the chest it points at (key E): the server checks the reach and that the
## camp that guards it is clear, then the chest gives its loot as drops.
@rpc("any_peer", "reliable")
func open_object(object_id: int) -> void:
	open_object_requested.emit(multiplayer.get_remote_sender_id(), object_id)


## Every world object (WorldObjects.snapshot()), once after the player spawned.
@rpc("authority", "reliable")
func objects_snapshot(all: Dictionary) -> void:
	objects_snapshot_received.emit(all)


## A new world object (WorldObjects.Entry.to_net()); "from" is where its arc starts, only here.
@rpc("authority", "reliable")
func object_added(id: int, data: Dictionary) -> void:
	object_added_received.emit(id, data)


## An object is gone: `by` is the peer that took it, 0 when it expired.
@rpc("authority", "reliable")
func object_removed(id: int, by: int) -> void:
	object_removed_received.emit(id, by)


## An object changed (a chest opened, a drop's count).
@rpc("authority", "reliable")
func object_updated(id: int, data: Dictionary) -> void:
	object_updated_received.emit(id, data)


## What the own pickup gave: shown as "+2 Iron scrap".
@rpc("authority", "reliable")
func item_toast(item_id: String, count: int) -> void:
	item_toast_received.emit(item_id, count)
