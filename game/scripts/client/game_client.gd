class_name GameClient
extends Node3D
## A player's side of the game (PLAN §4.3): sends input every tick, predicts its own player with
## the server's movement code and corrects it from snapshots, and draws everyone else about
## INTERP_TICKS behind the newest snapshot.

signal left(reason: String)

const INTERP_TICKS := 3.0
## Inputs sent per packet: the newest plus the ones before it, in case packets get lost.
const REDUNDANT_INPUTS := 4
## Prediction errors below this are left alone.
const CORRECTION_EPSILON := 0.01
## Corrections larger than this jump instead of being smoothed by physics interpolation.
const TELEPORT_DISTANCE := 2.0
const SNAPSHOTS_KEPT := 32
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
var corrections := 0
var max_error := 0.0

var _my_id := 0
var _placed := false
var _world: Node3D
var _rig: CameraRig
var _overlay: DebugOverlay
var _input_tick := 0
## [PlayerInput, PlayerState after running it], oldest first.
var _history: Array = []
var _pending_snapshot := {}
var _latest_tick := 0
var _render_tick := 0.0
## peer id -> {view: PlayerView, states: Array of [tick, PlayerState], start: Vector3}
var _remote := {}
var _started_ms := 0
var _bot_moved := false
## Bot: ids of other players it has seen move, kept after they leave.
var _seen_moved := {}


func _ready() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_world.add_child(Arena.new(true))
	_rig = CameraRig.new()
	add_child(_rig)
	_overlay = DebugOverlay.new()
	_overlay.client = self
	add_child(_overlay)
	net.welcomed.connect(_on_welcomed)
	net.rejected.connect(func(reason: String) -> void: left.emit(reason))
	net.snapshot_received.connect(func(data: PackedByteArray) -> void: _queue_snapshot(data))
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
	multiplayer.connected_to_server.connect(func() -> void: net.send_hello(player_name))
	multiplayer.connection_failed.connect(func() -> void: left.emit("Could not reach the server"))
	multiplayer.server_disconnected.connect(func() -> void: left.emit("The server closed"))


func player_count() -> int:
	return _remote.size() + (1 if _placed else 0)


func _on_welcomed(id: int) -> void:
	_my_id = id
	me = SimPlayer.new()
	me.peer_id = id
	me.player_name = player_name
	me.add_child(PlayerView.new(player_name, id, false))
	_world.add_child(me)
	me.visible = false
	_rig.target = me
	if not bot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _queue_snapshot(data: PackedByteArray) -> void:
	var snapshot := Net.unpack_snapshot(data)
	if snapshot.tick <= _latest_tick:
		return
	_latest_tick = snapshot.tick
	_pending_snapshot = snapshot
	var players: Dictionary = snapshot.players
	for id: int in players:
		if id != _my_id:
			_remember(id, snapshot.tick, players[id])
	for id: int in _remote.keys():
		if not players.has(id):
			(_remote[id].view as Node).queue_free()
			_remote.erase(id)


func _physics_process(delta: float) -> void:
	if me == null:
		return
	if not _pending_snapshot.is_empty():
		_reconcile(_pending_snapshot, delta)
		_pending_snapshot = {}
	if not _placed:
		return
	_input_tick += 1
	var input := _bot_input() if bot else _read_input()
	input.tick = _input_tick
	input = input.quantized()
	me.step(input, delta)
	_history.append([input, me.get_state()])
	var recent: Array[PlayerInput] = []
	for entry: Array in _history.slice(-REDUNDANT_INPUTS):
		recent.append(entry[0])
	net.send_inputs(Net.pack_inputs(recent))


## Checks the server's state for the last input it ran against what we predicted for it, and
## if they differ, takes the server's and runs the newer inputs again.
func _reconcile(snapshot: Dictionary, delta: float) -> void:
	var server_state: PlayerState = snapshot.players.get(_my_id)
	if server_state == null:
		return
	var ack: int = snapshot.ack
	if not _placed:
		me.apply_state(server_state)
		me.reset_physics_interpolation()
		me.visible = true
		_placed = true
		_input_tick = ack
		return
	while not _history.is_empty() and (_history[0][0] as PlayerInput).tick < ack:
		_history.pop_front()
	var predicted: PlayerState = null
	if not _history.is_empty() and (_history[0][0] as PlayerInput).tick == ack:
		predicted = _history.pop_front()[1]
	if predicted == null:
		return
	var error := predicted.error_to(server_state)
	if error <= CORRECTION_EPSILON:
		return
	corrections += 1
	max_error = maxf(max_error, error)
	var before := me.global_position
	me.apply_state(server_state)
	for entry: Array in _history:
		me.step(entry[0], delta)
		entry[1] = me.get_state()
	if before.distance_to(me.global_position) > TELEPORT_DISTANCE:
		me.reset_physics_interpolation()


func _remember(id: int, tick: int, state: PlayerState) -> void:
	if not _remote.has(id):
		var view := PlayerView.new("Player %d" % id, id, true)
		view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_world.add_child(view)
		_remote[id] = {view = view, states = [], start = state.position}
	var remote: Dictionary = _remote[id]
	var states: Array = remote.states
	states.append([tick, state])
	if states.size() > SNAPSHOTS_KEPT:
		states.pop_front()
	if state.position.distance_to(remote.start) > 2.0:
		_seen_moved[id] = true


func _process(delta: float) -> void:
	_render_tick += delta * Engine.physics_ticks_per_second
	var target := _latest_tick - INTERP_TICKS
	if absf(target - _render_tick) > 10.0:
		_render_tick = target
	else:
		_render_tick += (target - _render_tick) * minf(1.0, delta * 2.0)
	for remote: Dictionary in _remote.values():
		_place_remote(remote)


func _place_remote(remote: Dictionary) -> void:
	var states: Array = remote.states
	if states.is_empty():
		return
	var a: Array = states[0]
	var b: Array = states[0]
	for entry: Array in states:
		if entry[0] <= _render_tick:
			a = entry
			b = entry
		else:
			b = entry
			break
	var from: PlayerState = a[1]
	var to: PlayerState = b[1]
	var weight := 0.0 if b[0] == a[0] else clampf((_render_tick - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	var up := from.up.slerp(to.up, weight).normalized()
	var facing := SimPlayer._tangent(from.facing.slerp(to.facing, weight), up)
	(remote.view as Node3D).global_transform = Transform3D(
		SimPlayer.frame(up, facing), from.position.lerp(to.position, weight)
	)


func _read_input() -> PlayerInput:
	var input := PlayerInput.new()
	input.yaw = _rig.yaw
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return input
	input.move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	if Input.is_action_pressed(&"jump"):
		input.buttons |= PlayerInput.Buttons.JUMP
	if Input.is_action_pressed(&"sprint"):
		input.buttons |= PlayerInput.Buttons.SPRINT
	return input


## Walks a circle and jumps now and then.
func _bot_input() -> PlayerInput:
	var input := PlayerInput.new()
	var seconds := (Time.get_ticks_msec() - _started_ms) / 1000.0
	input.move = Vector2(0.0, 1.0)
	input.yaw = seconds * 0.8 + _my_id % 7
	if int(seconds * 2.0) % 5 == 0:
		input.buttons |= PlayerInput.Buttons.JUMP
	if me.global_position.length() > 3.0:
		_bot_moved = true
	return input


func _each_second() -> void:
	if multiplayer.multiplayer_peer != null and _placed:
		net.send_ping()
	if bot:
		_check_bot()


## Passes once it ran bot_duration, moved itself, saw every other expected player move and its
## prediction stayed close to the server.
func _check_bot() -> void:
	var seconds := (Time.get_ticks_msec() - _started_ms) / 1000.0
	if seconds < bot_duration or not _placed or not _bot_moved:
		return
	var moved := _seen_moved.size()
	if moved + 1 < bot_expect:
		return
	print(
		(
			"%s: saw %d others move, %d corrections (max %.3f m), ping %d ms"
			% [player_name, moved, corrections, max_error, ping_ms]
		)
	)
	get_tree().quit(0 if max_error < 0.5 else 3)


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
