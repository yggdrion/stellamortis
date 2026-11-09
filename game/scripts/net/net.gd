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
signal server_stats_received(tps: float, tick_ms: float, tick_avg_ms: float)

## Bump on any change to the RPCs here or to what netfox synchronizes (SimPlayer.STATE,
## PlayerControls) or to what both sides simulate (Layout, Gravity, Tuning).
const PROTOCOL_VERSION := 7

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
func server_stats(tps: float, tick_ms: float, tick_avg_ms: float) -> void:
	server_stats_received.emit(tps, tick_ms, tick_avg_ms)
