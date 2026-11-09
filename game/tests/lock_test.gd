extends GdUnitTestSuite
## Lock-on with the real arena: picking the enemy at the camera's center, toggling off,
## switching left and right, strafing around the target, rolling away from it, dropping the lock
## when the target dies or is left behind, and all of it on the asteroid.

const DELTA := 1.0 / 30.0
const B := PlayerControls.Buttons
## Looks a bit left of straight ahead: toward the passive dummy at (-4, 0, -10).
const YAW_LEFT := 0.3

var _world: Node3D
var _player: SimPlayer
var _left: TrainingDummy
var _right: TrainingDummy


func before_test() -> void:
	_world = auto_free(Node3D.new()) as Node3D
	add_child(_world)
	_world.add_child(Arena.new(false))
	_left = _dummy(0, Layout.DUMMIES[0][0], Vector3.UP)
	_right = _dummy(1, Layout.DUMMIES[1][0], Vector3.UP)
	_player = SimPlayer.new()
	_world.add_child(_player)
	_player.place(Vector3.ZERO)


## A dummy standing along up_vector; the tests never tick dummies, so they stay put.
func _dummy(index: int, at: Vector3, up_vector: Vector3) -> TrainingDummy:
	var dummy := TrainingDummy.new()
	dummy.index = index
	dummy.passive = true
	_world.add_child(dummy)
	dummy.facing = SimPlayer._tangent(Vector3.BACK, up_vector)
	dummy.global_transform = Transform3D(SimPlayer.frame(up_vector, dummy.facing), at)
	return dummy


func _run(ticks: int, buttons := 0, move := Vector2.ZERO, yaw := YAW_LEFT) -> void:
	for i in ticks:
		await get_tree().physics_frame
		_player.step(move, yaw, buttons, DELTA)


## A press: one tick down, one up.
func _press(button: int, yaw := YAW_LEFT) -> void:
	await _run(1, button, Vector2.ZERO, yaw)
	await _run(1, 0, Vector2.ZERO, yaw)


func _facing_target(enemy: Enemy) -> float:
	var to := SimPlayer._tangent(enemy.center() - _player.center(), _player.up)
	return _player.facing.dot(to)


func test_lock_picks_the_enemy_at_the_camera_center() -> void:
	await _press(B.LOCK)
	assert_int(_player.target).is_equal(_left.index)
	_player.place(Vector3.ZERO)
	await _press(B.LOCK)
	assert_int(_player.target).is_equal(LockOn.NONE)
	await _press(B.LOCK, -YAW_LEFT)
	assert_int(_player.target).is_equal(_right.index)


func test_lock_needs_an_enemy_near_the_center() -> void:
	# Looking back, away from both dummies.
	await _press(B.LOCK, PI)
	assert_int(_player.target).is_equal(LockOn.NONE)


func test_switch_goes_left_and_right() -> void:
	await _press(B.LOCK)
	await _press(B.SWITCH_RIGHT)
	assert_int(_player.target).is_equal(_right.index)
	# Nothing further right: the lock stays.
	await _press(B.SWITCH_RIGHT)
	assert_int(_player.target).is_equal(_right.index)
	await _press(B.SWITCH_LEFT)
	assert_int(_player.target).is_equal(_left.index)


func test_strafe_circles_the_target_facing_it() -> void:
	await _press(B.LOCK)
	var start := _player.global_position.distance_to(_left.global_position)
	var from := _player.global_position
	await _run(60, 0, Vector2(1, 0), 2.0)
	var distance := _player.global_position.distance_to(_left.global_position)
	assert_float(_player.global_position.distance_to(from)).is_greater(5.0)
	assert_float(distance).is_between(start - 1.0, start + 2.5)
	assert_float(_facing_target(_left)).is_greater(0.95)


func test_roll_without_direction_backs_away_from_the_target() -> void:
	await _press(B.LOCK)
	var start := _player.global_position.distance_to(_left.global_position)
	await _press(B.ROLL)
	await _run(Combat.ticks(Tuning.data().roll_time))
	var distance := _player.global_position.distance_to(_left.global_position)
	assert_float(distance).is_greater(start + 2.5)


func test_roll_sideways_goes_relative_to_the_target() -> void:
	await _press(B.LOCK)
	var to_target := SimPlayer._tangent(_left.center() - _player.center(), Vector3.UP)
	var from := _player.global_position
	await _run(1, B.ROLL, Vector2(1, 0))
	await _run(Combat.ticks(Tuning.data().roll_time), 0, Vector2(1, 0))
	var moved := (_player.global_position - from).normalized()
	assert_float(absf(moved.dot(to_target))).is_less(0.3)


func test_lock_drops_when_the_target_dies_or_is_far() -> void:
	await _press(B.LOCK)
	_left.take_hit(10000.0)
	await _run(1)
	assert_int(_player.target).is_equal(LockOn.NONE)
	await _press(B.LOCK, -YAW_LEFT)
	assert_int(_player.target).is_equal(_right.index)
	_player.place(Vector3(0, 0, 40))
	await _run(1)
	assert_int(_player.target).is_equal(LockOn.NONE)


func test_lock_and_strafe_on_the_asteroid() -> void:
	var center := Layout.ASTEROID_CENTER
	var radius := Layout.ASTEROID_RADIUS
	var tilt := deg_to_rad(16.0)
	var radial := Vector3(-sin(tilt), cos(tilt), 0.0)
	var dummy := _dummy(2, center + radial * radius, radial)
	_player.place(center + Vector3.UP * radius)
	# Let up settle on the surface first.
	await _run(15, 0, Vector2.ZERO, 0.0)
	_player.ref_forward = SimPlayer._tangent(dummy.center() - _player.center(), _player.up)
	await _press(B.LOCK, 0.0)
	assert_int(_player.target).is_equal(dummy.index)
	await _run(45, 0, Vector2(1, 0), 0.0)
	assert_int(_player.target).is_equal(dummy.index)
	assert_float(_facing_target(dummy)).is_greater(0.9)
	var height := _player.global_position.distance_to(center)
	assert_float(height).is_between(radius - 0.3, radius + 0.6)
