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


## The Roll clip plants the feet at 60 % of its length and stands up in place. Without a
## direction held the body has to stop there too, or the standing model glides over the ground.
func test_roll_stops_where_the_model_stands_up() -> void:
	var t := Tuning.data()
	var from := _player.global_position
	await _run(1, B.ROLL, Vector2(0, 1))
	var planted := from
	while _player.action == SimPlayer.Action.ROLL:
		if _player.action_time == SimPlayer.roll_travel_ticks(t) + 2:
			planted = _player.global_position
		await _run(1)
	var rolled := _player.global_position
	# Two ticks of braking after the travel, then nothing.
	assert_float(rolled.distance_to(planted)).is_less(0.05)
	# The roll still covers ground.
	assert_float(rolled.distance_to(from)).is_greater(3.8)


## With a direction held the roll runs into walking: no standstill between them.
func test_roll_walks_on_with_a_direction_held() -> void:
	var t := Tuning.data()
	var forward := Vector2(0, 1)
	await _run(1, B.ROLL, forward)
	var slowest := INF
	while _player.action == SimPlayer.Action.ROLL:
		slowest = minf(slowest, _player.velocity.length())
		await _run(1, 0, forward)
	assert_float(slowest).is_greater(t.walk_speed - 0.5)
	assert_float(_player.velocity.length()).is_equal_approx(t.walk_speed, 0.5)


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


## A melee mob standing at `at` (its post), out of the other bodies' way.
func _mob(at: Vector3) -> Mob:
	var mob := Mob.new()
	mob.index = 2
	mob.make_melee()
	mob.facing = Vector3.BACK
	_world.add_child(mob)
	mob.home = Transform3D(SimPlayer.frame(Vector3.UP, mob.facing), at)
	mob.global_transform = mob.home
	return mob


func _run_mob(mob: Enemy, ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame
		mob._rollback_tick(DELTA, 0, true)


## How far a hit from the north pushes the mob at its post, at most.
func _push(mob: Mob, attack_id: StringName) -> float:
	var def := Combat.attack(attack_id)
	mob.take_hit(def.damage, mob.global_position + Vector3.FORWARD * 3.0, def.knockback, def.flinch)
	var farthest := 0.0
	for i in 20:
		await _run_mob(mob, 1)
		farthest = maxf(farthest, mob.global_position.distance_to(mob.home.origin))
	return farthest


func test_heavy_pushes_a_mob_further_than_a_light() -> void:
	var mob := _mob(Vector3(0, 0, -30))
	var light := await _push(mob, &"light_1")
	mob.reset(Enemy.Action.IDLE)
	var heavy := await _push(mob, &"heavy")
	assert_float(light).is_greater(0.2)
	assert_float(heavy).is_greater(light * 2.0)


## The mob stands next to the player and winds up a swing; returns it at its first windup tick.
func _winding_mob() -> Mob:
	var mob := _mob(Vector3(0, 0, -1.6))
	for i in 60:
		if mob.action == Enemy.Action.WINDUP:
			break
		await _run_mob(mob, 1)
	assert_int(mob.action).is_equal(Enemy.Action.WINDUP)
	return mob


func test_flinch_delays_a_mob_windup() -> void:
	var heavy := Combat.attack(&"heavy")
	var windup := Combat.attack(&"mob_chop").windup_ticks()
	var undisturbed := await _winding_mob()
	await _run_mob(undisturbed, windup)
	assert_int(undisturbed.action).is_equal(Enemy.Action.STRIKE)
	var hit := await _winding_mob()
	hit.take_hit(heavy.damage, Vector3(0, 0, 3), heavy.knockback, heavy.flinch)
	assert_int(hit.action).is_equal(Enemy.Action.FLINCH)
	await _run_mob(hit, windup)
	assert_int(hit.action).is_not_equal(Enemy.Action.STRIKE)
	assert_int(hit.action).is_not_equal(Enemy.Action.WINDUP)


func test_a_light_flinch_does_not_interrupt_a_windup() -> void:
	var light := Combat.attack(&"light_1")
	var mob := await _winding_mob()
	mob.take_hit(light.damage, Vector3(0, 0, 3), light.knockback, light.flinch)
	assert_int(mob.action).is_equal(Enemy.Action.WINDUP)


func test_the_warden_does_not_flinch() -> void:
	var boss := Warden.new()
	boss.index = 3
	_world.add_child(boss)
	boss.global_position = Vector3(0, 0, -30)
	var heavy := Combat.attack(&"heavy")
	for action in [Enemy.Action.IDLE, Enemy.Action.WINDUP]:
		boss._set_action(action)
		boss.take_hit(heavy.damage, Vector3(0, 0, -25), heavy.knockback, heavy.flinch)
		assert_int(boss.action).is_equal(action)
	# It only slides a little.
	assert_float(boss.velocity.length()).is_between(0.1, heavy.knockback * 0.4)


## The player's speed in the tick an unarmed dummy's swing lands.
func _hit_speed(buttons: int) -> float:
	_player.velocity = Vector3.ZERO
	_player.invulnerable = 0
	_player.health = Tuning.data().max_health
	_swinger._set_action(Enemy.Action.IDLE)
	_face(_swinger)
	for i in 200:
		await _run(1, buttons)
		if _player.invulnerable > 0:
			break
	return _player.velocity.length()


func test_a_blocked_hit_pushes_the_player_less() -> void:
	var unguarded := await _hit_speed(0)
	var blocked := await _hit_speed(B.BLOCK)
	assert_float(unguarded).is_equal_approx(Combat.attack(&"dummy_swing").knockback, 0.5)
	assert_float(blocked).is_equal_approx(unguarded * Tuning.data().block_knockback, 0.5)


## Replaying a hit from the same state (what a rollback does) lands the mob in the same place.
func test_rollback_replay_of_a_hit_is_deterministic() -> void:
	var mob := _mob(Vector3(0, 0, -30))
	var heavy := Combat.attack(&"heavy")
	var start := [mob.global_transform, mob.velocity, mob.facing, mob.health]
	var ends := []
	for run in 2:
		mob.global_transform = start[0]
		mob.velocity = start[1]
		mob.facing = start[2]
		mob.health = start[3]
		mob._set_action(Enemy.Action.IDLE)
		mob.take_hit(heavy.damage, Vector3(0, 0, -33), heavy.knockback, heavy.flinch)
		await _run_mob(mob, 25)
		ends.append([mob.global_position, mob.velocity, mob.action, mob.action_time, mob.health])
	assert_vector(ends[1][0]).is_equal(ends[0][0])
	assert_that(ends[1]).is_equal(ends[0])
	assert_float(mob.global_position.distance_to(mob.home.origin)).is_greater(0.5)


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
