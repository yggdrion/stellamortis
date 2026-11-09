class_name LobbyClient
extends Node
## Player host (PLAN §4.7): finds the game server through the lobby (lobby/) and sets up the
## WebRTC connections. The lobby gives out a room code and relays WebRTC offers, answers and
## ICE candidates; game traffic then goes peer to peer (or through the TURN relay). Message
## format: lobby/src/rooms.ts.
##
## Server side (host): opens a room on a WebRTCMultiplayerPeer server and keeps the lobby
## socket open, pinging, for as long as the server runs, so friends can join any time. Each
## guest gets its own WebRTCPeerConnection under the peer id the lobby gave it, and the server
## makes the offer. Client side (join): makes a WebRTCMultiplayerPeer client for the id it was
## given, connects to the server (peer 1) and closes the lobby socket once connected.

## Client: the multiplayer peer to use, handed out as soon as it exists, so the multiplayer
## API polls it while it connects.
signal peer_created(peer: WebRTCMultiplayerPeer)
## Server: the room is open under this code.
signal room_opened(code: String)
## Something went wrong; reason is for the player. On the server the lobby is gone then, but
## players already connected stay.
signal failed(reason: String)
## Client: the WebRTC link to the server is up. The lobby is closed then.
signal connected

## Where a client's join stands, for the reason it gives when it fails.
enum Stage { LOBBY, SIGNALING, ICE, WELCOME }

## The game's default lobby; --lobby=URL picks another.
const DEFAULT_URL := "wss://lobby.r4b2.de/ws"
## The lobby message format (lobby/src/server.ts PROTOCOL), apart from Net.PROTOCOL_VERSION
## so game-only changes need no lobby redeploy.
const PROTOCOL := 1
const SERVER_ID := 1
## Server: seconds between heartbeats; the lobby drops a room after 60 s without one.
const PING_INTERVAL := 20.0
## Seconds a guest's connection may take before it is given up.
const CONNECT_TIMEOUT := 30.0
## Client: seconds from the lobby's `joined` to the server's offer.
const SIGNAL_TIMEOUT := 10.0
## Readable names of the WebRTCPeerConnection state enums, for the join log.
const CONNECTION_NAMES := ["new", "connecting", "connected", "disconnected", "failed", "closed"]
const GATHERING_NAMES := ["new", "gathering", "complete"]
const SIGNALING_NAMES := [
	"stable",
	"have-local-offer",
	"have-remote-offer",
	"have-local-pranswer",
	"have-remote-pranswer",
	"closed"
]

var code := ""
## Debug (--relay-only): sends and accepts only relay candidates, so the connection has to go
## through the TURN server.
var relay_only := false
## Client: the server's ICE candidates as "<type> <address>", for the debug overlay. Godot
## exposes no WebRTC stats, so this is what the server offered, not the pair that won: "host"
## candidates on the same network usually mean a direct LAN link, only "relay" goes through
## TURN.
var remote_candidates := PackedStringArray()
## Our own ICE candidates as "<type> <address>", filled as they are gathered.
var local_candidates := PackedStringArray()
## The trace of the join steps (user://logs/join-<role>.log); made on host/join if not set.
var log: JoinLog
var _ws := WebSocketPeer.new()
## The first message, sent once the socket is open.
var _hello := {}
var _rtc: WebRTCMultiplayerPeer
var _ice: Array = []
var _hosting := false
## Server: guest id -> seconds left to connect, for connections still being set up.
var _pending := {}
var _ping_due := PING_INTERVAL
## Client: seconds left to connect, counting once the lobby gave us an id.
var _connect_left := CONNECT_TIMEOUT
var _done := false
## Client: where the join stands, and seconds left to get the server's offer.
var _stage := Stage.LOBBY
var _signal_left := SIGNAL_TIMEOUT
## Peer id -> last logged "connection gathering signaling" state names, to log changes only.
var _seen_states := {}


## Server: opens a room for rtc, a WebRTCMultiplayerPeer in server mode. Hosting again after a
## failure opens a new room for the same peer, so connected players stay.
func host(url: String, rtc: WebRTCMultiplayerPeer) -> void:
	_hosting = true
	_rtc = rtc
	_ensure_log()
	_open(url, {"type": "host", "protocol": PROTOCOL})


## Client: joins the room with this code.
func join(url: String, room_code: String) -> void:
	_ensure_log()
	_open(url, {"type": "join", "code": room_code.strip_edges().to_upper(), "protocol": PROTOCOL})


func _open(url: String, hello: Dictionary) -> void:
	_hello = hello
	_log("lobby connecting", url)
	var err := _ws.connect_to_url(url)
	if err != OK:
		_fail("Could not reach the lobby (%s)" % error_string(err))


func _process(delta: float) -> void:
	if _done:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _hello.is_empty():
		_log("lobby open")
		_log("hello sent", str(_hello.get("type")))
		_send(_hello)
		_hello = {}
	while _ws.get_available_packet_count() > 0:
		var msg: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if msg is Dictionary:
			handle(msg)
	if _done:
		return
	if _hosting:
		_tick_server(delta)
	elif _rtc != null:
		_tick_client(delta)
	if not _done and state == WebSocketPeer.STATE_CLOSED:
		_fail("Lost the lobby" if code != "" else "Could not reach the lobby")


func _tick_server(delta: float) -> void:
	if code != "":
		_ping_due -= delta
		if _ping_due <= 0.0:
			_ping_due = PING_INTERVAL
			_send({"type": "ping"})
	for id: int in _pending.keys():
		var connection := _connection(id)
		var connection_state := (
			connection.get_connection_state() if connection else WebRTCPeerConnection.STATE_CLOSED
		)
		_pending[id] -= delta
		_watch_states(id, connection)
		if connection_state == WebRTCPeerConnection.STATE_CONNECTED:
			_log("connected", turn_note(local_candidates, remote_candidates), id)
			_pending.erase(id)
		elif (
			_pending[id] <= 0.0
			or connection_state == WebRTCPeerConnection.STATE_FAILED
			or connection_state == WebRTCPeerConnection.STATE_CLOSED
		):
			print("lobby: guest %d never connected" % id)
			_log("gave up", "guest never connected", id)
			_drop(id)


func _tick_client(delta: float) -> void:
	var connection := _connection(SERVER_ID)
	var connection_state := connection.get_connection_state() if connection else -1
	if connection != null:
		_watch_states(SERVER_ID, connection)
	if connection_state == WebRTCPeerConnection.STATE_CONNECTED:
		# The lobby has done its part.
		_log("connected", turn_note(local_candidates, remote_candidates), SERVER_ID)
		_ws.close()
		_done = true
		_stage = Stage.WELCOME
		connected.emit()
		return
	if _stage == Stage.SIGNALING:
		_signal_left -= delta
		if _signal_left <= 0.0:
			_fail(failure_reason(_stage, connection_state, false, false))
		return
	_connect_left -= delta
	if connection_state == WebRTCPeerConnection.STATE_FAILED or _connect_left <= 0.0:
		_fail(failure_reason(_stage, connection_state, _turn_offered(), _relay_gathered()))


## One message from the lobby.
func handle(msg: Dictionary) -> void:
	match str(msg.get("type")):
		"hosted":
			code = str(msg.get("code"))
			_ice = msg.get("ice", [])
			_log("hosted", "ice " + ice_kinds(_ice))
			room_opened.emit(code)
		"joined":
			code = str(msg.get("code"))
			_ice = msg.get("ice", [])
			_log("joined", "id %d ice %s" % [int(msg.get("id")), ice_kinds(_ice)])
			_stage = Stage.SIGNALING
			_rtc = WebRTCMultiplayerPeer.new()
			_rtc.create_client(int(msg.get("id")))
			if _add_connection(SERVER_ID):
				peer_created.emit(_rtc)
		"guest":
			# The server makes the offer.
			var id := int(msg.get("id"))
			_log("guest", "creating offer", id)
			if _hosting and _add_connection(id):
				_pending[id] = CONNECT_TIMEOUT
				_connection(id).create_offer()
		"left":
			# Not a reason to drop the guest: one that got through closes its socket at once,
			# often before this side sees the connection up. One that gave up times out.
			_log("left", "id %d" % int(msg.get("id", 0)), int(msg.get("id", 0)))
		"signal":
			_on_signal(int(msg.get("from", 0)), msg.get("data", {}))
		"error":
			var reason := str(msg.get("reason", "lobby error"))
			_log("lobby error", reason)
			_fail(reason.left(1).to_upper() + reason.substr(1))


func _add_connection(id: int) -> bool:
	var connection := WebRTCPeerConnection.new()
	var err := connection.initialize({"iceServers": _ice})
	if err != OK:
		_fail("WebRTC is not available (%s)" % error_string(err))
		return false
	connection.session_description_created.connect(
		func(kind: String, sdp: String) -> void:
			connection.set_local_description(kind, sdp)
			_log("%s sent" % kind, "", id)
			_signal(id, {"kind": kind, "sdp": sdp})
	)
	connection.ice_candidate_created.connect(
		func(mid: String, index: int, sdp: String) -> void:
			var summary := candidate_summary(sdp)
			if relay_only and not summary.begins_with("relay "):
				_log("candidate skipped", summary, id)
				return
			_log("candidate sent", summary, id)
			if summary != "" and not summary in local_candidates:
				local_candidates.append(summary)
			_signal(id, {"kind": "candidate", "mid": mid, "index": index, "sdp": sdp})
	)
	_rtc.add_peer(connection, id)
	return true


func _connection(id: int) -> WebRTCPeerConnection:
	if not _rtc.has_peer(id):
		return null
	return _rtc.get_peer(id).get("connection")


func _drop(id: int) -> void:
	_pending.erase(id)
	if _rtc.has_peer(id):
		_rtc.remove_peer(id)


## Sends signal data to the peer with this id: the guest from the server, the server from a
## guest (the lobby knows).
func _signal(id: int, data: Dictionary) -> void:
	if _hosting:
		_send({"type": "signal", "to": id, "data": data})
	else:
		_send({"type": "signal", "data": data})


func _on_signal(from: int, data: Variant) -> void:
	if not data is Dictionary:
		return
	var connection := _connection(from if _hosting else SERVER_ID) if _rtc else null
	if connection == null:
		return
	match str(data.get("kind")):
		"offer", "answer":
			_log("%s received" % data["kind"], "", from)
			if not _hosting and _stage == Stage.SIGNALING:
				_stage = Stage.ICE
			# Setting the server's offer makes the guest create its answer.
			connection.set_remote_description(str(data["kind"]), str(data.get("sdp")))
		"candidate":
			var sdp := str(data.get("sdp"))
			var summary := candidate_summary(sdp)
			if relay_only and not summary.begins_with("relay "):
				_log("candidate ignored", summary, from)
				return
			connection.add_ice_candidate(str(data.get("mid")), int(data.get("index", 0)), sdp)
			_log("candidate received", summary, from)
			if not _hosting and summary != "" and not summary in remote_candidates:
				remote_candidates.append(summary)


## "<type> <address>" from an ICE candidate line
## ("candidate:<foundation> <component> <proto> <priority> <address> <port> typ <type> ..."),
## or "" if it doesn't parse.
static func candidate_summary(sdp: String) -> String:
	var fields := sdp.split(" ", false)
	var typ := fields.find("typ")
	if typ < 6 or typ + 1 >= fields.size():
		return ""
	return "%s %s" % [fields[typ + 1], fields[4]]


## "stun,turn" from the urls of ICE servers, "none" without any. Never the credentials.
static func ice_kinds(ice: Array) -> String:
	var kinds: Array[String] = []
	for server: Variant in ice:
		if not server is Dictionary:
			continue
		var urls: Variant = server.get("urls", [])
		for url: Variant in urls if urls is Array else [urls]:
			var kind := str(url).split(":")[0].trim_suffix("s")
			if kind in ["stun", "turn"] and not kind in kinds:
				kinds.append(kind)
	kinds.sort()
	return ",".join(kinds) if not kinds.is_empty() else "none"


## The reason shown to the player for a join that failed in this stage. connection_state is
## a WebRTCPeerConnection.STATE_*; turn_offered whether the lobby gave TURN servers and
## relay_gathered whether a relay candidate was found.
static func failure_reason(
	stage: Stage, _connection_state: int, turn_offered: bool, relay_gathered: bool
) -> String:
	match stage:
		Stage.SIGNALING:
			return "The host did not answer through the lobby (signaling timeout)"
		Stage.ICE:
			if turn_offered and not relay_gathered:
				return "Could not reach the TURN relay, so no connection to the host"
			return "No connection to the host, even through the relay (ICE failed)"
		Stage.WELCOME:
			return "Connected, but the host never let us in"
	return "Could not reach the lobby"


func _turn_offered() -> bool:
	return "turn" in ice_kinds(_ice)


func _relay_gathered() -> bool:
	return _relay_count(local_candidates) > 0


## Godot gives no selected candidate pair: TURN is inferred when every candidate on one side
## is a relay.
static func turn_note(local: PackedStringArray, remote: PackedStringArray) -> String:
	for side in [local, remote]:
		if not side.is_empty() and side.size() == _relay_count(side):
			return "turn used (inferred)"
	return "direct or stun"


static func _relay_count(candidates: PackedStringArray) -> int:
	var n := 0
	for c in candidates:
		if c.begins_with("relay "):
			n += 1
	return n


## Logs the connection, gathering and signaling state names of a peer when one changed.
func _watch_states(id: int, connection: WebRTCPeerConnection) -> void:
	var text := (
		"connection=%s gathering=%s signaling=%s"
		% [
			_name_of(CONNECTION_NAMES, connection.get_connection_state()),
			_name_of(GATHERING_NAMES, connection.get_gathering_state()),
			_name_of(SIGNALING_NAMES, connection.get_signaling_state()),
		]
	)
	if _seen_states.get(id, "") != text:
		_seen_states[id] = text
		_log("state", text, id)


static func _name_of(names: Array, index: int) -> String:
	return names[index] if index >= 0 and index < names.size() else str(index)


func _ensure_log() -> void:
	if log == null:
		log = JoinLog.new("server" if _hosting else "client")


func _log(what: String, detail := "", peer := 0) -> void:
	_ensure_log()
	log.step(what, detail, code, peer)


## For tests: acts as the host of rtc without opening a lobby socket.
func host_for_test(rtc: WebRTCMultiplayerPeer) -> void:
	_hosting = true
	_rtc = rtc


func _send(msg: Dictionary) -> void:
	_ws.send_text(JSON.stringify(msg))


func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	_log("gave up", reason)
	_ws.close()
	failed.emit(reason)
