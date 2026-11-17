extends GdUnitTestSuite
## EventLog (M24): a hit is logged once although its tick was resimulated, what a resimulation
## no longer reports vanishes, and the state hash tells a changed value from noise.

const DELTA := 1.0 / 30.0
const PATH := "user://event_log_test.jsonl"
const B := PlayerControls.Buttons

var _world: Node3D
var _player: SimPlayer
var _dummy: Enemy


func before_test() -> void:
	_world = auto_free(Node3D.new()) as Node3D
	add_child(_world)
	FlatGround.add(_world)
	_dummy = Enemy.new()
	_dummy.kind = Combat.enemy_kind(&"dummy")
	_dummy.index = 0
	_dummy.passive = true
	_dummy.facing = Vector3.BACK
	_world.add_child(_dummy)
	_dummy.global_transform = Transform3D(
		SimPlayer.frame(Vector3.UP, _dummy.facing), Vector3(0, 0, -10)
	)
	_player = SimPlayer.new()
	_player.peer_id = 7
	_world.add_child(_player)
	_player.place(Vector3(0, 0, -8.4))
	_player.facing = Vector3.FORWARD
	_player.ref_forward = Vector3.FORWARD
	assert_bool(EventLog.open(PATH, true)).is_true()


func after_test() -> void:
	EventLog.close()
	DirAccess.remove_absolute(PATH)


## The events written so far, after everything is final.
func _lines() -> Array[Dictionary]:
	EventLog.confirm(1 << 40)
	EventLog.flush()
	var lines: Array[Dictionary] = []
	var text := FileAccess.get_file_as_string(PATH)
	for line in text.split("\n", false):
		lines.append(JSON.parse_string(line) as Dictionary)
	return lines


func _of(kind: String) -> Array[Dictionary]:
	return _lines().filter(func(e: Dictionary) -> bool: return e["e"] == kind)


func _save(node: Object, names: Array) -> Dictionary:
	var saved := {}
	for property: String in names:
		saved[property] = node.get(property)
	return saved


func _restore(node: Object, saved: Dictionary) -> void:
	for property: String in saved:
		node.set(property, saved[property])


## Steps player and dummy one tick as netfox does: the player's tick starts with `begin`.
func _tick(tick: int, buttons := 0) -> void:
	await get_tree().physics_frame
	_dummy._rollback_tick(DELTA, tick, true)
	EventLog.begin(_player, tick)
	_player.step(Vector2.ZERO, 0.0, buttons, DELTA)


func test_resimulated_hit_is_logged_once() -> void:
	var hit_tick := -1
	var player_before := {}
	var dummy_before := {}
	for tick in 40:
		var player_state := _save(_player, SimPlayer.STATE)
		var dummy_state := _save(_dummy, Enemy.STATE)
		var health := _dummy.health
		await _tick(tick, B.ATTACK if tick == 0 else 0)
		if hit_tick < 0 and _dummy.health < health:
			hit_tick = tick
			player_before = player_state
			dummy_before = dummy_state
			break
	assert_int(hit_tick).is_greater(0)
	# Late input: netfox restores the tick's state and simulates it again, twice.
	for pass_number in 2:
		_restore(_player, player_before)
		_restore(_dummy, dummy_before)
		await _tick(hit_tick)
	var hits := _of("hit")
	assert_int(hits.size()).is_equal(1)
	assert_int(int(hits[0]["tick"])).is_equal(hit_tick)
	assert_int(int(hits[0]["attacker"])).is_equal(7)
	assert_str(hits[0]["attack"]).is_equal("light_1")
	assert_float(hits[0]["damage"]).is_equal(Combat.attack(&"light_1").damage)


func test_a_resimulation_that_reports_nothing_voids_the_event() -> void:
	var node := auto_free(Node.new()) as Node
	var other := auto_free(Node.new()) as Node
	EventLog.begin(node, 5)
	EventLog.note("roll", {"peer": 1})
	EventLog.begin(other, 5)
	EventLog.note("roll", {"peer": 2})
	# Tick 5 is simulated again for the first node only: its roll is gone, the other stays.
	EventLog.begin(node, 5)
	var rolls := _of("roll")
	assert_int(rolls.size()).is_equal(1)
	assert_int(int(rolls[0]["peer"])).is_equal(2)


func test_nothing_is_written_before_the_tick_is_final() -> void:
	var node := auto_free(Node.new()) as Node
	EventLog.begin(node, 100)
	EventLog.note("roll", {"peer": 1})
	EventLog.confirm(100)
	EventLog.flush()
	assert_str(FileAccess.get_file_as_string(PATH)).not_contains("roll")
	EventLog.confirm(101)
	EventLog.flush()
	assert_str(FileAccess.get_file_as_string(PATH)).contains("roll")


func test_state_hash_agrees_and_reports_a_changed_value() -> void:
	_player.health = 73.5
	var server := _snapshot(_player, 60)
	var client := _snapshot(_player, 60)
	var same := EventLog.state_of(server, _player)
	assert_int(same["h"]).is_equal(EventLog.state_of(client, _player)["h"])
	# The client's player 3 cm off, or hurt, or in another action, is another hash.
	_player.global_position += Vector3(0.03, 0, 0)
	assert_int(EventLog.state_of(_snapshot(_player, 60), _player)["h"]).is_not_equal(same["h"])
	_player.global_position -= Vector3(0.03, 0, 0)
	_player.health = 70.0
	assert_int(EventLog.state_of(_snapshot(_player, 60), _player)["h"]).is_not_equal(same["h"])
	_player.health = 73.5
	_player.action = SimPlayer.Action.ROLL
	assert_int(EventLog.state_of(_snapshot(_player, 60), _player)["h"]).is_not_equal(same["h"])


## What netfox's history holds for a player at a tick: the properties the log reads.
func _snapshot(player: SimPlayer, tick: int) -> _Snapshot:
	var snapshot := _Snapshot.new(tick)
	snapshot.set_property(player, NodePath(":transform"), player.global_transform)
	snapshot.set_property(player, NodePath(":net_combat"), player.net_combat)
	return snapshot
