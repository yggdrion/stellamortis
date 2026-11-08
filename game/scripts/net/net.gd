class_name Net
extends Node
## The one node both sides talk through, at /root/Main/Net on server and client so the RPCs
## line up. GameServer and GameClient call the RPCs and listen to the signals. With lag_ms set
## (client only, --lag), every message in both directions waits lag_ms / 2, to test prediction.

# Server side.
signal hello_received(peer_id: int, version: int, player_name: String)
signal inputs_received(peer_id: int, data: PackedByteArray)
signal pinged(peer_id: int, sent_ms: int)
# Client side.
signal welcomed(peer_id: int)
signal rejected(reason: String)
signal snapshot_received(data: PackedByteArray)
signal ponged(sent_ms: int)
signal server_stats_received(tps: float, tick_ms: float)

## Bump on any change to the RPCs below or their payloads.
const PROTOCOL_VERSION := 1

## Fake round-trip latency in ms, split evenly between sending and receiving.
var lag_ms := 0
## [release_ms, Callable] in release order.
var _delayed: Array = []


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	while not _delayed.is_empty() and _delayed[0][0] <= now:
		(_delayed.pop_front()[1] as Callable).call()


## Runs action now, or after half the fake lag.
func later(action: Callable) -> void:
	if lag_ms <= 0:
		action.call()
		return
	_delayed.append([Time.get_ticks_msec() + lag_ms / 2, action])


@rpc("any_peer", "reliable")
func hello(version: int, player_name: String) -> void:
	hello_received.emit(multiplayer.get_remote_sender_id(), version, player_name)


@rpc("authority", "reliable")
func welcome(peer_id: int) -> void:
	later(func() -> void: welcomed.emit(peer_id))


@rpc("authority", "reliable")
func reject(reason: String) -> void:
	rejected.emit(reason)


## The last few PlayerInputs (newest last), so one lost packet loses nothing.
@rpc("any_peer", "unreliable_ordered")
func inputs(data: PackedByteArray) -> void:
	inputs_received.emit(multiplayer.get_remote_sender_id(), data)


@rpc("authority", "unreliable_ordered")
func snapshot(data: PackedByteArray) -> void:
	later(func() -> void: snapshot_received.emit(data))


@rpc("any_peer", "unreliable")
func ping(sent_ms: int) -> void:
	pinged.emit(multiplayer.get_remote_sender_id(), sent_ms)


@rpc("authority", "unreliable")
func pong(sent_ms: int) -> void:
	later(func() -> void: ponged.emit(sent_ms))


@rpc("authority", "unreliable")
func server_stats(tps: float, tick_ms: float) -> void:
	server_stats_received.emit(tps, tick_ms)


## Client to server, through the fake lag.
func send_inputs(data: PackedByteArray) -> void:
	later(
		func() -> void:
			if _connected():
				inputs.rpc_id(1, data)
	)


func send_ping() -> void:
	var sent := Time.get_ticks_msec()
	later(
		func() -> void:
			if _connected():
				ping.rpc_id(1, sent)
	)


## Delayed sends may come due after the connection closed.
func _connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func send_hello(player_name: String) -> void:
	hello.rpc_id(1, PROTOCOL_VERSION, player_name)


## Snapshot layout: server tick u32, acked input tick u32, count u8, then per player:
## peer id u32 and a PlayerState.
static func pack_snapshot(tick: int, ack: int, players: Array[SimPlayer]) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(9 + players.size() * (4 + PlayerState.SIZE))
	buf.encode_u32(0, tick)
	buf.encode_u32(4, ack)
	buf.encode_u8(8, players.size())
	var at := 9
	for player in players:
		buf.encode_u32(at, player.peer_id)
		player.get_state().encode_into(buf, at + 4)
		at += 4 + PlayerState.SIZE
	return buf


## {tick, ack, players: {peer_id: PlayerState}}.
static func unpack_snapshot(buf: PackedByteArray) -> Dictionary:
	var players := {}
	var at := 9
	for i in buf.decode_u8(8):
		players[buf.decode_u32(at)] = PlayerState.decode_from(buf, at + 4)
		at += 4 + PlayerState.SIZE
	return {tick = buf.decode_u32(0), ack = buf.decode_u32(4), players = players}


static func pack_inputs(list: Array[PlayerInput]) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(1 + list.size() * PlayerInput.SIZE)
	buf.encode_u8(0, list.size())
	for i in list.size():
		list[i].encode_into(buf, 1 + i * PlayerInput.SIZE)
	return buf


static func unpack_inputs(buf: PackedByteArray) -> Array[PlayerInput]:
	var list: Array[PlayerInput] = []
	if buf.is_empty():
		return list
	var count := buf.decode_u8(0)
	if buf.size() < 1 + count * PlayerInput.SIZE:
		return list
	for i in count:
		list.append(PlayerInput.decode_from(buf, 1 + i * PlayerInput.SIZE))
	return list
