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


## [move, yaw, buttons]
func _forward(yaw := 0.0, buttons := 0) -> Array:
	return [Vector2(0, 1), yaw, buttons]


func _idle() -> Array:
	return [Vector2.ZERO, 0.0, 0]


## Steps inside physics frames, like the game: move_and_slide reads the physics delta.
func _run(player: SimPlayer, inputs: Array) -> void:
	for input: Array in inputs:
		await get_tree().physics_frame
		player.step(input[0], input[1], input[2], DELTA)


func _snapshot(player: SimPlayer) -> Array:
	return [player.global_transform, player.velocity, player.up, player.ref_forward, player.facing]


func _restore(player: SimPlayer, state: Array) -> void:
	player.global_transform = state[0]
	player.velocity = state[1]
	player.up = state[2]
	player.ref_forward = state[3]
	player.facing = state[4]


func test_walks_forward() -> void:
	var player := _player()
	var inputs: Array = []
	for i in 30:
		inputs.append(_forward())
	await _run(player, inputs)
	# Reference forward is -Z: about walk_speed metres in one second, minus the speed-up.
	assert_float(-player.global_position.z).is_between(3.5, 5.1)
	assert_float(absf(player.global_position.x)).is_less(0.05)
	assert_bool(player.grounded).is_true()


func test_yaw_turns_the_walk() -> void:
	var player := _player()
	var inputs: Array = []
	for i in 20:
		inputs.append(_forward(PI / 2.0))
	await _run(player, inputs)
	# A quarter turn left of -Z is -X.
	assert_float(-player.global_position.x).is_greater(2.0)


func test_jump_lands() -> void:
	var player := _player()
	var idle: Array = []
	for i in 10:
		idle.append(_idle())
	await _run(player, idle)
	assert_bool(player.grounded).is_true()
	var inputs: Array = [_forward(0.0, PlayerControls.Buttons.JUMP)]
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
	var inputs: Array = []
	for i in 40:
		inputs.append(_forward(i * 0.05, PlayerControls.Buttons.JUMP if i == 10 else 0))
	var start := _snapshot(player)
	await _run(player, inputs)
	var first: Transform3D = player.global_transform
	_restore(player, start)
	await _run(player, inputs)
	assert_float(player.global_position.distance_to(first.origin)).is_less(0.001)


## The test stair in the realm (Arena: six 0.4 m risers, 0.8 m deep, top at 2.4 m) is walked up
## without jumping.
func test_walks_up_stairs() -> void:
	var player := _player()
	player.global_position = Vector3(8, 0.05, -23.0)
	var highest := 0.0
	for i in 60:
		await _run(player, [_forward()])
		highest = maxf(highest, player.global_position.y)
	assert_float(highest).is_greater(2.3)
