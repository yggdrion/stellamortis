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
## Seconds between world autosaves; a crash loses at most this much of the world.
const AUTOSAVE := 300.0
## A player's character is sent at most this often (seconds).
const CHARACTER_EVERY := 1.0

var net: Net
var solo := false
## Debug: answer every client's debug map request (--debug-map); else only the host's.
var debug_map := false
## The address the ENet server listens on: "*" is every interface. Solo and the test tools
## use 127.0.0.1, so the operating system's firewall has nothing to ask about.
var bind_ip := "*"
## Debug: where players spawn instead of the ring around the arrival gate (--spawn=x,y,z).
var spawn_at: Variant = null
## Debug: more spawn points (--spawn=x,y,z;x,y,z), handed out to players in turn (load test).
var spawn_list: Array[Vector3] = []
## The seed the world is generated from (--seed=N, random without) and its name (--world).
var world_seed := randi()
## An empty name means no world file: nothing is loaded or saved (tests, quick games). With a
## name, `user://worlds/<name>.json` continues the world and is written every AUTOSAVE seconds
## and on every normal exit.
var world_name := ""
## Debug: players spawn inside the ring of the first realm's boss site, so the Warden rises at
## once (--encounter=boss).
var spawn_at_boss := false
## Debug (--debug-loot): a row of items ahead of every joining player; "open" also opens the
## chests after two seconds.
var debug_loot := ""
## Debug (--debug-bag): joining players get a mixed bag and the gear is worn in part.
var debug_bag := false
## Opens a room in this lobby and takes players over WebRTC instead of ENet.
var lobby_url := ""
## Where the room code goes once the room is open ("!reason" if it can't be), for the host's
## client that spawned this server.
var room_file := ""
## The lobby room code, "" without one.
var room := ""
var _rtc: WebRTCMultiplayerPeer

var _world: World
var _inventories: Inventories
var _looting: Looting
var _graves: Graves
## Peer id -> true for inventories changed since their character was sent.
var _character_dirty := {}
## Peer id -> Time.get_ticks_msec() of the last character sent.
var _character_sent := {}
var _spawned := 0
var _names := {}
## Peer ids whose client has built the world (Net.world_ready).
var _built := {}
## Peer id -> Time.get_ticks_msec() of its last ping, for players in the world.
var _heard := {}
var _ever_joined := false
## The first player that joined: the host of a hosted game, the only one when solo.
var _host_id := 0
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
	var saved := {}
	if world_name != "":
		saved = WorldSave.read(world_name)
	if not saved.is_empty():
		if int(saved["seed"]) != world_seed:
			print("World %s continues with its saved seed %d" % [world_name, int(saved["seed"])])
		world_seed = int(saved["seed"])
	_world.build(world_seed, world_name)
	_world.add_spawner()
	if not saved.is_empty():
		WorldSave.restore(saved, _world)
	_inventories = Inventories.new()
	_inventories.net = net
	_inventories.world = _world
	_inventories.changed.connect(
		func(id: int, cells: Dictionary) -> void:
			net.inventory_changed.rpc_id(id, cells)
			_character_dirty[id] = true
	)
	add_child(_inventories)
	_looting = Looting.new()
	_looting.world = _world
	_looting.inventories = _inventories
	if not saved.is_empty():
		_looting.objects = WorldObjects.from_dict(saved.get("objects"))
		_looting.world_seconds = WorldSave.seconds_of(saved)
	_looting.added.connect(
		func(object_id: int, data: Dictionary) -> void:
			for id: int in _heard:
				net.object_added.rpc_id(id, object_id, data)
	)
	_looting.removed.connect(
		func(object_id: int, by: int) -> void:
			for id: int in _heard:
				net.object_removed.rpc_id(id, object_id, by)
	)
	_looting.updated.connect(
		func(object_id: int, data: Dictionary) -> void:
			for id: int in _heard:
				net.object_updated.rpc_id(id, object_id, data)
	)
	_looting.toast.connect(
		func(id: int, item: StringName, count: int) -> void:
			net.item_toast.rpc_id(id, String(item), count)
	)
	_looting.notice.connect(func(id: int, text: String) -> void: net.notice.rpc_id(id, text))
	add_child(_looting)
	_graves = Graves.new()
	_graves.world = _world
	_graves.inventories = _inventories
	_graves.looting = _looting
	add_child(_graves)
	if world_name != "":
		var timer := Timer.new()
		timer.wait_time = AUTOSAVE
		timer.autostart = true
		timer.timeout.connect(save_world)
		add_child(timer)
	net.pickup_requested.connect(
		func(id: int, object_id: int) -> void:
			if _heard.has(id):
				_looting.pickup(id, object_id)
	)
	net.open_object_requested.connect(
		func(id: int, object_id: int) -> void:
			if _heard.has(id):
				_looting.open(id, object_id)
	)
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
			_quit(1)
			return
		multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.peer_connected.connect(
		func(id: int) -> void: Net.keep_throttle_open(multiplayer.multiplayer_peer, id)
	)
	net.hello_received.connect(_on_hello)
	net.pinged.connect(_on_ping)
	net.cleared_camps_requested.connect(_on_cleared_camps_requested)
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


## Writes the world file (nothing without a world name).
func save_world() -> void:
	if world_name == "" or _world == null or _looting == null:
		return
	var data := WorldSave.capture(_world, _looting.objects, _looting.world_seconds)
	if not WorldSave.write(world_name, data):
		push_error("Could not save world %s" % world_name)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_world()


## Quits after saving the world.
func _quit(code := 0) -> void:
	save_world()
	get_tree().quit(code)


## Sends a player's character to its client.
func _send_character(id: int) -> void:
	var inv := _inventories.inventory(id)
	if inv == null:
		return
	_character_dirty.erase(id)
	_character_sent[id] = Time.get_ticks_msec()
	var data := {
		"id": _inventories.player_id(id), "name": _names.get(id, ""), "inventory": inv.to_dict()
	}
	net.character.rpc_id(id, data)


func _process(_delta: float) -> void:
	_drop_silent()
	var now := Time.get_ticks_msec()
	for id: int in _character_dirty.keys():
		if _heard.has(id) and now - _character_sent.get(id, 0) >= CHARACTER_EVERY * 1000:
			_send_character(id)
	var wait := ROOM_JOIN_TIMEOUT if lobby_url != "" else SOLO_JOIN_TIMEOUT
	if solo and not _ever_joined and Time.get_ticks_msec() - _started_ms > wait * 1000:
		print("Nobody joined, exiting")
		_quit()


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
					+ " out_kbps_per_player=%.2f in_kbps_per_player=%.2f awake=%d %s"
				)
				% [
					_names.size(),
					tps,
					average,
					_stats_ms,
					float(_stats_rollback_ticks) / maxi(_stats_loops, 1),
					out_kbps,
					in_kbps,
					_awake_slots(),
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


func _on_hello(
	id: int, version: int, player_name: String, character: Dictionary, player_id: String
) -> void:
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
	if _host_id == 0:
		_host_id = id
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
	if not spawn_list.is_empty():
		at = spawn_list[_spawned % spawn_list.size()]
		_spawned += 1
	if spawn_at is Vector3:
		at = spawn_at
	if spawn_at_boss:
		at = _world.encounter.site.ring_spot(id)
	# The ground under the spawn stands before the body does (a debug spawn may be elsewhere).
	_world.chunks.ensure_around(at)
	# What cannot be read as an inventory starts as the starting kit.
	var inventory := Inventory.starting_kit()
	if character.get("inventory") is Dictionary:
		inventory = Inventory.from_dict(character["inventory"])
	if debug_bag:
		inventory = _debug_inventory()
	_inventories.add_peer(id, inventory, CharacterSave.clean_id(player_id))
	_world.spawn_player(id, _names[id], at)
	net.inventory_snapshot.rpc_id(id, _inventories.snapshot(id))
	net.objects_snapshot.rpc_id(id, _looting.snapshot())
	_heard[id] = Time.get_ticks_msec()
	print("%s joined (%d)" % [_names[id], id])
	if debug_loot != "":
		var body := _world.player(id)
		_looting.debug_pile(body.global_position, body.up, SimPlayer._tangent(body.facing, body.up))
		if debug_loot == "open":
			get_tree().create_timer(2.0).timeout.connect(_looting.debug_open_chests)
	_tell_others(id, "%s joined" % _names[id])


## A bag with a bit of everything and a few worn pieces (screenshots).
func _debug_inventory() -> Inventory:
	var inventory := Inventory.starting_kit()
	for entry: Array in [
		[&"bandage", 6],
		[&"sword_runed", 1],
		[&"axe_bronze", 1],
		[&"shield_iron", 1],
		[&"helm_leather", 1],
		[&"chest_chain", 1],
		[&"legs_barrow", 1],
		[&"ring_ember", 1],
		[&"charm_bone", 1],
		[&"crossbow_ash", 1],
		[&"hide", 14],
		[&"iron_scrap", 33],
		[&"bone", 9],
		[&"ember", 2],
		[&"bolt", 12],
	]:
		inventory.add(entry[0], entry[1])
	inventory.equip(3)
	inventory.equip(4)
	return inventory


func _on_cleared_camps_requested(id: int, realm_id: String) -> void:
	if _heard.has(id) and (debug_map or (solo and id == _host_id)):
		net.cleared_camps.rpc_id(
			id, _world.spawner.cleared_camps(StringName(realm_id), NetworkTime.tick)
		)


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
			_send_character(id)
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
	_inventories.remove_peer(id)
	_character_dirty.erase(id)
	_character_sent.erase(id)
	var player := _world.player(id)
	if player:
		player.queue_free()
	if solo and _names.is_empty():
		_quit()


## Pool slots that are awake (not hidden), for the stats line.
func _awake_slots() -> int:
	var awake := 0
	for i in World.POOL:
		awake += int(_world.pool_slot(i).action != Enemy.Action.HIDDEN)
	return awake
