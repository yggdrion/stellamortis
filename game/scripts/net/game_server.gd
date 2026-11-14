class_name GameServer
extends Node
## The authoritative game (PLAN §4.1): solo, host and dedicated all run this. netfox runs the
## tick loop (NetworkEvents starts it with the server) and rolls players back when late input
## arrives; this node admits players and spawns them once their clock is in sync.
##
## Players reach it over ENet by address, or, with a lobby URL, over WebRTC by room code
## (player host, PLAN §4.7): then the server opens the room and keeps it open while it runs, so
## friends can join any time.

## Players in one game. netfox's server-side rollback (GDScript) holds 30 ticks per second
## with 6 on one core; 8 and more fell behind for good (PLAN M7, §8).
const MAX_PLAYERS := 6
## A solo server exits when its player leaves, or if nobody joined within this many seconds.
const SOLO_JOIN_TIMEOUT := 20.0
## The same through a lobby room, which takes longer to set up.
const ROOM_JOIN_TIMEOUT := 60.0
## Seconds before opening a new room after the lobby was lost.
const LOBBY_RETRY := 10.0
## Seconds without a ping from a player before it is dropped. Clients ping every second; a
## crashed one or one that lost its network would otherwise stand there until ENet or WebRTC
## time out (up to 30 s). Generous, so a client's long first frame (shader compiles) is no drop.
const SILENT_DROP := 10.0

var net: Net
var solo := false
## The address the ENet server listens on: "*" is every interface. Solo and the test tools
## use 127.0.0.1, so the operating system's firewall has nothing to ask about.
var bind_ip := "*"
## Debug: where players spawn instead of the ring around the origin (--spawn=x,y,z).
var spawn_at: Variant = null
## The seed the world is generated from (--seed=N, random without) and its name (--world).
var world_seed := randi()
var world_name := "default"
## Debug: start with the mobs dead, so the Warden rises at once (--encounter=boss).
var skip_to_boss := false
## Opens a room in this lobby and takes players over WebRTC instead of ENet.
var lobby_url := ""
## Where the room code goes once the room is open ("!reason" if it can't be), for the host's
## client that spawned this server.
var room_file := ""
## The lobby room code, "" without one.
var room := ""
var _rtc: WebRTCMultiplayerPeer

var _world: World
var _names := {}
## Peer ids whose client has built the world (Net.world_ready).
var _built := {}
## Peer id -> Time.get_ticks_msec() of its last ping, for players in the world.
var _heard := {}
var _ever_joined := false
var _started_ms := 0
var _loop_began := 0
var _stats_ticks := 0
var _stats_ms := 0.0
var _stats_sum_ms := 0.0
var _stats_loops := 0
var _stats_at := 0
## Ticks netfox resimulated in rollback, summed over the second (debug builds only).
var _stats_rollback_ticks := 0
var _profile: RollbackProfile


func _init() -> void:
	name = "Game"


func start(port: int) -> void:
	_world = World.new(false)
	add_child(_world)
	_world.build(world_seed, world_name)
	if skip_to_boss:
		for mob in _world.encounter.mobs:
			mob.take_hit(1000000.0, Vector3.ZERO)
	if lobby_url != "":
		_rtc = WebRTCMultiplayerPeer.new()
		var rtc_err := _rtc.create_server()
		if rtc_err != OK:
			_room_failed("WebRTC is not available (%s)" % error_string(rtc_err))
			return
		multiplayer.multiplayer_peer = _rtc
		_open_room()
	else:
		var peer := ENetMultiplayerPeer.new()
		# Room for a few more connections than players, so the ones over get told why.
		peer.set_bind_ip(bind_ip)
		var err := peer.create_server(port, MAX_PLAYERS + 2)
		if err != OK:
			push_error("Could not open port %d: %s" % [port, error_string(err)])
			get_tree().quit(1)
			return
		multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	net.hello_received.connect(_on_hello)
	net.pinged.connect(_on_ping)
	net.world_ready_received.connect(
		func(id: int) -> void:
			if _names.has(id):
				_built[id] = true
	)
	NetworkTime.before_tick_loop.connect(func() -> void: _loop_began = Time.get_ticks_usec())
	NetworkTime.after_tick_loop.connect(_track_stats)
	NetworkTime.on_tick.connect(func(_delta: float, _tick: int) -> void: _stats_ticks += 1)
	_started_ms = Time.get_ticks_msec()
	_stats_at = _started_ms
	if OS.has_environment("STELLAMORTIS_SERVER_STATS"):
		_profile = RollbackProfile.new()
		_profile.attach()
	if lobby_url == "":
		print("Server listening on port %d%s" % [port, " (solo)" if solo else ""])


## Connects to the lobby and opens a room for the WebRTC peer.
func _open_room() -> void:
	var lobby := LobbyClient.new()
	add_child(lobby)
	lobby.room_opened.connect(
		func(code: String) -> void:
			room = code
			print("Room %s" % code)
			_write_room_file(code)
			for id: int in _names:
				net.room.rpc_id(id, code)
	)
	lobby.failed.connect(
		func(reason: String) -> void:
			lobby.queue_free()
			if room == "":
				_room_failed(reason)
				return
			# Players already in stay connected; new ones need the new code.
			push_warning("Lost the lobby (%s), new room in %d s" % [reason, LOBBY_RETRY])
			room = ""
			get_tree().create_timer(LOBBY_RETRY).timeout.connect(_open_room)
	)
	lobby.host(lobby_url, _rtc)


## The first room could not be opened: nobody can join, so give up.
func _room_failed(reason: String) -> void:
	push_error("Cannot open a room: %s" % reason)
	_write_room_file("!" + reason)
	get_tree().quit(1)


func _write_room_file(text: String) -> void:
	if room_file == "":
		return
	var file := FileAccess.open(room_file, FileAccess.WRITE)
	if file:
		file.store_string(text)


func _process(_delta: float) -> void:
	_drop_silent()
	var wait := ROOM_JOIN_TIMEOUT if lobby_url != "" else SOLO_JOIN_TIMEOUT
	if solo and not _ever_joined and Time.get_ticks_msec() - _started_ms > wait * 1000:
		print("Nobody joined, exiting")
		get_tree().quit()


func _track_stats() -> void:
	var took := (Time.get_ticks_usec() - _loop_began) / 1000.0
	_stats_ms = maxf(_stats_ms, took)
	_stats_sum_ms += took
	_stats_loops += 1
	if NetworkPerformance.is_enabled():
		_stats_rollback_ticks += NetworkPerformance.get_rollback_ticks()
	var now := Time.get_ticks_msec()
	if now - _stats_at < 1000:
		return
	var average := _stats_sum_ms / maxi(_stats_loops, 1)
	var seconds := (now - _stats_at) / 1000.0
	var tps := _stats_ticks / seconds
	var out_kbps := 0.0
	var in_kbps := 0.0
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.host and not _names.is_empty():
		var sent := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
		var received := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
		out_kbps = sent / 1000.0 / seconds / _names.size()
		in_kbps = received / 1000.0 / seconds / _names.size()
	if not _names.is_empty():
		net.server_stats.rpc(tps, _stats_ms, average, out_kbps)
	if OS.has_environment("STELLAMORTIS_SERVER_STATS"):
		# One parseable line per second (tools/run_load_test.py reads it).
		print(
			(
				(
					"stats players=%d tps=%.1f tick_avg_ms=%.2f tick_max_ms=%.2f resim_ticks=%.1f"
					+ " out_kbps_per_player=%.2f in_kbps_per_player=%.2f %s"
				)
				% [
					_names.size(),
					tps,
					average,
					_stats_ms,
					float(_stats_rollback_ticks) / maxi(_stats_loops, 1),
					out_kbps,
					in_kbps,
					_profile.take(),
				]
			)
		)
	_stats_rollback_ticks = 0
	_stats_ticks = 0
	_stats_ms = 0.0
	_stats_sum_ms = 0.0
	_stats_loops = 0
	_stats_at = now


func _on_hello(id: int, version: int, player_name: String) -> void:
	if version != Net.PROTOCOL_VERSION:
		net.reject.rpc_id(id, "Game version %d, server runs %d" % [version, Net.PROTOCOL_VERSION])
		return
	if _names.has(id):
		return
	if _names.size() >= MAX_PLAYERS:
		net.reject.rpc_id(id, "The game is full (%d players)" % MAX_PLAYERS)
		return
	_names[id] = player_name.substr(0, 24)
	_ever_joined = true
	if room != "":
		net.room.rpc_id(id, room)
	# The client builds the world from the seed before anything is spawned for it.
	net.world.rpc_id(id, world_seed, world_name)
	while not _built.has(id):
		await net.world_ready_received
		if not _names.has(id):
			return
	# netfox needs the client's clock in sync before it can take part in rollback.
	while not NetworkTime.is_client_synced(id):
		await NetworkTime.after_client_sync
		if not _names.has(id):
			return
	var at := Layout.spawn_point(id)
	_world.spawn_player(id, _names[id], spawn_at if spawn_at is Vector3 else at)
	_heard[id] = Time.get_ticks_msec()
	print("%s joined (%d)" % [_names[id], id])
	_tell_others(id, "%s joined" % _names[id])


func _on_ping(id: int, sent: int) -> void:
	if _heard.has(id):
		_heard[id] = Time.get_ticks_msec()
	net.pong.rpc_id(id, sent)


## Drops players that went quiet (SILENT_DROP); peer_disconnected then finds them gone.
func _drop_silent() -> void:
	var now := Time.get_ticks_msec()
	for id: int in _heard.keys():
		if now - _heard[id] > SILENT_DROP * 1000:
			print("%s went silent (%d)" % [_names.get(id, "?"), id])
			_heard.erase(id)
			_tell_others(id, "%s lost the connection" % _names.get(id, "A player"))
			_names.erase(id)
			_remove_player(id)
			multiplayer.multiplayer_peer.disconnect_peer(id)


## A HUD line for every player in the world but this one.
func _tell_others(id: int, text: String) -> void:
	for other: int in _heard:
		if other != id:
			net.notice.rpc_id(other, text)


func _on_peer_disconnected(id: int) -> void:
	if not _names.has(id):
		return
	print("%s left (%d)" % [_names[id], id])
	if _heard.has(id):
		_heard.erase(id)
		_tell_others(id, "%s left" % _names[id])
	_names.erase(id)
	_remove_player(id)


func _remove_player(id: int) -> void:
	_built.erase(id)
	var player := _world.player(id)
	if player:
		player.queue_free()
	if solo and _names.is_empty():
		get_tree().quit()
