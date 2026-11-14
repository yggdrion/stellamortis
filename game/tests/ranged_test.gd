extends GdUnitTestSuite
## The crossbow: weapon switch, draw and release, bolts that fall with the local gravity, hit
## enemies for charge-scaled damage, and stop at walls.

const DELTA := 1.0 / 30.0
## Where the M2 dummies stood, north of the realm's arrival (they moved to the keep in M12;
## these tests keep the realm's walls and ground around them).
const DUMMY_AT := [Vector3(-4.0, 0.0, -10.0), Vector3(4.0, 0.0, -10.0)]
const B := PlayerControls.Buttons
const CROSSBOW := SimPlayer.Weapon.CROSSBOW

var _world: Node3D
var _player: SimPlayer
var _dummy: Enemy


func before_test() -> void:
	_world = auto_free(Node3D.new()) as Node3D
	add_child(_world)
	_world.add_child(Arena.new(false))
	_dummy = Enemy.new()
	_dummy.kind = Combat.enemy_kind(&"dummy")
	_dummy.passive = true
	_world.add_child(_dummy)
	_dummy.global_transform = Transform3D(SimPlayer.frame(Vector3.UP, Vector3.BACK), DUMMY_AT[0])
	_player = SimPlayer.new()
	_world.add_child(_player)
	_player.place(Vector3.ZERO)


## Stands at feet; yaw turns the look from -Z (reference forward) to the left.
func _stand(feet: Vector3, yaw := 0.0) -> void:
	_player.place(feet)
	await _run(5, 0, yaw)


func _run(ticks: int, buttons := 0, yaw := 0.0, pitch := 0.0) -> void:
	for i in ticks:
		await get_tree().physics_frame
		_dummy._rollback_tick(DELTA, 0, true)
		_player.step(Vector2.ZERO, yaw, buttons, DELTA, pitch, CROSSBOW)


## Draws for ticks, then releases.
func _shoot(draw_ticks: int, yaw := 0.0, pitch := 0.0) -> void:
	await _run(draw_ticks, B.ATTACK, yaw, pitch)
	await _run(1, 0, yaw, pitch)


func test_switches_to_crossbow() -> void:
	await _stand(Vector3.ZERO)
	assert_int(_player.weapon).is_equal(CROSSBOW)


func test_full_draw_hits_for_full_damage() -> void:
	await _stand(_dummy.global_position + Vector3.BACK * 8.0)
	var t := Tuning.data()
	await _shoot(Combat.ticks(t.draw_time) + 2)
	assert_float(_player.charge).is_equal(1.0)
	assert_int(_player.action).is_equal(SimPlayer.Action.SHOOT)
	await _run(20)
	assert_float(_dummy.health).is_equal_approx(_dummy.max_health - t.bolt_damage_max, 0.01)
	assert_int(_player.bolt_life[0]).is_equal(0)


func test_quick_shot_is_weak_and_cheap() -> void:
	await _stand(_dummy.global_position + Vector3.BACK * 6.0)
	var t := Tuning.data()
	await _shoot(1)
	assert_float(_player.stamina).is_less(t.max_stamina - t.bolt_stamina_min + 1.0)
	assert_float(_player.stamina).is_greater(t.max_stamina - t.bolt_stamina_max)
	await _run(25)
	assert_float(_dummy.health).is_greater(_dummy.max_health - t.bolt_damage_min - 2.0)
	assert_float(_dummy.health).is_less(_dummy.max_health)


## Height of a quick shot's bolt 10 ticks after release, relative to where it started.
func _drop_after_quick_shot(feet: Vector3, yaw: float) -> float:
	await _stand(feet, yaw)
	await _shoot(1, yaw)
	var start := _player.bolt_pos[0].dot(_player.up)
	await _run(10, 0, yaw)
	return _player.bolt_pos[0].dot(_player.up) - start


func test_low_gravity_bolts_fall_less() -> void:
	# Away from walls: west across open ground, and east inside the low-g zone.
	var normal: float = await _drop_after_quick_shot(Vector3(10, 0, 25), PI / 2.0)
	var low: float = await _drop_after_quick_shot(Vector3(30, 0, -15), -PI / 2.0)
	assert_float(normal).is_less(low - 0.2)


func test_bolt_stops_at_wall() -> void:
	# The wall at z = 45 is behind the spawn; yaw PI looks along +Z.
	await _stand(Vector3(0, 0, 38), PI)
	await _shoot(Combat.ticks(Tuning.data().draw_time) + 2, PI)
	await _run(20, 0, PI)
	assert_int(_player.bolt_life[0]).is_equal(0)
	assert_float(_player.bolt_pos[0].z).is_between(43.5, 45.0)


func test_no_stamina_no_shot() -> void:
	await _stand(Vector3.ZERO)
	_player.stamina = 0.0
	_player.stamina_wait = 100
	await _shoot(10)
	assert_int(_player.bolt_life[0]).is_equal(0)
	assert_int(_player.action).is_equal(SimPlayer.Action.NONE)
