extends GdUnitTestSuite
## Inputs and snapshots survive packing, and quantizing an input is stable (the client predicts
## with exactly what the server decodes).


func test_input_round_trip() -> void:
	var input := PlayerInput.new()
	input.tick = 123456
	input.move = Vector2(-0.5, 1.0)
	input.yaw = 2.5
	input.buttons = PlayerInput.Buttons.JUMP | PlayerInput.Buttons.SPRINT
	var q := input.quantized()
	assert_int(q.tick).is_equal(123456)
	assert_vector(q.move).is_equal_approx(Vector2(-0.5, 1.0), Vector2(0.01, 0.01))
	assert_float(q.yaw).is_equal_approx(2.5, 0.001)
	assert_bool(q.has(PlayerInput.Buttons.JUMP)).is_true()
	assert_bool(q.has(PlayerInput.Buttons.SPRINT)).is_true()
	var again := q.quantized()
	assert_vector(again.move).is_equal(q.move)
	assert_float(again.yaw).is_equal(q.yaw)


func test_negative_yaw_wraps() -> void:
	var input := PlayerInput.new()
	input.yaw = -0.5
	assert_float(input.quantized().yaw).is_equal_approx(TAU - 0.5, 0.001)


func test_inputs_list_round_trip() -> void:
	var list: Array[PlayerInput] = []
	for i in 4:
		var input := PlayerInput.new()
		input.tick = 10 + i
		list.append(input)
	var back := Net.unpack_inputs(Net.pack_inputs(list))
	assert_int(back.size()).is_equal(4)
	assert_int(back[3].tick).is_equal(13)


func test_truncated_inputs_are_ignored() -> void:
	var buf := PackedByteArray([3, 1, 2])
	assert_array(Net.unpack_inputs(buf)).is_empty()


func test_snapshot_round_trip() -> void:
	var player := auto_free(SimPlayer.new()) as SimPlayer
	add_child(player)
	player.peer_id = 42
	player.position = Vector3(1, 2, 3)
	player.velocity = Vector3(0, -1, 4)
	player.grounded = true
	var players: Array[SimPlayer] = [player]
	var snapshot := Net.unpack_snapshot(Net.pack_snapshot(900, 77, players))
	assert_int(snapshot.tick).is_equal(900)
	assert_int(snapshot.ack).is_equal(77)
	var state: PlayerState = snapshot.players[42]
	assert_vector(state.position).is_equal(Vector3(1, 2, 3))
	assert_vector(state.velocity).is_equal(Vector3(0, -1, 4))
	assert_bool(state.grounded).is_true()
