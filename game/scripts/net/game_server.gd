class_name GameServer
extends Node
## The authoritative game (PLAN §4.1): solo, host and dedicated all run this. Takes inputs,
## moves every player once per received input and sends each client a snapshot every tick.

const MAX_PLAYERS := 10
## A solo server exits when its player leaves, or if nobody joined within this many seconds.
const SOLO_JOIN_TIMEOUT := 20.0
## Inputs a player may run in one tick; the rest wait (a burst after a network hiccup).
const MAX_INPUTS_PER_TICK := 8
const SPAWN_RADIUS := 3.0

var net: Net
var solo := false

var tick := 0
var _world: Node3D
## peer id -> SimPlayer
var _players := {}
## peer id -> Array[PlayerInput], oldest first
var _pending := {}
## peer id -> tick of the last input run, sent back so the client can drop older ones
var _acked := {}
var _ever_joined := false
var _started_ms := 0
var _stats_ticks := 0
var _stats_ms := 0.0
var _stats_at := 0


func start(port: int) -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_world.add_child(Arena.new(false))

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Could not open port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	net.hello_received.connect(_on_hello)
	net.inputs_received.connect(_on_inputs)
	net.pinged.connect(func(id: int, sent: int) -> void: net.pong.rpc_id(id, sent))
	_started_ms = Time.get_ticks_msec()
	_stats_at = _started_ms
	print("Server listening on port %d%s" % [port, " (solo)" if solo else ""])


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	var began := Time.get_ticks_usec()
	tick += 1
	for id: int in _players:
		var player: SimPlayer = _players[id]
		var queue: Array = _pending[id]
		var ran := 0
		while not queue.is_empty() and ran < MAX_INPUTS_PER_TICK:
			var input: PlayerInput = queue.pop_front()
			player.step(input, delta)
			_acked[id] = input.tick
			ran += 1
	_send_snapshots()
	_track_stats(began)
	if solo and not _ever_joined and Time.get_ticks_msec() - _started_ms > SOLO_JOIN_TIMEOUT * 1000:
		print("Nobody joined, exiting")
		get_tree().quit()


func _send_snapshots() -> void:
	if _players.is_empty():
		return
	var players: Array[SimPlayer] = []
	for player: SimPlayer in _players.values():
		players.append(player)
	var connected := multiplayer.get_peers()
	for id: int in _players:
		if id in connected:
			net.snapshot.rpc_id(id, Net.pack_snapshot(tick, _acked[id], players))


func _track_stats(began_usec: int) -> void:
	_stats_ticks += 1
	_stats_ms = maxf(_stats_ms, (Time.get_ticks_usec() - began_usec) / 1000.0)
	var now := Time.get_ticks_msec()
	if now - _stats_at < 1000:
		return
	var tps := _stats_ticks * 1000.0 / (now - _stats_at)
	if not _players.is_empty():
		net.server_stats.rpc(tps, _stats_ms)
	_stats_ticks = 0
	_stats_ms = 0.0
	_stats_at = now


func _on_hello(id: int, version: int, player_name: String) -> void:
	if version != Net.PROTOCOL_VERSION:
		net.reject.rpc_id(id, "Game version %d, server runs %d" % [version, Net.PROTOCOL_VERSION])
		return
	if _players.has(id):
		return
	var player := SimPlayer.new()
	player.peer_id = id
	player.player_name = player_name.substr(0, 24)
	player.name = "Player%d" % id
	var angle := _players.size() * TAU / MAX_PLAYERS
	_world.add_child(player)
	player.global_position = Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS
	_players[id] = player
	_pending[id] = []
	_acked[id] = 0
	_ever_joined = true
	net.welcome.rpc_id(id, id)
	print("%s joined (%d)" % [player.player_name, id])


func _on_inputs(id: int, data: PackedByteArray) -> void:
	if not _players.has(id):
		return
	var queue: Array = _pending[id]
	var newest: int = _acked[id] if queue.is_empty() else (queue.back() as PlayerInput).tick
	for input in Net.unpack_inputs(data):
		if input.tick > newest:
			queue.append(input)
			newest = input.tick


func _on_peer_disconnected(id: int) -> void:
	if not _players.has(id):
		return
	var player: SimPlayer = _players[id]
	print("%s left (%d)" % [player.player_name, id])
	player.queue_free()
	_players.erase(id)
	_pending.erase(id)
	_acked.erase(id)
	if solo and _players.is_empty():
		get_tree().quit()
