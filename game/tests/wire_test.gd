extends GdUnitTestSuite
## Every synchronized property has a compact serializer (Wire), values survive a round trip,
## the packed groups (net_*) cover the whole rolled back state, and a player's full state fits
## netfox's 508 byte packet limit.

const PACKET_LIMIT := 508


func _all_properties() -> Array:
	return SimPlayer.STATE + PlayerControls.INPUT + Enemy.STATE + Encounter.STATE


func test_every_synchronized_property_has_a_serializer() -> void:
	for property: String in _all_properties():
		assert_bool(Wire.has(property)).override_failure_message(property).is_true()


func _encoded_size(node: Object, properties: Array) -> int:
	var buffer := StreamPeerBuffer.new()
	for property: String in properties:
		Wire.serializer(property).encode(node.get(property), buffer)
	return buffer.get_size()


func _round_trip(node: Object, properties: Array) -> void:
	var buffer := StreamPeerBuffer.new()
	for property: String in properties:
		Wire.serializer(property).encode(node.get(property), buffer)
	buffer.seek(0)
	for property: String in properties:
		var back: Variant = Wire.serializer(property).decode(buffer)
		var value: Variant = node.get(property)
		if value is float:
			assert_float(back).override_failure_message(property).is_equal_approx(value, 0.001)
		else:
			assert_that(back).override_failure_message(property).is_equal(value)


func test_player_state_round_trips_and_fits_a_packet() -> void:
	var player := auto_free(SimPlayer.new()) as SimPlayer
	player.transform = Transform3D(Basis.from_euler(Vector3(0.1, 2.0, -0.3)), Vector3(40, 68.1, -3))
	player.velocity = Vector3(1.5, -9.8, 0.25)
	player.health = 63.5
	player.action_time = 4000
	player.swing_hits = 0b100101
	player.bolt_pos[2] = Vector3(1, 2, 3)
	player.bolt_life[2] = 90
	player.bolt_damage[2] = 37.25
	_round_trip(player, SimPlayer.STATE)
	var size := _encoded_size(player, SimPlayer.SYNCED)
	# Headroom for netfox's tick, identity reference and size prefix.
	assert_int(size).is_less(PACKET_LIMIT - 32)


func test_every_enemy_kind_round_trips_and_fits_a_packet() -> void:
	# The biggest slot: every kind's state, with the boss's ten bolts.
	for kind in Combat.ENEMY_KINDS.size():
		var enemy := auto_free(Enemy.new()) as Enemy
		enemy.kind = kind
		enemy.make_bolts(10)
		enemy.bolt_pos[7] = Vector3(-4, 1.5, 30)
		enemy.bolt_life[7] = 120
		enemy.well_time = 150
		enemy.combo = 9
		enemy.max_health = 1350.0
		_round_trip(enemy, Enemy.STATE)
		assert_int(_encoded_size(enemy, Enemy.STATE)).is_less(PACKET_LIMIT - 32)


func test_packed_fields_restore_an_enemy_kind() -> void:
	var fields := Enemy.STATE.filter(func(f: String) -> bool: return f != "transform")
	var enemy := auto_free(Enemy.new()) as Enemy
	enemy.kind = Combat.enemy_kind(&"warden")
	enemy.health = 12.5
	enemy.combo = 3
	var other := auto_free(Enemy.new()) as Enemy
	Wire.unpack(other, fields, Wire.pack(enemy, fields))
	assert_int(other.kind).is_equal(Combat.enemy_kind(&"warden"))
	assert_object(other.def).is_same(enemy.def)
	assert_float(other.radius).is_equal(enemy.def.radius)
	assert_float(other.health).is_equal(12.5)
	assert_int(other.combo).is_equal(3)


func test_packed_groups_cover_the_player_state() -> void:
	var grouped := ["transform", "velocity"] + SimPlayer.MOTION + SimPlayer.COMBAT + SimPlayer.BOLTS
	grouped.sort()
	var state := SimPlayer.STATE.duplicate()
	state.sort()
	assert_array(grouped).is_equal(state)


func test_packed_groups_restore_the_player() -> void:
	var player := auto_free(SimPlayer.new()) as SimPlayer
	player.up = Vector3(0, 0, 1)
	player.health = 12.5
	player.action = SimPlayer.Action.ROLL
	player.action_time = 300
	player.bolt_life[1] = 44
	var motion := player.net_motion
	var combat := player.net_combat
	var bolts := player.net_bolts
	var other := auto_free(SimPlayer.new()) as SimPlayer
	other.net_motion = motion
	other.net_combat = combat
	other.net_bolts = bolts
	assert_vector(other.up).is_equal(Vector3(0, 0, 1))
	assert_float(other.health).is_equal(12.5)
	assert_int(other.action).is_equal(SimPlayer.Action.ROLL)
	assert_int(other.action_time).is_equal(300)
	assert_int(other.bolt_life[1]).is_equal(44)
