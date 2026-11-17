class_name EventLog
extends RefCounted
## The play-test event log (M24): JSON lines, one event each, in the file named by
## STELLAMORTIS_EVENT_LOG. Off without it: every entry point returns on one static flag.
##
## The server (the file itself) and each client (PATH.<peer id>) log. Sim code reports events
## where they happen (`note`), but netfox resimulates ticks when late input arrives, so a hit
## seen while simulating tick T may vanish or change on the next pass. Candidates are therefore
## kept per tick and per reporting node: `begin` (first line of a node's _rollback_tick) drops
## what that node reported for that tick before, so a resimulated tick leaves only its last pass.
## A tick is written once it is final: netfox never simulates a tick older than
## NetworkRollback.history_start (its loop starts at most history_limit ticks back, and the
## current tick only grows), so `confirm` writes the ticks below it, in tick order. The file is
## therefore not sorted by tick: events outside rollback (joins, camps waking, stats) are written
## at once. Every line has `e` (kind) and `tick`.
##
## Desync check: every HASH_TICKS ticks, HASH_DELAY ticks after the fact (inside netfox's history,
## which holds history_limit), server and client each write the state their netfox history holds
## for a player: hash, position in cm, health, action. tools/desync.py compares them.

## Ticks between state lines, and how far back they look: late enough that input and corrections
## for that tick have arrived (1.6 s), early enough that the history still holds it.
const HASH_TICKS := 30
const HASH_DELAY := 48
## Seconds between writes of the buffered lines.
const FLUSH_SECONDS := 1.0

## Sim code reports events (note) only while this is set: the server with a log.
static var server := false
## `begin` and the state check run while this is set: server or client with a log.
static var collect := false
## A client logs the state of this peer's player only.
static var own_peer := 0

static var _file: FileAccess
static var _buffer := PackedStringArray()
## Tick -> {source instance id -> Array of event dictionaries}.
static var _pending := {}
## The node whose tick is being simulated, and the tick.
static var _source := 0
static var _tick := 0
static var _flushed_ms := 0
static var _scratch: SimPlayer
## The next tick to write state lines for, -1 until the first loop.
static var _next_state := -1


## Opens the log for a role. `path` is the file name; nothing happens (and the log stays off)
## when it is empty or cannot be opened. Returns whether it is on.
static func open(path: String, as_server: bool, peer := 0) -> bool:
	close()
	if path == "":
		return false
	_file = FileAccess.open(path if as_server else "%s.%d" % [path, peer], FileAccess.WRITE)
	if _file == null:
		push_error("Cannot open the event log %s" % path)
		return false
	server = as_server
	collect = true
	own_peer = peer
	_flushed_ms = Time.get_ticks_msec()
	if not NetworkRollback.after_loop.is_connected(_after_loop):
		NetworkRollback.after_loop.connect(_after_loop)
		NetworkRollback.after_process_tick.connect(_after_process)
	emit_now("open", {"role": "server" if as_server else "client", "peer": peer})
	return true


## Writes everything left (ticks not yet final too: a stopped game has no later rollback) and
## closes the file.
static func close() -> void:
	if _file != null:
		confirm(1 << 60)
		flush()
		_file.close()
		_file = null
	server = false
	collect = false
	own_peer = 0
	_pending.clear()
	_buffer.clear()
	_source = 0
	_next_state = -1
	if _scratch != null:
		_scratch.free()
		_scratch = null


## An attack's id: the file name its resource was loaded from.
static func attack_id(def: AttackDef) -> String:
	return def.resource_path.get_file().get_basename()


static func is_open() -> bool:
	return _file != null


## First line of a node's _rollback_tick: what it reported for this tick on an earlier pass is
## void now, and what it reports next belongs to this tick.
static func begin(source: Node, tick: int) -> void:
	_source = source.get_instance_id()
	_tick = tick
	var sources: Dictionary = _pending.get(tick, {})
	sources.erase(_source)


## Reports an event from sim code (guard calls with `if EventLog.server`). Inside a node's tick
## it is a candidate until the tick is final; outside rollback it is written at once.
static func note(kind: String, fields: Dictionary) -> void:
	if _file == null:
		return
	if _source == 0:
		emit_now(kind, fields)
		return
	var event := {"e": kind, "tick": _tick}
	event.merge(fields)
	if not _pending.has(_tick):
		_pending[_tick] = {}
	var sources: Dictionary = _pending[_tick]
	if not sources.has(_source):
		sources[_source] = []
	(sources[_source] as Array).append(event)


## Writes an event now, stamped with the current network tick.
static func emit_now(kind: String, fields: Dictionary) -> void:
	if _file == null:
		return
	var event := {"e": kind, "tick": NetworkTime.tick}
	event.merge(fields)
	_buffer.append(JSON.stringify(event))


## Writes the candidates of every tick below `limit`, oldest first, and the buffer once a
## second has passed.
static func confirm(limit: int) -> void:
	if _file == null:
		return
	var ticks: Array = _pending.keys().filter(func(t: int) -> bool: return t < limit)
	ticks.sort()
	for tick: int in ticks:
		for events: Array in (_pending[tick] as Dictionary).values():
			for event: Dictionary in events:
				_buffer.append(JSON.stringify(event))
		_pending.erase(tick)
	if Time.get_ticks_msec() - _flushed_ms >= int(FLUSH_SECONDS * 1000.0):
		flush()


static func flush() -> void:
	if _file == null:
		return
	_flushed_ms = Time.get_ticks_msec()
	if _buffer.is_empty():
		return
	_file.store_string("\n".join(_buffer) + "\n")
	_file.flush()
	_buffer.clear()


static func _after_process(_tick_done: int) -> void:
	# Between nodes' ticks and after the loop, reports are not part of a simulated tick.
	_source = 0


static func _after_loop() -> void:
	_source = 0
	if _file == null:
		return
	confirm(NetworkRollback.history_start)
	_log_states(NetworkTime.tick - HASH_DELAY)


## The state lines for the multiples of HASH_TICKS up to `tick` not logged yet (one per player
## this log covers): what netfox's history holds for the player. A tick the history no longer
## holds (a stalled loop) is skipped.
static func _log_states(tick: int) -> void:
	if tick < 0:
		return
	if _next_state < 0 or _next_state > tick + HASH_TICKS:
		_next_state = ceili(float(tick) / HASH_TICKS) * HASH_TICKS
	var tree := Engine.get_main_loop() as SceneTree
	while _next_state <= tick:
		var at := _next_state
		_next_state += HASH_TICKS
		var snapshot: _Snapshot = NetworkHistoryServer._get_rollback_state_snapshot(at)
		if snapshot == null:
			continue
		for node: Node in tree.get_nodes_in_group(SimPlayer.GROUP):
			var player := node as SimPlayer
			if not server and player.peer_id != own_peer:
				continue
			var state := state_of(snapshot, player)
			if not state.is_empty():
				state["peer"] = player.peer_id
				state["at"] = at
				emit_now("state", state)


## The player's state in a snapshot as {h, pos (cm), hp (tenths), act}: position and health are
## rounded, so the float noise of two machines is no difference. Empty when the snapshot has
## nothing of this player.
static func state_of(snapshot: _Snapshot, player: SimPlayer) -> Dictionary:
	var transform_value: Variant = null
	var combat: Variant = null
	for path: NodePath in snapshot.get_subject_properties(player):
		match String(path).trim_prefix(":"):
			"transform":
				transform_value = snapshot.get_property(player, path)
			"net_combat":
				combat = snapshot.get_property(player, path)
	if not (transform_value is Transform3D) or not (combat is PackedByteArray):
		return {}
	if _scratch == null:
		_scratch = SimPlayer.new()
	Wire.unpack(_scratch, SimPlayer.COMBAT, combat as PackedByteArray)
	return state_fields(
		(transform_value as Transform3D).origin, _scratch.health, int(_scratch.action)
	)


## The hashed fields. Position goes through the float32 the wire carries, then to whole
## centimetres.
static func state_fields(origin: Vector3, health: float, action: int) -> Dictionary:
	var cm := [roundi(origin.x * 100.0), roundi(origin.y * 100.0), roundi(origin.z * 100.0)]
	var hp := roundi(health * 10.0)
	return {
		"h": ("%d,%d,%d,%d,%d" % [cm[0], cm[1], cm[2], hp, action]).hash(),
		"pos": cm,
		"hp": hp,
		"act": action,
	}
