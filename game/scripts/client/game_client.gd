class_name GameClient
extends Node3D
## A player's side of the game (PLAN §4.3). netfox predicts the own player from its input and
## rolls it back on server state, and interpolates every player between ticks; this node fills
## the input, follows the own player with the camera and runs the bot and screenshot modes.

signal left(reason: String)

const SCREENSHOT_DELAY := 4.0

var net: Net
var player_name := "player"
var bot := false
## Bot: players (itself included) it has to see move before it may pass.
var bot_expect := 1
## Bot: seconds to run at least.
var bot_duration := 5.0
## Saves a PNG of the screen here after SCREENSHOT_DELAY seconds, then quits (visual checks).
var screenshot_path := ""

var me: SimPlayer
var ping_ms := 0
var server_tps := 0.0
var server_tick_ms := 0.0

var _world: World
var _rig: CameraRig
var _overlay: DebugOverlay
var _started_ms := 0
## Bot: peer id -> where it first saw that player; ids it saw move are in _seen_moved.
var _first_seen := {}
var _seen_moved := {}


func _init() -> void:
	name = "Game"


func _ready() -> void:
	_world = World.new(true)
	add_child(_world)
	_world.player_spawned.connect(_on_player_spawned)
	_rig = CameraRig.new()
	add_child(_rig)
	_overlay = DebugOverlay.new()
	_overlay.client = self
	add_child(_overlay)
	net.rejected.connect(func(reason: String) -> void: left.emit(reason))
	net.ponged.connect(func(sent: int) -> void: ping_ms = Time.get_ticks_msec() - sent)
	net.server_stats_received.connect(
		func(tps: float, tick_ms: float) -> void:
			server_tps = tps
			server_tick_ms = tick_ms
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
	multiplayer.connected_to_server.connect(
		func() -> void: net.hello.rpc_id(1, Net.PROTOCOL_VERSION, player_name)
	)
	multiplayer.connection_failed.connect(func() -> void: left.emit("Could not reach the server"))
	multiplayer.server_disconnected.connect(func() -> void: left.emit("The server closed"))


func player_count() -> int:
	return _world.players.get_child_count()


func _on_player_spawned(player: SimPlayer) -> void:
	if player.peer_id != multiplayer.get_unique_id():
		_first_seen[player.peer_id] = player.global_position
		return
	me = player
	me.controls.reader = _bot_controls if bot else _read_controls
	_rig.target = me
	if not bot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _read_controls(controls: PlayerControls) -> void:
	controls.yaw = _rig.yaw
	controls.move = Vector2.ZERO
	controls.buttons = 0
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	controls.move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	if Input.is_action_pressed(&"jump"):
		controls.buttons |= PlayerControls.Buttons.JUMP
	if Input.is_action_pressed(&"sprint"):
		controls.buttons |= PlayerControls.Buttons.SPRINT


## Walks a circle and jumps now and then.
func _bot_controls(controls: PlayerControls) -> void:
	var seconds := (Time.get_ticks_msec() - _started_ms) / 1000.0
	controls.move = Vector2(0.0, 1.0)
	controls.yaw = fposmod(seconds * 0.8 + me.peer_id % 7, TAU)
	controls.buttons = PlayerControls.Buttons.JUMP if int(seconds * 2.0) % 5 == 0 else 0


func _each_second() -> void:
	if me != null:
		net.ping.rpc_id(1, Time.get_ticks_msec())
	if bot:
		_check_bot()


## Passes once it ran bot_duration, moved itself and saw every other expected player move.
func _check_bot() -> void:
	for id: int in _first_seen:
		var other := _world.player(id)
		if other and other.global_position.distance_to(_first_seen[id]) > 2.0:
			_seen_moved[id] = true
	var seconds := (Time.get_ticks_msec() - _started_ms) / 1000.0
	if seconds < bot_duration or me == null or me.global_position.length() < 4.0:
		return
	if _seen_moved.size() + 1 < bot_expect:
		return
	print("%s: saw %d others move, ping %d ms" % [player_name, _seen_moved.size(), ping_ms])
	get_tree().quit(0)


func _take_screenshot() -> void:
	_overlay.visible = true
	await get_tree().create_timer(SCREENSHOT_DELAY).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(screenshot_path)
	print("Saved ", screenshot_path)
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if bot:
		return
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rig.look(motion.screen_relative)
	elif event.is_action_pressed(&"release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and me != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"toggle_debug"):
		_overlay.visible = not _overlay.visible
