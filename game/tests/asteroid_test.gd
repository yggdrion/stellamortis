extends GdUnitTestSuite
## Walking around the asteroid and the jump pads between it and the ground, with the real
## SimPlayer on the real arena collision.

const DELTA := 1.0 / 30.0

var _arena: Arena


func before_test() -> void:
	_arena = auto_free(Arena.new(false)) as Arena
	add_child(_arena)


func _player_at(feet: Vector3, up: Vector3) -> SimPlayer:
	var player := auto_free(SimPlayer.new()) as SimPlayer
	add_child(player)
	player.up = up
	player.ref_forward = SimPlayer._tangent(Vector3.FORWARD, up)
	player.facing = player.ref_forward
	# Orient first: the capsule stands along the body's local up.
	player.global_transform = Transform3D(SimPlayer.frame(up, player.facing), feet)
	return player


## Runs ticks inside physics frames (move_and_slide reads the physics delta), pressing
## buttons on the first one.
func _run(player: SimPlayer, ticks: int, move: Vector2, buttons := 0) -> void:
	for i in ticks:
		await get_tree().physics_frame
		player.step(move, 0.0, buttons if i == 0 else 0, DELTA)


func _height_over_asteroid(player: SimPlayer) -> float:
	return player.global_position.distance_to(Layout.ASTEROID_CENTER) - Layout.ASTEROID_RADIUS


func test_walk_around_asteroid() -> void:
	var top := Layout.ASTEROID_CENTER + Vector3.UP * (Layout.ASTEROID_RADIUS + 0.05)
	var player := _player_at(top, Vector3.UP)
	await _run(player, 10, Vector2.ZERO)
	var start := player.global_position
	var grounded := 0
	var highest := 0.0
	# 12 s at walk speed is about 60 m, more than half way around (113 m).
	for i in 360:
		await get_tree().physics_frame
		player.step(Vector2(0, 1), 0.0, 0, DELTA)
		grounded += 1 if player.grounded else 0
		highest = maxf(highest, _height_over_asteroid(player))
	# Stayed on the surface (boulders are up to 2.8 m, the path may climb one).
	assert_float(highest).is_less(3.2)
	assert_float(grounded / 360.0).is_greater(0.9)
	# Went far around: the up vector turned well past the equator.
	assert_float(player.up.angle_to(Vector3.UP)).is_greater(deg_to_rad(120))
	assert_float(player.global_position.distance_to(start)).is_greater(25.0)
	# The camera's reference frame stayed tangent.
	assert_float(absf(player.ref_forward.dot(player.up))).is_less(0.001)


func test_ground_pad_reaches_asteroid() -> void:
	var pad := Layout.jump_pads()[0]
	var player := _player_at(pad.position + Vector3.UP * 0.05, Vector3.UP)
	await _run(player, 10, Vector2.ZERO)
	await _run(player, 150, Vector2.ZERO, PlayerControls.Buttons.JUMP)
	assert_bool(player.grounded).is_true()
	assert_float(_height_over_asteroid(player)).is_less(0.5)
	assert_float(player.up.dot(Vector3.DOWN)).is_greater(0.8)


func test_return_pad_reaches_ground() -> void:
	var pad := Layout.jump_pads()[1]
	var player := _player_at(pad.position + Vector3.DOWN * 0.05, Vector3.DOWN)
	await _run(player, 10, Vector2.ZERO)
	await _run(player, 150, Vector2.ZERO, PlayerControls.Buttons.JUMP)
	assert_bool(player.grounded).is_true()
	assert_float(player.global_position.y).is_less(0.2)
	assert_float(player.up.dot(Vector3.UP)).is_greater(0.99)


func test_plain_jump_cannot_leave_asteroid() -> void:
	var side := Layout.ASTEROID_CENTER + Vector3.RIGHT * (Layout.ASTEROID_RADIUS + 0.05)
	var player := _player_at(side, Vector3.RIGHT)
	await _run(player, 10, Vector2.ZERO)
	await _run(player, 90, Vector2.ZERO, PlayerControls.Buttons.JUMP)
	assert_float(_height_over_asteroid(player)).is_less(0.5)
