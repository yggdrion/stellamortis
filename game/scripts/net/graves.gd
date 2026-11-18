class_name Graves
extends Node
## Death on the server (M23): the first step a player is DEAD, its bag (not the worn gear) is
## moved into a GRAVE world object where the body fell. The owner takes it back by walking to it
## and pressing E (Looting.open); for GRAVE_LOCK world seconds nobody else can. A second death
## makes a second grave: nothing is ever destroyed (M57's XP in the grave is lost then, PLAN §4.8).
##
## Runs after every rollback step like Spawner.update, so a replayed tick (netfox restores older
## state, the player is DEAD again with the same `respawns`) finds the death in `_buried` and does
## nothing. Not rolled back, and nothing here touches rolled back state.

var world: World
var inventories: Inventories
var looting: Looting

## Peer id -> the `respawns` value of the death it was buried for.
var _buried := {}


func _ready() -> void:
	NetworkRollback.after_process_tick.connect(_watch)


func _watch(_tick: int) -> void:
	for peer_id: int in inventories.peers():
		var player := world.player(peer_id)
		if (
			player != null
			and player.action == SimPlayer.Action.DEAD
			and _buried.get(peer_id, -1) != player.respawns
		):
			_buried[peer_id] = player.respawns
			bury(peer_id, player)


## Moves a player's bag into a grave; returns the grave's object id, 0 when the bag was empty.
func bury(peer_id: int, player: SimPlayer) -> int:
	var bag := inventories.empty_bag(peer_id)
	for stack in bag.cells:
		if stack != null:
			return looting.bury(
				inventories.player_id(peer_id), bag, player.global_position, player.up
			)
	return 0
