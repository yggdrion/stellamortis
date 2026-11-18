extends GdUnitTestSuite
## Walking around a small test sphere with its own gravity (the Skyshards of M62 are floating
## rocks like it) and the jump pads between it and the ground, with the real SimPlayer on real
## collision: a sphere body, two zones in Layout and two pads, all added here and removed after.

const DELTA := 1.0 / 30.0
const CENTER := Vector3(40.0, 50.0, 0.0)
const RADIUS := 18.0
## Gravity reaches this far from the sphere's center.
const REACH := 34.0
const GRAVITY := 7.0

var _zones: Array[GravityZone] = []
var _pads: Array[JumpPad] = []


func before_test() -> void:
	var ground := auto_free(Node3D.new()) as Node3D
	add_child(ground)
	FlatGround.add(ground)
	var rock := StaticBody3D.new()
	rock.collision_layer = SimPlayer.LAYER_WORLD
	rock.collision_mask = 0
	rock.position = CENTER
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	rock.add_child(shape)
	ground.add_child(rock)
	# Weak gravity over the pad, so a launch from the ground reaches the rock's pull.
	_zones = [
		GravityZone.box("low gravity", Vector3(40, 9, 0), Vector3(30, 18, 40), 3.0),
		GravityZone.sphere("test rock", CENTER, REACH, GRAVITY),
	]
	Layout.gravity_zones().append_array(_zones)
	# Off the pole below the sphere, so the launch lands beside the return pad; the other one is
	# its bottom pole, up pointing at the ground.
	_pads = [
		JumpPad.at(Vector3(40.0, 0.0, 6.0), Vector3.UP, 12.0),
		JumpPad.at(CENTER + Vector3.DOWN * RADIUS, Vector3.DOWN, 17.0),
	]
	Layout.jump_pads().append_array(_pads)


func after_test() -> void:
	for zone in _zones:
		Layout.gravity_zones().erase(zone)
	for pad in _pads:
		Layout.jump_pads().erase(pad)


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


func _height_over_rock(player: SimPlayer) -> float:
	return player.global_position.distance_to(CENTER) - RADIUS


func test_walk_around_the_rock() -> void:
	var top := CENTER + Vector3.UP * (RADIUS + 0.05)
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
		highest = maxf(highest, _height_over_rock(player))
	# Stayed on the surface.
	assert_float(highest).is_less(0.6)
	assert_float(grounded / 360.0).is_greater(0.9)
	# Went far around: the up vector turned well past the equator.
	assert_float(player.up.angle_to(Vector3.UP)).is_greater(deg_to_rad(120))
	assert_float(player.global_position.distance_to(start)).is_greater(25.0)
	# The camera's reference frame stayed tangent.
	assert_float(absf(player.ref_forward.dot(player.up))).is_less(0.001)


func test_ground_pad_reaches_the_rock() -> void:
	var pad := _pads[0]
	var player := _player_at(pad.position + Vector3.UP * 0.05, Vector3.UP)
	await _run(player, 10, Vector2.ZERO)
	await _run(player, 150, Vector2.ZERO, PlayerControls.Buttons.JUMP)
	assert_bool(player.grounded).is_true()
	assert_float(_height_over_rock(player)).is_less(0.5)
	assert_float(player.up.dot(Vector3.DOWN)).is_greater(0.8)


func test_return_pad_reaches_ground() -> void:
	var pad := _pads[1]
	var player := _player_at(pad.position + Vector3.DOWN * 0.05, Vector3.DOWN)
	await _run(player, 10, Vector2.ZERO)
	await _run(player, 150, Vector2.ZERO, PlayerControls.Buttons.JUMP)
	assert_bool(player.grounded).is_true()
	assert_float(player.global_position.y).is_less(0.2)
	assert_float(player.up.dot(Vector3.UP)).is_greater(0.99)


func test_plain_jump_cannot_leave_the_rock() -> void:
	var side := CENTER + Vector3.RIGHT * (RADIUS + 0.05)
	var player := _player_at(side, Vector3.RIGHT)
	await _run(player, 10, Vector2.ZERO)
	await _run(player, 90, Vector2.ZERO, PlayerControls.Buttons.JUMP)
	assert_float(_height_over_rock(player)).is_less(0.5)
