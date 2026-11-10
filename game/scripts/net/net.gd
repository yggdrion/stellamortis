class_name Net
extends Node
## Our own RPCs, at /root/Main/Net on server and client so they line up. Movement state and
## input go through netfox (RollbackSynchronizer on each SimPlayer), not through here.

# Server side.
signal hello_received(peer_id: int, version: int, player_name: String)
signal pinged(peer_id: int, sent_ms: int)
# Client side.
signal rejected(reason: String)
signal ponged(sent_ms: int)
signal server_stats_received(tps: float, tick_ms: float, tick_avg_ms: float, out_kbps: float)
signal room_received(code: String)
signal notice_received(text: String)

## Bump on any change to the RPCs here or to what netfox synchronizes (SimPlayer.STATE,
## PlayerControls) or to what both sides simulate (Layout, Gravity, Tuning).
const PROTOCOL_VERSION := 12

@rpc("any_peer", "reliable")
func hello(version: int, player_name: String) -> void:
	hello_received.emit(multiplayer.get_remote_sender_id(), version, player_name)


@rpc("authority", "reliable")
func reject(reason: String) -> void:
	rejected.emit(reason)


@rpc("any_peer", "unreliable")
func ping(sent_ms: int) -> void:
	pinged.emit(multiplayer.get_remote_sender_id(), sent_ms)


@rpc("authority", "unreliable")
func pong(sent_ms: int) -> void:
	ponged.emit(sent_ms)


@rpc("authority", "unreliable")
## out_kbps: kB per second the server sends to each player (ENet only, 0 over WebRTC).
func server_stats(tps: float, tick_ms: float, tick_avg_ms: float, out_kbps: float) -> void:
	server_stats_received.emit(tps, tick_ms, tick_avg_ms, out_kbps)


## Player host: the lobby room code friends join with, on joining and whenever it changes.
@rpc("authority", "reliable")
func room(code: String) -> void:
	room_received.emit(code)


## A line for every player's HUD ("Ana joined", "Ana lost the connection").
@rpc("authority", "reliable")
func notice(text: String) -> void:
	notice_received.emit(text)
