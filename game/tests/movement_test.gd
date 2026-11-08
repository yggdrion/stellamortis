extends GdUnitTestSuite
## SimPlayer moves on the arena: walks where the input yaw points, lands after a jump, and
## replaying the same inputs from the same state gives the same result (what prediction
## relies on).

const DELTA := 1.0 / 30.0

var _arena: Arena


func before_test() -> void:
	_arena = auto_free(Arena.new(false)) as Arena
	add_child(_arena)


func _player() -> SimPlayer:
	var player := auto_free(SimPlayer.new()) as SimPlayer
	add_child(player)
	player.global_position = Vector3(0, 0.05, 0)
	return player


func _forward(yaw := 0.0, buttons := 0) -> PlayerInput:
	var input := PlayerInput.new()
	input.move = Vector2(0, 1)
	input.yaw = yaw
	input.buttons = buttons
	return input.quantized()


## Steps inside physics frames, like the game: move_and_slide reads the physics delta.
func _run(player: SimPlayer, inputs: Array[PlayerInput]) -> void:
	for input in inputs:
		await get_tree().physics_frame
		player.step(input, DELTA)


func test_walks_forward() -> void:
	var player := _player()
	var inputs: Array[PlayerInput] = []
	for i in 30:
		inputs.append(_forward())
	await _run(player, inputs)
	# Reference forward is -Z: about walk_speed metres in one second, minus the speed-up.
	assert_float(-player.global_position.z).is_between(3.5, 5.1)
	assert_float(absf(player.global_position.x)).is_less(0.05)
	assert_bool(player.grounded).is_true()


func test_yaw_turns_the_walk() -> void:
	var player := _player()
	var inputs: Array[PlayerInput] = []
	for i in 20:
		inputs.append(_forward(PI / 2.0))
	await _run(player, inputs)
	# A quarter turn left of -Z is -X.
	assert_float(-player.global_position.x).is_greater(2.0)


func test_jump_lands() -> void:
	var player := _player()
	var idle: Array[PlayerInput] = []
	for i in 10:
		idle.append(PlayerInput.new())
	await _run(player, idle)
	assert_bool(player.grounded).is_true()
	var inputs: Array[PlayerInput] = [_forward(0.0, PlayerInput.Buttons.JUMP)]
	for i in 3:
		inputs.append(_forward())
	await _run(player, inputs)
	assert_bool(player.grounded).is_false()
	assert_float(player.global_position.y).is_greater(0.2)
	inputs.clear()
	for i in 60:
		inputs.append(_forward())
	await _run(player, inputs)
	assert_bool(player.grounded).is_true()
	assert_float(player.global_position.y).is_less(0.1)


func test_replay_is_deterministic() -> void:
	var player := _player()
	var inputs: Array[PlayerInput] = []
	for i in 40:
		inputs.append(_forward(i * 0.05, PlayerInput.Buttons.JUMP if i == 10 else 0))
	var start := player.get_state()
	await _run(player, inputs)
	var first := player.get_state()
	player.apply_state(start)
	await _run(player, inputs)
	assert_float(player.get_state().error_to(first)).is_less(0.001)
