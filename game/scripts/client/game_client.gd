class_name GameClient
extends Node3D
## A player's side of the game (PLAN §4.3). netfox predicts the own player from its input and
## rolls it back on server state, and interpolates every player between ticks; this node fills
## the input, follows the own player with the camera and runs the bot and screenshot modes.
## It reaches the server over ENet by address (solo, --connect) or over WebRTC by lobby room
## code (player host, PLAN §4.7).

signal left(reason: String)
## The own player is in the world (the main menu waits for it).
signal entered
## The own inventory changed (the snapshot or a delta from the server).
signal inventory_updated

## Seconds without a word from the server before the HUD warns, and before giving up.
const SILENT_WARN := 2.0
const SILENT_LEAVE := 8.0

var net: Net
var player_name := "player"
var bot := false
## Bot: players (itself included) it has to see move before it may pass.
var bot_expect := 1
## Bot: seconds to run at least.
var bot_duration := 5.0
## Bot: "" walks and runs through everything; "shoot" stands, aims where the camera looks and
## fires full draws (screenshots).
var bot_plan := ""
## Saves a PNG of the screen here after screenshot_delay seconds, then quits (visual checks).
var screenshot_path := ""
var screenshot_delay := 4.0
## How many screenshots, 50 ms apart (PATH gets _0, _1, ... before .png when more than one).
var screenshot_frames := 1
## A preset name for this run only (--graphics), "" for the saved one.
var graphics := ""
## Camera yaw and pitch in degrees to start with (screenshots), null for the default.
var look: Variant = null
## Opens the map at the start and keeps it open (--map): "" no, "full" the whole realm, else the
## meters across.
var map_start := ""
## Opens the inventory panel a second after the start (--inventory).
var inventory_start := false
## The cell the panel's cursor starts on when opened by --inventory.
var inventory_cursor := 0
## Leaves the mouse free until a click in the window (--no-grab, and every --screenshot run).
var no_grab := false

var me: SimPlayer
## The own inventory as the server last said (read only: the panel shows it, intents change it).
var inventory := Inventory.new()
var ping_ms := 0
var server_tps := 0.0
var server_tick_ms := 0.0
var server_tick_avg_ms := 0.0
var server_out_kbps := 0.0
## Player host: the room code friends join with, "" without one.
var room := ""
## Over WebRTC: the lobby that set up the connection.
var lobby: LobbyClient
## Debug: only relay ICE candidates (LobbyClient.relay_only).
var relay_only := false
## This client opened the room it joins (--host or Host in the menu): when the server goes, it
## is not "the host left".
var hosting := false
## How the game was started: "solo", "host", "join" or "connect" (Presence shows it).
var mode := "solo"

var _world: World
var _rig: CameraRig
## Set by leave(): the disconnect that follows is ours, not a lost server.
var _leaving := false
## When the server was last heard from (pong or stats), 0 before the first. A server that
## crashed or a host that lost its network sends nothing, and ENet or WebRTC take up to 30 s to
## notice: after SILENT_WARN the HUD says so, after SILENT_LEAVE the game ends.
var _heard_ms := 0
var _overlay: DebugOverlay
var _hud: Hud
var _pause: PauseMenu
var _map: MapPanel
## Whether the server's snapshot arrived: before it the character file must not be written.
var _have_inventory := false
var _panel: InventoryPanel
var _objects: ObjectsView
## The planet's wind (Sounds.ambience).
var _ambience: AudioStreamPlayer
var _started_ms := 0
## The weapon picked with 1, 2 or the wheel (SimPlayer.Weapon).
var _wanted_weapon := 0
## Bot: peer id -> where it first saw that player; ids it saw move are in _seen_moved.
var _first_seen := {}
## Debug (STELLAMORTIS_SNAP_LOG=1): prints when the own player jumps between ticks.
var _snap_log := OS.get_environment("STELLAMORTIS_SNAP_LOG") == "1"
var _snap_tick := -1
var _snap_at := Vector3.ZERO
var _seen_moved := {}
## Bot: where it first stood, and whether it has been 4 m away from there since (a respawn
## near the spawn must not undo that).
var _bot_start: Variant = null
var _bot_moved := false
## Bot: how far its inventory exercise got (take the shield off, put it on again).
var _bot_gear_step := 0


func _init() -> void:
	name = "Game"


func _ready() -> void:
	_world = World.new(true)
	add_child(_world)
	_world.player_spawned.connect(_on_player_spawned)
	Graphics.load_saved()
	if graphics != "":
		Graphics.preset = maxi(0, Graphics.NAMES.find(graphics.capitalize())) as Graphics.Preset
	Graphics.apply(get_viewport(), _world.arena)
	_rig = CameraRig.new()
	add_child(_rig)
	_hud = Hud.new()
	add_child(_hud)
	_objects = ObjectsView.new()
	_objects.world = _world
	add_child(_objects)
	_overlay = DebugOverlay.new()
	_overlay.client = self
	add_child(_overlay)
	_ambience = AudioStreamPlayer.new()
	add_child(_ambience)
	_map = MapPanel.new()
	_map.world = _world
	_map.camera = _rig.camera
	var map_layer := CanvasLayer.new()
	map_layer.layer = 5
	map_layer.add_child(_map)
	add_child(map_layer)
	_panel = InventoryPanel.new()
	_panel.visible = false
	_panel.junk_changed.connect(save_character)
	_panel.intent_sent.connect(func(op: int, a: int, b: int) -> void: send_intent(op, a, b))
	var panel_layer := CanvasLayer.new()
	panel_layer.layer = 6
	panel_layer.add_child(_panel)
	add_child(panel_layer)
	_pause = PauseMenu.new()
	_pause.on_graphics = func() -> void: Graphics.apply(get_viewport(), _world.arena)
	_pause.resumed.connect(_resume)
	_pause.left_game.connect(_leave_to_menu)
	add_child(_pause)
	net.rejected.connect(func(reason: String) -> void: left.emit(reason))
	net.world_received.connect(
		func(world_seed: int, world_name: String) -> void:
			_world.build(world_seed, world_name)
			net.world_ready.rpc_id(1)
	)
	net.cleared_camps_received.connect(func(cleared: Dictionary) -> void: _map.cleared = cleared)
	net.room_received.connect(func(code: String) -> void: room = code)
	net.ponged.connect(
		func(sent: int) -> void:
			ping_ms = Time.get_ticks_msec() - sent
			_heard_ms = Time.get_ticks_msec()
	)
	net.inventory_snapshot_received.connect(
		func(data: Dictionary) -> void:
			inventory = Inventory.from_dict(data)
			_have_inventory = true
			_show_inventory()
	)
	net.inventory_changed_received.connect(
		func(cells: Dictionary) -> void:
			inventory.apply_cells(cells)
			_show_inventory()
	)
	net.character_received.connect(
		func(data: Dictionary) -> void:
			var saved := Inventory.from_dict(data.get("inventory"))
			CharacterSave.write(Settings.player_id, player_name, saved, Settings.junk)
	)
	net.notice_received.connect(func(text: String) -> void: _hud.notice(text))
	net.objects_snapshot_received.connect(func(all: Dictionary) -> void: _objects.snapshot(all))
	net.object_added_received.connect(
		func(id: int, data: Dictionary) -> void: _objects.add(id, data)
	)
	net.object_removed_received.connect(func(id: int, by: int) -> void: _objects.remove(id, by))
	net.object_updated_received.connect(
		func(id: int, data: Dictionary) -> void: _objects.update(id, data)
	)
	net.item_toast_received.connect(
		func(item_id: String, count: int) -> void:
			var def := Items.by_id(StringName(item_id))
			if def != null:
				_hud.notice("+%d %s" % [count, def.title])
	)
	net.server_stats_received.connect(
		func(tps: float, tick_ms: float, tick_avg_ms: float, out_kbps: float) -> void:
			server_tps = tps
			server_tick_ms = tick_ms
			server_tick_avg_ms = tick_avg_ms
			server_out_kbps = out_kbps
			_heard_ms = Time.get_ticks_msec()
	)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_each_second)
	add_child(timer)
	_started_ms = Time.get_ticks_msec()
	if screenshot_path != "":
		_take_screenshot.call_deferred()


func join(host: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		left.emit("Could not connect: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	_watch_connection()


## Joins a lobby room by code, over WebRTC.
func join_room(lobby_url: String, code: String) -> void:
	room = code.strip_edges().to_upper()
	lobby = LobbyClient.new()
	lobby.relay_only = relay_only
	add_child(lobby)
	lobby.peer_created.connect(
		func(peer: WebRTCMultiplayerPeer) -> void: multiplayer.multiplayer_peer = peer
	)
	lobby.failed.connect(
		func(reason: String) -> void:
			push_error(reason)
			var path := lobby.log.path_shown() if lobby.log else ""
			left.emit(reason if path == "" else "%s (details: %s)" % [reason, path])
	)
	_watch_connection()
	lobby.join(lobby_url, room)


## The first message: the character file (empty for a new player) and the player ID. The ID in
## the file wins, so a character keeps its graves when settings.cfg is new.
func _say_hello() -> void:
	Settings.ensure_player_id()
	var character := CharacterSave.read(player_name)
	if character.is_empty():
		Settings.junk = []
	else:
		Settings.junk = character["junk"]
		if character["id"] != "":
			Settings.player_id = character["id"]
	net.hello.rpc_id(1, Net.PROTOCOL_VERSION, player_name, character, Settings.player_id)


## Writes the character file from the inventory the server last confirmed (and the junk list).
func save_character() -> void:
	if _have_inventory and Settings.player_id != "":
		CharacterSave.write(Settings.player_id, player_name, inventory, Settings.junk)


func _watch_connection() -> void:
	multiplayer.connected_to_server.connect(_say_hello)
	multiplayer.connection_failed.connect(func() -> void: left.emit("Could not reach the server"))
	multiplayer.server_disconnected.connect(
		func() -> void:
			if not _leaving:
				_heard_ms = 0
				left.emit("The host left" if lobby and not hosting else "The server closed")
	)


## Disconnects cleanly and waits a moment, so the server drops the peer before it would send
## to a closed connection (it logged "Unable to send packet" when a client just quit).
func leave() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_leaving = true
	# No more input packets onto the closing connection.
	NetworkTime.stop()
	if peer is ENetMultiplayerPeer:
		(peer as ENetMultiplayerPeer).get_peer(1).peer_disconnect_later()
	else:
		peer.close()
	await get_tree().create_timer(0.3).timeout


## Captures the mouse for play, unless no_grab keeps it free (a click still captures it).
func _grab() -> void:
	if not no_grab:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Pause menu: back into the game.
func _resume() -> void:
	_pause.visible = false
	_grab()


## Pause menu: disconnects and hands back to the main menu (an empty reason).
func _leave_to_menu() -> void:
	await leave()
	left.emit("")


## Signals of the persistent Net node and the MultiplayerAPI still point at this client's
## lambdas; drop them, so a later game doesn't call into a freed one.
func _exit_tree() -> void:
	save_character()
	for source: Object in [net, multiplayer]:
		if source == null:
			continue
		for info in source.get_signal_list():
			for connection in source.get_signal_connection_list(info.name):
				var callable: Callable = connection.callable
				if callable.get_object() == self:
					source.disconnect(info.name, callable)


func player_count() -> int:
	return _world.players.get_child_count()


func _on_player_spawned(player: SimPlayer) -> void:
	if player.peer_id != multiplayer.get_unique_id():
		_first_seen[player.peer_id] = player.global_position
		return
	me = player
	_objects.me = me
	_map.me = me
	_hud.player = me
	me.controls.reader = _bot_controls if bot else _read_controls
	_rig.target = me
	if look is Vector2:
		_rig.yaw = deg_to_rad((look as Vector2).x)
		_rig.pitch = deg_to_rad((look as Vector2).y)
	if not bot and not _pause.visible:
		_grab()
	if inventory_start:
		get_tree().create_timer(1.0).timeout.connect(_open_inventory)
	if map_start != "":
		_map.span = INF if map_start == "full" else float(map_start)
		_map.visible = true
	entered.emit()


## Asks the server to change the own inventory; the answer comes as a delta.
func send_intent(op: Net.Op, a := 0, b := 0) -> void:
	net.inventory_intent.rpc_id(1, op, a, b)


## Tells the panel and the hotbar what the server last said.
func _show_inventory() -> void:
	_panel.show_inventory(inventory)
	_hud.hotbar.show_inventory(inventory)
	inventory_updated.emit()


## I or Tab: the panel over the game with the mouse free; the game runs on behind it.
func _open_inventory() -> void:
	_panel.visible = true
	_panel.show_inventory(inventory)
	_panel.set_cursor(maxi(_panel.cursor, 0) if inventory_cursor < 0 else inventory_cursor)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_inventory() -> void:
	_panel.visible = false
	_panel.held = -1
	_panel.set_cursor(_panel.cursor)
	_grab()


## E: takes the drop or opens the chest in reach (the server decides; a toast or a delta answers).
func interact() -> void:
	if _objects.focus_id < 0:
		return
	if _objects.focus_is_chest:
		net.open_object.rpc_id(1, _objects.focus_id)
	else:
		net.pickup.rpc_id(1, _objects.focus_id)


func _read_controls(controls: PlayerControls) -> void:
	controls.yaw = _rig.yaw
	controls.pitch = _rig.pitch
	controls.weapon = _wanted_weapon
	controls.move = Vector2.ZERO
	controls.buttons = 0
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	controls.move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	if Input.is_action_pressed(&"jump"):
		controls.buttons |= PlayerControls.Buttons.JUMP
	var held := {
		&"sprint": PlayerControls.Buttons.SPRINT,
		&"attack": PlayerControls.Buttons.ATTACK,
		&"heavy": PlayerControls.Buttons.HEAVY,
		&"block": PlayerControls.Buttons.BLOCK,
		&"roll": PlayerControls.Buttons.ROLL,
	}
	for action: StringName in held:
		if Input.is_action_pressed(action):
			controls.buttons |= held[action]


## Walks a circle and runs through jump, attack, heavy, roll and block on a rhythm, so the
## network test exercises combat and rollback too.
func _bot_controls(controls: PlayerControls) -> void:
	var seconds := (Time.get_ticks_msec() - _started_ms) / 1000.0
	if bot_plan == "combo" or bot_plan == "combo_walk":
		# Looks where --look points and chains light combos, every 4th time a heavy; combo_walk
		# also walks forward and sweeps the camera (rubberband checks: STELLAMORTIS_SNAP_LOG=1).
		var walking := bot_plan == "combo_walk"
		controls.move = Vector2(0.0, 1.0) if walking else Vector2.ZERO
		controls.yaw = _rig.yaw + (sin(seconds * 1.3) * 0.8 if walking else 0.0)
		controls.pitch = _rig.pitch
		controls.weapon = SimPlayer.Weapon.SWORD
		var beat := int(seconds * 5.0)
		var heavy := beat % 40 >= 30
		var b := PlayerControls.Buttons
		controls.buttons = (b.HEAVY if heavy else b.ATTACK) if beat % 2 == 0 else 0
		return
	if bot_plan == "shoot":
		controls.move = Vector2.ZERO
		controls.yaw = _rig.yaw
		controls.pitch = _rig.pitch
		controls.weapon = SimPlayer.Weapon.CROSSBOW
		var b := PlayerControls.Buttons
		controls.buttons = b.BLOCK | (b.ATTACK if fmod(seconds, 1.4) < 1.0 else 0)
		_rig.aiming = true
		return
	controls.move = Vector2(0.0, 1.0)
	controls.yaw = fposmod(seconds * 0.8 + me.peer_id % 7, TAU)
	var b := PlayerControls.Buttons
	controls.buttons = [b.JUMP, b.ATTACK, b.HEAVY, b.ROLL, b.BLOCK, 0][int(seconds * 2.0) % 6]
	# Every other 4 s with the crossbow: draws on ATTACK, aims on BLOCK.
	controls.weapon = int(seconds / 4.0) % 2


func _process(delta: float) -> void:
	_hud.room = room
	var covered := _pause.visible or _map.visible or _panel.visible
	_hud.prompt = _objects.prompt if not covered else ""
	_hud.prompt_color = _objects.prompt_color
	_watch_silence()
	if _snap_log and me != null:
		_log_snaps()
	if me != null:
		var place := Layout.place_at(me.global_position)
		_world.arena.show_place(place)
		_world.arena.follow_up(me.global_position, delta)
		Sounds.ambience(_ambience)
	if me != null and not bot:
		_rig.aiming = (
			me.weapon == SimPlayer.Weapon.CROSSBOW
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			and (Input.is_action_pressed(&"block") or me.action == SimPlayer.Action.DRAW)
		)


## Warns, then leaves, when the server has gone quiet (see _heard_ms).
func _watch_silence() -> void:
	if _heard_ms == 0 or _leaving:
		_hud.warning = ""
		return
	var silent := (Time.get_ticks_msec() - _heard_ms) / 1000.0
	var who := "the host" if lobby and not hosting else "the server"
	if silent >= SILENT_LEAVE:
		_heard_ms = 0
		left.emit("Lost the connection to %s" % who)
	elif silent >= SILENT_WARN:
		_hud.warning = "No word from %s for %d s ..." % [who, int(silent)]
	else:
		_hud.warning = ""


## Prints the own player's moves between ticks that are longer than its speed allows (rollback
## corrections), with the action it is in.
func _log_snaps() -> void:
	if NetworkTime.tick == _snap_tick:
		return
	var at := me.global_position
	if _snap_tick >= 0:
		var ticks := maxi(1, NetworkTime.tick - _snap_tick)
		var moved := at.distance_to(_snap_at)
		var allowed := (me.velocity.length() + 1.0) * ticks / 30.0 + 0.05
		if moved > allowed:
			print(
				(
					"snap %.2f m over %d ticks, action %d time %d attack %d health %.0f tick %d"
					% [
						moved,
						ticks,
						me.action,
						me.action_time,
						me.attack,
						me.health,
						NetworkTime.tick
					]
				)
			)
	_snap_tick = NetworkTime.tick
	_snap_at = at


func _each_second() -> void:
	if me != null:
		net.ping.rpc_id(1, Time.get_ticks_msec())
	if _map.visible and _map.realm_id() != "":
		net.request_cleared_camps.rpc_id(1, _map.realm_id())
	if bot:
		interact()
		_bot_gear()
		_check_bot()


## Exercises the inventory over the network: once its snapshot is in, takes the shield off and
## puts it on again, a second apart (the gear ints then change in rolled back state twice).
func _bot_gear() -> void:
	if me == null or inventory.at(Inventory.Cell.MAIN) == null:
		return
	if _bot_gear_step == 0:
		send_intent(Net.Op.UNEQUIP, Inventory.Cell.OFF)
		_bot_gear_step = 1
	elif _bot_gear_step == 1 and inventory.at(0) != null:
		send_intent(Net.Op.EQUIP, 0)
		_bot_gear_step = 2


## Passes once it ran bot_duration, moved itself and saw every other expected player move.
func _check_bot() -> void:
	for id: int in _first_seen:
		var other := _world.player(id)
		if other and other.global_position.distance_to(_first_seen[id]) > 2.0:
			_seen_moved[id] = true
	var seconds := (Time.get_ticks_msec() - _started_ms) / 1000.0
	if me != null:
		if _bot_start == null:
			_bot_start = me.global_position
		elif me.global_position.distance_to(_bot_start) >= 4.0:
			_bot_moved = true
	# Standing plans (combo, shoot) only have to last.
	var standing := bot_plan == "combo" or bot_plan == "shoot"
	if seconds < bot_duration or not (_bot_moved or standing):
		return
	# The inventory exercise went through: the shield is back on.
	if _bot_gear_step < 2 or inventory.at(Inventory.Cell.OFF) == null:
		return
	if _seen_moved.size() + 1 < bot_expect:
		return
	print("%s: saw %d others move, ping %d ms" % [player_name, _seen_moved.size(), ping_ms])
	await leave()
	get_tree().quit(0)


func _take_screenshot() -> void:
	_overlay.visible = true
	await get_tree().create_timer(screenshot_delay).timeout
	for i in screenshot_frames:
		await RenderingServer.frame_post_draw
		var path := screenshot_path
		if screenshot_frames > 1:
			path = screenshot_path.get_basename() + "_%d.png" % i
		get_viewport().get_texture().get_image().save_png(path)
		print("Saved ", path)
		await get_tree().create_timer(0.05).timeout
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if bot:
		return
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rig.look(motion.screen_relative)
	elif event.is_action_pressed(&"pause") and _panel.visible:
		_close_inventory()
	elif event.is_action_pressed(&"pause") and me != null:
		if _pause.visible:
			_pause.back()
		else:
			_pause.room = room
			_pause.open()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action(&"map") and not event.is_echo() and me != null and map_start == "":
		# Held: the mouse is free for hover and zoom while it is open (the player stands still).
		_map.visible = event.is_pressed() and not _pause.visible
		if _map.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			_grab()
	elif event.is_action_pressed(&"inventory") and me != null and not _pause.visible:
		if _panel.visible:
			_close_inventory()
		elif not _map.visible:
			_open_inventory()
	elif _pause.visible:
		return
	elif Hotbar.cell_for(event) >= 0:
		send_intent(Net.Op.USE, Hotbar.cell_for(event))
	elif _panel.visible:
		_panel.handle_event(event)
	elif event is InputEventMouseButton and event.is_pressed() and me != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"interact"):
		interact()
	elif event.is_action_pressed(&"weapon_1"):
		_wanted_weapon = SimPlayer.Weapon.SWORD
	elif event.is_action_pressed(&"weapon_2"):
		_wanted_weapon = SimPlayer.Weapon.CROSSBOW
	elif event.is_action_pressed(&"weapon_next"):
		_wanted_weapon = 1 - _wanted_weapon
	elif event.is_action_pressed(&"graphics"):
		Graphics.cycle(get_viewport(), _world.arena)
	elif event.is_action_pressed(&"copy_room") and room != "":
		DisplayServer.clipboard_set(room)
		_hud.notice("Room code %s copied" % room)
	elif event.is_action_pressed(&"toggle_debug"):
		_overlay.visible = not _overlay.visible
