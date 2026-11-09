extends Node
## Entry point. Picks the role from the user args (after `--`):
##   --server --port=N [--solo]     headless game server; --solo: exits with its player
##     [--spawn=X,Y,Z]              debug: spawn players there (a solo client passes it on)
##     [--encounter=boss]           debug: start with the mobs dead (a solo client passes it on)
##     [--lobby=URL [--room-file=PATH]]   instead of the port: open a room in this lobby and
##                                  take players over WebRTC; the code goes to PATH
##   --connect=host:port            client joining a running server over ENet
##   --host                         spawns a local server with a lobby room and joins it by code
##   --join=CODE                    client joining a lobby room over WebRTC
##   --lobby=URL                    lobby for --host and --join (LobbyClient.DEFAULT_URL)
##     [--relay-only]               debug: connect through the TURN relay only
##   --bot [--expect=N]             headless test client (see GameClient._check_bot)
##     [--bot-plan=shoot]           shoot: fire the crossbow where --look points
##     [--duration=SECS]
##   --solo                         solo: spawns a local --solo server and joins it
##   --name=NAME                    player name (instead of the saved one)
##   --windowed                     start in a window instead of fullscreen (or the saved mode)
##   --screenshot=PATH              save a PNG of the screen after a few seconds, then quit
##     [--delay=SECONDS]            how long to wait first (default 4)
##     [--frames=N]                 take N, 50 ms apart (PATH_0.png, PATH_1.png, ...)
##   --graphics=low|medium|high|ultra   graphics preset for this run (not saved)
##   --look=YAW,PITCH               start the camera there (degrees, yaw 0 looks along -Z)
##   --bench=N                      time N simulated players and the enemies per tick, then quit
##   (none of the above)            the main menu (MainMenu); --spawn, --encounter, --look and
##                                  --screenshot without a role mean solo, as before M11

const DEFAULT_PORT := 17777
## Seconds the host waits for its server to open a room.
const ROOM_TIMEOUT := 20.0

## Flags that start a game right away instead of the menu.
const DIRECT := [
	"connect", "join", "host", "bot", "solo", "screenshot", "spawn", "encounter", "look"
]

var _args := {}
var _server_pid := 0
var _client: GameClient
var _menu: MainMenu
## Discord Rich Presence, for players only (not bots, servers or screenshots).
var _presence: Presence

@onready var _net: Net = $Net


func _ready() -> void:
	_args = parse_args(OS.get_cmdline_user_args())
	if _args.has("bench"):
		var bench := Bench.new()
		bench.players = int(_args["bench"])
		add_child(bench)
		return
	if _args.has("server"):
		var server := GameServer.new()
		server.net = _net
		server.solo = _args.has("solo")
		if _args.has("spawn"):
			var p := (_args["spawn"] as String).split(",")
			server.spawn_at = Vector3(float(p[0]), float(p[1]), float(p[2]))
		server.skip_to_boss = _args.get("encounter", "") == "boss"
		server.lobby_url = _args.get("lobby", "")
		server.room_file = _args.get("room-file", "")
		add_child(server)
		server.start(int(_args.get("port", DEFAULT_PORT)))
		return
	Controls.setup()
	if not _args.has("bot") and not _args.has("screenshot"):
		_presence = Presence.new()
		add_child(_presence)
	Settings.load_saved()
	Graphics.load_saved()
	if not _args.has("windowed") and not _args.has("bot") and not OS.is_debug_build():
		Settings.apply_window(get_window())
	for flag: String in DIRECT:
		if _args.has(flag):
			_start(_direct_mode())
			return
	_show_menu("")


## The mode the command line asks for.
func _direct_mode() -> String:
	for mode: String in ["connect", "join", "host"]:
		if _args.has(mode):
			return mode
	return "solo"


func _show_menu(message: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = MainMenu.new()
	_menu.message = message
	_menu.chosen.connect(_start)
	add_child(_menu)


## Starts a game: "solo", "host", "join" (code from the menu or --join) or "connect".
func _start(mode: String, code := "") -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
	var client := GameClient.new()
	client.net = _net
	client.bot = _args.has("bot")
	client.bot_expect = int(_args.get("expect", "1"))
	client.bot_duration = float(_args.get("duration", "5"))
	client.bot_plan = _args.get("bot-plan", "")
	client.player_name = _args.get("name", Settings.player_name)
	client.screenshot_path = _args.get("screenshot", "")
	client.screenshot_delay = float(_args.get("delay", "4"))
	client.screenshot_frames = int(_args.get("frames", "1"))
	client.graphics = _args.get("graphics", "")
	client.relay_only = _args.has("relay-only")
	client.hosting = mode == "host"
	client.mode = mode
	if _args.has("look"):
		var parts := (_args["look"] as String).split(",")
		client.look = Vector2(float(parts[0]), float(parts[1]) if parts.size() > 1 else -15.0)
	client.left.connect(_on_left)
	_client = client
	add_child(client)
	match mode:
		"connect":
			var parts: PackedStringArray = (_args["connect"] as String).rsplit(":", true, 1)
			client.join(parts[0], int(parts[1]) if parts.size() > 1 else DEFAULT_PORT)
		"join":
			client.join_room(_lobby_url(), code if code != "" else _args["join"])
		"host":
			_host(client)
		_:
			var port := _free_port()
			var server_args: PackedStringArray = ["--solo", "--port=%d" % port]
			server_args.append_array(_debug_args())
			_server_pid = _spawn_server(server_args)
			# The server needs a moment to open its port; ENet retries the connect meanwhile.
			client.join("127.0.0.1", port)


## Starts a local server that opens a lobby room, waits for its code and joins it like any
## friend would: in player host everyone, the host too, uses WebRTC (one peer type per
## MultiplayerAPI).
func _host(client: GameClient) -> void:
	var lobby := _lobby_url()
	var room_file := OS.get_user_data_dir().path_join("host_room_%d.txt" % OS.get_process_id())
	DirAccess.remove_absolute(room_file)
	var server_args: PackedStringArray = ["--solo", "--lobby=" + lobby, "--room-file=" + room_file]
	server_args.append_array(_debug_args())
	_server_pid = _spawn_server(server_args)
	var waited := 0.0
	while waited < ROOM_TIMEOUT:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
		# Left to the menu meanwhile.
		if client != _client:
			return
		var text := FileAccess.get_file_as_string(room_file).strip_edges()
		if text.begins_with("!"):
			_on_left("Could not open a room: " + text.substr(1))
			return
		if text != "":
			DirAccess.remove_absolute(room_file)
			print("Hosting room ", text)
			client.join_room(lobby, text)
			return
	_on_left("The local server did not open a room")


## Debug args a client passes on to the server it spawns.
func _debug_args() -> PackedStringArray:
	var passed := PackedStringArray()
	for key: String in ["spawn", "encounter"]:
		if _args.has(key):
			passed.append("--%s=%s" % [key, _args[key]])
	return passed


func _lobby_url() -> String:
	return _args.get("lobby", LobbyClient.DEFAULT_URL)


## The game ended: bots quit (exit 2 on failure), players go back to the menu with the
## reason ("" when they left themselves).
func _on_left(reason: String) -> void:
	print("Left the game: ", reason)
	if _args.has("bot"):
		get_tree().quit(2)
		return
	_back_to_menu.call_deferred(reason)


func _back_to_menu(reason: String) -> void:
	if _client == null:
		return
	var client := _client
	_client = null
	await client.leave()
	NetworkTime.stop()
	remove_child(client)
	client.free()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_stop_server()
	_show_menu(reason)


func _stop_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = 0


func _process(delta: float) -> void:
	if _presence:
		_presence.follow(_client, delta)


func _exit_tree() -> void:
	_stop_server()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		Settings.fullscreen = get_window().mode != Window.MODE_FULLSCREEN
		Settings.apply_window(get_window())
		Settings.save()


## "--key=value" → {key: value}, "--flag" → {flag: ""}.
static func parse_args(user_args: PackedStringArray) -> Dictionary:
	var args := {}
	for arg in user_args:
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args


## Starts this same executable as a headless server. Returns its pid.
func _spawn_server(server_args: PackedStringArray) -> int:
	var cmd: PackedStringArray = ["--headless"]
	# From source the executable is the Godot binary, which needs the project path.
	if not OS.has_feature("template"):
		cmd.append_array(["--path", ProjectSettings.globalize_path("res://")])
	cmd.append_array(["--", "--server"])
	cmd.append_array(server_args)
	return OS.create_process(OS.get_executable_path(), cmd)


func _free_port() -> int:
	var udp := PacketPeerUDP.new()
	for i in 20:
		var port := randi_range(20000, 60000)
		if udp.bind(port) == OK:
			udp.close()
			return port
	return DEFAULT_PORT
