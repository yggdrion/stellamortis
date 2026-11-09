extends GdUnitTestSuite
## Player combat against the training dummies, with the real arena: attacks hit once per swing,
## combos chain, rolls dodge, blocks and parries work, stamina gates actions, death respawns.

const DELTA := 1.0 / 30.0
## Where the M2 dummies stood, north of the realm's arrival (they moved to the keep in M12;
## these tests keep the realm's walls and ground around them).
const DUMMY_AT := [Vector3(-4.0, 0.0, -10.0), Vector3(4.0, 0.0, -10.0)]
const B := PlayerControls.Buttons

var _world: Node3D
var _player: SimPlayer
var _passive: TrainingDummy
var _swinger: TrainingDummy


func before_test() -> void:
	_world = auto_free(Node3D.new()) as Node3D
	add_child(_world)
	_world.add_child(Arena.new(false))
	_passive = _dummy(0, DUMMY_AT[0], true)
	_swinger = _dummy(1, DUMMY_AT[1], false)
	_player = SimPlayer.new()
	_world.add_child(_player)
	_player.place(Vector3(0, 0, 0))


func _dummy(index: int, at: Vector3, passive: bool) -> TrainingDummy:
	var dummy := TrainingDummy.new()
	dummy.index = index
	dummy.passive = passive
	dummy.facing = Vector3.BACK
	_world.add_child(dummy)
	dummy.global_transform = Transform3D(SimPlayer.frame(Vector3.UP, dummy.facing), at)
	return dummy


## Puts the player in front of a dummy (between it and the spawn), facing it.
func _face(dummy: TrainingDummy, distance := 1.6) -> void:
	_player.place(dummy.global_position + Vector3.BACK * distance)
	_player.facing = Vector3.FORWARD
	_player.ref_forward = Vector3.FORWARD


## Runs ticks of player then dummies (the order netfox uses: dummies registered first, but the
## order within a tick does not change these outcomes), each input held for its ticks.
func _run(ticks: int, buttons := 0, move := Vector2.ZERO) -> void:
	for i in ticks:
		await get_tree().physics_frame
		_passive._rollback_tick(DELTA, 0, true)
		_swinger._rollback_tick(DELTA, 0, true)
		_player.step(move, 0.0, buttons, DELTA)


func _press(button: int, hold := 1) -> void:
	await _run(hold, button)


func test_light_hits_once_per_swing() -> void:
	_face(_passive)
	await _press(B.ATTACK)
	await _run(25)
	assert_float(_passive.health).is_equal(_passive.max_health - Combat.attack(&"light_1").damage)
	assert_int(_player.action).is_equal(SimPlayer.Action.NONE)


func test_combo_chains_three_lights() -> void:
	_face(_passive)
	var expected := _passive.max_health
	for id: StringName in [&"light_1", &"light_2", &"light_3"]:
		await _press(B.ATTACK)
		await _run(Combat.attack(id).active_end_ticks() + 1)
		expected -= Combat.attack(id).damage
	assert_float(_passive.health).is_equal_approx(expected, 0.01)
	assert_int(_player.attack).is_equal(2)


func test_attacks_cost_stamina_and_zero_stamina_blocks_them() -> void:
	_face(_passive)
	_player.stamina = 0.0
	_player.stamina_wait = 100
	await _press(B.ATTACK)
	assert_int(_player.action).is_equal(SimPlayer.Action.NONE)
	_player.stamina = 50.0
	await _press(B.HEAVY)
	assert_int(_player.action).is_equal(SimPlayer.Action.ATTACK)
	assert_float(_player.stamina).is_equal(50.0 - Combat.attack(&"heavy").stamina)


func test_unguarded_hit_staggers_and_hurts() -> void:
	_face(_swinger)
	await _run(Combat.ticks(TrainingDummy.REST) + 40)
	assert_float(_player.health).is_equal(
		Tuning.data().max_health - Combat.attack(&"dummy_swing").damage
	)


func test_roll_dodges_the_swing() -> void:
	_face(_swinger)
	var def := Combat.attack(&"dummy_swing")
	# Wait until the dummy is a few ticks from striking, then roll toward it (through the hit).
	while not (
		_swinger.action == Enemy.Action.WINDUP and _swinger.action_time >= def.windup_ticks() - 4
	):
		await _run(1)
	await _press(B.ROLL, 1)
	await _run(30, 0, Vector2(0, 1))
	assert_float(_player.health).is_equal(Tuning.data().max_health)


func test_block_takes_chip_damage_and_stamina() -> void:
	_face(_swinger)
	await _run(1, B.BLOCK)
	# Hold the block long before the strike: past the parry window.
	while _swinger.action != Enemy.Action.RECOVER:
		await _run(1, B.BLOCK)
	var t := Tuning.data()
	var damage := Combat.attack(&"dummy_swing").damage
	assert_float(_player.health).is_equal_approx(
		t.max_health - damage * (1 - t.block_reduction), 0.01
	)
	assert_float(_player.stamina).is_less(t.max_stamina)
	assert_int(_swinger.action).is_equal(Enemy.Action.RECOVER)


func test_parry_staggers_and_riposte_hits_harder() -> void:
	_face(_swinger)
	var def := Combat.attack(&"dummy_swing")
	while not (
		_swinger.action == Enemy.Action.WINDUP and _swinger.action_time >= def.windup_ticks() - 2
	):
		await _run(1)
	# Block right before the strike: inside the parry window.
	while _swinger.action != Enemy.Action.STAGGER and _swinger.action != Enemy.Action.RECOVER:
		await _run(1, B.BLOCK)
	assert_int(_swinger.action).is_equal(Enemy.Action.STAGGER)
	assert_bool(_swinger.parried).is_true()
	assert_float(_player.health).is_equal(Tuning.data().max_health)
	await _run(1)
	await _press(B.ATTACK)
	await _run(20)
	var riposte := Combat.attack(&"light_1").damage * _swinger.riposte
	assert_float(_swinger.health).is_equal_approx(_swinger.max_health - riposte, 0.01)


func test_death_and_respawn() -> void:
	_face(_swinger)
	_player.health = 1.0
	await _run(Combat.ticks(TrainingDummy.REST) + 40)
	assert_int(_player.action).is_equal(SimPlayer.Action.DEAD)
	await _run(Combat.ticks(Tuning.data().death_time) + 2)
	assert_int(_player.action).is_equal(SimPlayer.Action.NONE)
	assert_float(_player.health).is_equal(Tuning.data().max_health)
	assert_int(_player.respawns).is_equal(1)
	assert_float(_player.global_position.distance_to(_swinger.global_position)).is_greater(5.0)


func test_in_arc() -> void:
	var o := Vector3.ZERO
	(
		assert_bool(Combat.in_arc(o, Vector3.FORWARD, Vector3.UP, 2, 90, Vector3(0, 0, -2.3), 0.4))
		. is_true()
	)
	(
		assert_bool(Combat.in_arc(o, Vector3.FORWARD, Vector3.UP, 2, 90, Vector3(0, 0, 2), 0.4))
		. is_false()
	)
	(
		assert_bool(Combat.in_arc(o, Vector3.FORWARD, Vector3.UP, 2, 90, Vector3(0, 0, -2.5), 0.4))
		. is_false()
	)
	(
		assert_bool(
			Combat.in_arc(o, Vector3.FORWARD, Vector3.UP, 2, 90, Vector3(1.2, 0, -1.2), 0.1)
		)
		. is_true()
	)
