class_name World
extends Node3D
## What server and client share at the same node path (/root/Main/Game/World): the arena and
## the players, spawned by the server through a MultiplayerSpawner so late joiners get them too.

signal player_spawned(player: SimPlayer)

var visual := false
var arena: Arena
var players: Node3D
var _spawner: MultiplayerSpawner


func _init(with_visuals: bool) -> void:
	name = "World"
	visual = with_visuals


func _ready() -> void:
	arena = Arena.new(visual)
	add_child(arena)
	players = Node3D.new()
	players.name = "Players"
	add_child(players)
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("../Players")
	_spawner.spawn_function = _spawn_player
	add_child(_spawner)
	_add_dummies()


## The same dummies, same names and order, on every peer (netfox finds them by path).
func _add_dummies() -> void:
	var enemies := Node3D.new()
	enemies.name = "Enemies"
	add_child(enemies)
	for i in Layout.DUMMIES.size():
		var dummy := TrainingDummy.new()
		dummy.name = "Dummy%d" % i
		dummy.index = i
		dummy.passive = Layout.DUMMIES[i][1]
		dummy.networked(Enemy.STATE)
		dummy.position = Layout.DUMMIES[i][0]
		dummy.facing = Vector3.BACK
		dummy.basis = SimPlayer.frame(Vector3.UP, dummy.facing)
		if visual:
			dummy.add_child(EnemyView.new(dummy))
		enemies.add_child(dummy)


## Server only: spawns a player on every peer.
func spawn_player(peer_id: int, player_name: String, at: Vector3) -> void:
	_spawner.spawn([peer_id, player_name, at])


func player(peer_id: int) -> SimPlayer:
	return players.get_node_or_null("Player%d" % peer_id) as SimPlayer


func _spawn_player(data: Array) -> Node:
	var peer_id: int = data[0]
	var player_name: String = data[1]
	var body := SimPlayer.new()
	body.player_name = player_name
	body.networked(peer_id, visual)
	body.place(data[2])
	if visual:
		var own := peer_id == multiplayer.get_unique_id()
		body.add_child(PlayerView.new(body, not own))
	player_spawned.emit.call_deferred(body)
	return body
