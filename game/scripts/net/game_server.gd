class_name GameServer
extends Node
## The authoritative game (PLAN §4.1): solo, host and dedicated all run this. netfox runs the
## tick loop (NetworkEvents starts it with the server) and rolls players back when late input
## arrives; this node admits players and spawns them once their clock is in sync.

const MAX_PLAYERS := 10
## A solo server exits when its player leaves, or if nobody joined within this many seconds.
const SOLO_JOIN_TIMEOUT := 20.0
const SPAWN_RADIUS := 3.0

var net: Net
var solo := false
## Debug: where players spawn instead of the ring around the origin (--spawn=x,y,z).
var spawn_at: Variant = null

var _world: World
var _names := {}
var _ever_joined := false
var _started_ms := 0
var _loop_began := 0
var _stats_ticks := 0
var _stats_ms := 0.0
var _stats_at := 0


func _init() -> void:
	name = "Game"


func start(port: int) -> void:
	_world = World.new(false)
	add_child(_world)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Could not open port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	net.hello_received.connect(_on_hello)
	net.pinged.connect(func(id: int, sent: int) -> void: net.pong.rpc_id(id, sent))
	NetworkTime.before_tick_loop.connect(func() -> void: _loop_began = Time.get_ticks_usec())
	NetworkTime.after_tick_loop.connect(_track_stats)
	NetworkTime.on_tick.connect(func(_delta: float, _tick: int) -> void: _stats_ticks += 1)
	_started_ms = Time.get_ticks_msec()
	_stats_at = _started_ms
	print("Server listening on port %d%s" % [port, " (solo)" if solo else ""])


func _process(_delta: float) -> void:
	if solo and not _ever_joined and Time.get_ticks_msec() - _started_ms > SOLO_JOIN_TIMEOUT * 1000:
		print("Nobody joined, exiting")
		get_tree().quit()


func _track_stats() -> void:
	_stats_ms = maxf(_stats_ms, (Time.get_ticks_usec() - _loop_began) / 1000.0)
	var now := Time.get_ticks_msec()
	if now - _stats_at < 1000:
		return
	if not _names.is_empty():
		net.server_stats.rpc(_stats_ticks * 1000.0 / (now - _stats_at), _stats_ms)
	_stats_ticks = 0
	_stats_ms = 0.0
	_stats_at = now


func _on_hello(id: int, version: int, player_name: String) -> void:
	if version != Net.PROTOCOL_VERSION:
		net.reject.rpc_id(id, "Game version %d, server runs %d" % [version, Net.PROTOCOL_VERSION])
		return
	if _names.has(id):
		return
	_names[id] = player_name.substr(0, 24)
	_ever_joined = true
	# netfox needs the client's clock in sync before it can take part in rollback.
	while not NetworkTime.is_client_synced(id):
		await NetworkTime.after_client_sync
		if not _names.has(id):
			return
	var angle := (_world.players.get_child_count() % MAX_PLAYERS) * TAU / MAX_PLAYERS
	var at := Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS
	_world.spawn_player(id, _names[id], spawn_at if spawn_at is Vector3 else at)
	print("%s joined (%d)" % [_names[id], id])


func _on_peer_disconnected(id: int) -> void:
	if not _names.has(id):
		return
	print("%s left (%d)" % [_names[id], id])
	_names.erase(id)
	var player := _world.player(id)
	if player:
		player.queue_free()
	if solo and _names.is_empty():
		get_tree().quit()
