extends Node
## Entry point. Picks the role from the user args (after `--`):
##   --server --port=N [--solo]     headless game server; --solo: exits with its player
##     [--spawn=X,Y,Z]              debug: spawn players there (a solo client passes it on)
##     [--encounter=boss]           debug: start with the mobs dead (a solo client passes it on)
##   --connect=host:port            client joining a running server over ENet
##   --bot [--expect=N]             headless test client (see GameClient._check_bot)
##     [--bot-plan=shoot|lock]      shoot: fire the crossbow where --look points;
##                                  lock: lock on and strafe around the target
##     [--duration=SECS]
##   --name=NAME                    player name
##   --windowed                     start in a window instead of fullscreen
##   --screenshot=PATH              save a PNG of the screen after a few seconds, then quit
##     [--delay=SECONDS]            how long to wait first (default 4)
##     [--frames=N]                 take N, 50 ms apart (PATH_0.png, PATH_1.png, ...)
##   --graphics=low|medium|high|ultra   graphics preset for this run (not saved)
##   --look=YAW,PITCH               start the camera there (degrees, yaw 0 looks along -Z)
##   (none)                         solo: spawns a local --solo server and joins it

const DEFAULT_PORT := 17777

var _args := {}
var _server_pid := 0

@onready var _net: Net = $Net


func _ready() -> void:
	_args = parse_args(OS.get_cmdline_user_args())
	if _args.has("server"):
		var server := GameServer.new()
		server.net = _net
		server.solo = _args.has("solo")
		if _args.has("spawn"):
			var p := (_args["spawn"] as String).split(",")
			server.spawn_at = Vector3(float(p[0]), float(p[1]), float(p[2]))
		server.skip_to_boss = _args.get("encounter", "") == "boss"
		add_child(server)
		server.start(int(_args.get("port", DEFAULT_PORT)))
		return
	Controls.setup()
	if not _args.has("windowed") and not _args.has("bot") and not OS.is_debug_build():
		get_window().mode = Window.MODE_FULLSCREEN
	var client := GameClient.new()
	client.net = _net
	client.bot = _args.has("bot")
	client.bot_expect = int(_args.get("expect", "1"))
	client.bot_duration = float(_args.get("duration", "5"))
	client.bot_plan = _args.get("bot-plan", "")
	client.player_name = _args.get("name", "player")
	client.screenshot_path = _args.get("screenshot", "")
	client.screenshot_delay = float(_args.get("delay", "4"))
	client.screenshot_frames = int(_args.get("frames", "1"))
	client.graphics = _args.get("graphics", "")
	if _args.has("look"):
		var parts := (_args["look"] as String).split(",")
		client.look = Vector2(float(parts[0]), float(parts[1]) if parts.size() > 1 else -15.0)
	client.left.connect(_on_left)
	add_child(client)
	if _args.has("connect"):
		var parts: PackedStringArray = (_args["connect"] as String).rsplit(":", true, 1)
		client.join(parts[0], int(parts[1]) if parts.size() > 1 else DEFAULT_PORT)
	else:
		var port := _free_port()
		var server_args: PackedStringArray = ["--solo", "--port=%d" % port]
		if _args.has("spawn"):
			server_args.append("--spawn=" + _args["spawn"])
		if _args.has("encounter"):
			server_args.append("--encounter=" + _args["encounter"])
		_server_pid = _spawn_server(server_args)
		# The server needs a moment to open its port; ENet retries the connect meanwhile.
		client.join("127.0.0.1", port)


func _on_left(reason: String) -> void:
	print("Left the game: ", reason)
	get_tree().quit(2 if _args.has("bot") else 0)


func _exit_tree() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		var full := get_window().mode == Window.MODE_FULLSCREEN
		get_window().mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN


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
