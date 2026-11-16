extends GdUnitTestSuite
## Enemy behaviors of M22: the frontal guard (front hits reduced, flank hits not, a parry opens
## it), the leap (committed target point, lands as the windup ends) and enemy combos, plus the
## wire size with the new state. Test attacks are built here; the real kinds come later.

const DELTA := 1.0 / 30.0
const B := PlayerControls.Buttons

var _world: Node3D
var _player: SimPlayer
var _enemy: Enemy


func before_test() -> void:
	_world = auto_free(Node3D.new()) as Node3D
	add_child(_world)
	_world.add_child(Arena.new(false))
	_player = SimPlayer.new()
	_world.add_child(_player)
	_player.place(Vector3(0, 0, 10))
	_enemy = Enemy.new()
	_enemy.kind = Combat.enemy_kind(&"swordsman")
	# Own copy of the def: tests tune it without touching the shared resource.
	_enemy.def = _enemy.def.duplicate() as EnemyDef
	_world.add_child(_enemy)
	# Faces +Z, toward the player.
	_enemy.home = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	_enemy.reset(Enemy.Action.IDLE)


func _attack(id: StringName, props: Dictionary) -> void:
	var swing := AttackDef.new()
	for key: String in props:
		swing.set(key, props[key])
	Combat._attacks[id] = swing


func _run(ticks: int, buttons := 0) -> void:
	for i in ticks:
		await get_tree().physics_frame
		_enemy._rollback_tick(DELTA, 0, true)
		_player.step(Vector2.ZERO, 0.0, buttons, DELTA)


func _guard() -> void:
	_enemy.def.guard_arc = 120.0
	_enemy.def.guard_damage = 0.25


func test_front_hit_on_a_guard_is_reduced_and_flank_is_not() -> void:
	_guard()
	var front := _enemy.take_hit(40.0, Vector3(0, 0, 2), 6.0, 0.6)
	assert_float(front).is_equal(10.0)
	assert_int(_enemy.action).is_equal(Enemy.Action.GUARD)
	assert_float(_enemy.velocity.length()).is_equal(0.0)
	_enemy.reset(Enemy.Action.IDLE)
	var flank := _enemy.take_hit(40.0, Vector3(3, 0, 0.5), 0.0, 0.0)
	assert_float(flank).is_equal(40.0)
	assert_int(_enemy.action).is_equal(Enemy.Action.IDLE)
	_enemy.reset(Enemy.Action.IDLE)
	assert_float(_enemy.take_hit(40.0, Vector3(0, 0, -2))).is_equal(40.0)


func test_guard_is_open_while_striking_or_staggered() -> void:
	_guard()
	_enemy.health = 1000.0
	_enemy._set_action(Enemy.Action.STRIKE)
	assert_float(_enemy.take_hit(40.0, Vector3(0, 0, 2))).is_equal(40.0)
	_enemy._set_action(Enemy.Action.RECOVER)
	assert_float(_enemy.take_hit(40.0, Vector3(0, 0, 2))).is_equal(40.0)
	_enemy.parry()
	assert_float(_enemy.take_hit(10.0, Vector3(0, 0, 2))).is_equal(10.0 * _enemy.def.riposte)
	# A winding-up guard still blocks, without being interrupted.
	_enemy._set_action(Enemy.Action.WINDUP)
	assert_float(_enemy.take_hit(40.0, Vector3(0, 0, 2), 0.0, 1.0)).is_equal(10.0)
	assert_int(_enemy.action).is_equal(Enemy.Action.WINDUP)


func test_guard_reaction_ends() -> void:
	_guard()
	_enemy.take_hit(40.0, Vector3(0, 0, 2))
	await _run(Combat.ticks(_enemy.def.guard_react) + 1)
	assert_int(_enemy.action).is_not_equal(Enemy.Action.GUARD)


func test_player_sword_and_bolt_hit_the_guard() -> void:
	_guard()
	_player.place(Vector3(0, 0, 1.6))
	_player.facing = Vector3.FORWARD
	_player.ref_forward = Vector3.FORWARD
	await _run(1, B.ATTACK)
	await _run(25)
	var swing := Combat.attack(&"light_1")
	assert_float(_enemy.health).is_equal(_enemy.max_health - swing.damage * 0.25)
	var before := _enemy.health
	_enemy.reset(Enemy.Action.IDLE)
	_enemy.take_hit(40.0, Vector3(0, 0, 5), Tuning.data().bolt_knockback)
	assert_float(_enemy.health).is_equal(_enemy.max_health - 10.0)
	assert_float(before).is_greater(0.0)


func test_player_parry_opens_the_attacker() -> void:
	_attack(&"test_chop", {"windup": 0.2, "active": 0.2, "recover": 0.4, "damage": 10.0})
	_enemy.def.attacks = [&"test_chop"] as Array[StringName]
	_player.place(Vector3(0, 0, 1.4))
	_player.facing = Vector3.FORWARD
	_player.ref_forward = Vector3.FORWARD
	_enemy._start_attack(0)
	await _run(Combat.ticks(0.2) - 2, B.BLOCK)
	await _run(8, B.BLOCK)
	assert_int(_enemy.action).is_equal(Enemy.Action.STAGGER)
	assert_bool(_enemy.parried).is_true()


func _leap_setup() -> void:
	_attack(
		&"test_leap",
		{"windup": 0.8, "active": 0.15, "recover": 0.5, "damage": 20.0, "leap": 8.0, "reach": 2.0}
	)
	_enemy.def.attacks = [&"test_leap"] as Array[StringName]


func test_leap_lands_on_the_target_point_and_hits_who_stood() -> void:
	_leap_setup()
	_player.place(Vector3(0, 0, 6))
	_enemy._start_attack(0)
	assert_vector(_enemy.leap_to).is_equal_approx(Vector3(0, 0, 6), Vector3.ONE * 0.1)
	await _run(Combat.ticks(0.8))
	assert_float(_enemy.global_position.distance_to(Vector3(0, 0, 6))).is_less(0.8)
	await _run(Combat.ticks(0.3))
	assert_float(_player.health).is_less(Tuning.data().max_health)


func test_leap_misses_who_moved_off_the_point() -> void:
	_leap_setup()
	_player.place(Vector3(0, 0, 6))
	_enemy._start_attack(0)
	await _run(10)
	_player.place(Vector3(7, 0, 6))
	await _run(Combat.ticks(1.2))
	assert_float(_player.health).is_equal(Tuning.data().max_health)


func test_leap_is_capped_at_its_distance() -> void:
	_leap_setup()
	_player.place(Vector3(0, 0, 30))
	_enemy._start_attack(0)
	assert_float(_enemy.leap_to.distance_to(Vector3.ZERO)).is_equal_approx(8.0, 0.01)


func test_combo_chains_the_next_attack_without_recovery() -> void:
	_attack(&"test_a", {"windup": 0.2, "active": 0.1, "recover": 0.6, "next": &"test_b"})
	_attack(&"test_b", {"windup": 0.2, "active": 0.1, "recover": 0.6})
	_enemy.def.attacks = [&"test_a", &"test_b"] as Array[StringName]
	_player.place(Vector3(0, 0, 20))
	_enemy._start_attack(0)
	await _run(Combat.ticks(0.3) + 1)
	assert_int(_enemy.attack).is_equal(1)
	assert_int(_enemy.action).is_equal(Enemy.Action.WINDUP)
	await _run(Combat.ticks(0.3) + 1)
	assert_int(_enemy.action).is_equal(Enemy.Action.RECOVER)


func test_leap_state_round_trips_and_stays_small() -> void:
	var slot := auto_free(Enemy.new()) as Enemy
	slot.kind = Combat.enemy_kind(&"warden")
	slot.make_bolts(10)
	var plain := slot.net_combat.size()
	slot.action = Enemy.Action.WINDUP
	slot.parried = true
	slot.leap_to = Vector3(4, -2, 7.5)
	var bytes := slot.net_combat
	assert_int(bytes.size()).is_equal(plain + 12)
	var other := auto_free(Enemy.new()) as Enemy
	other.make_bolts(10)
	other.net_combat = bytes
	assert_vector(other.leap_to).is_equal(slot.leap_to)
	assert_bool(other.parried).is_true()
	slot.leap_to = Vector3.ZERO
	other.net_combat = slot.net_combat
	assert_vector(other.leap_to).is_equal(Vector3.ZERO)
	assert_int(bytes.size()).is_less(508 - 32)


## The real kinds (task 2): every one loads with attacks that exist, and plays as designed.
func test_every_kind_loads_with_its_attacks() -> void:
	for kind in Combat.ENEMY_KINDS.size():
		var def := Combat.enemy_def(kind)
		assert_object(def).is_not_null()
		for id in def.attacks:
			assert_object(Combat.attack(id)).is_not_null()
	var elite := Combat.enemy_def(Combat.enemy_kind(&"barrow_elite"))
	assert_object(Combat.attack(elite.attacks[0]).next).is_equal(elite.attacks[1])


func _kind(id: StringName) -> void:
	_enemy.kind = Combat.enemy_kind(id)
	_enemy.reset(Enemy.Action.IDLE)


func test_shield_bearer_guards_its_front_and_the_bash_is_parryable() -> void:
	_kind(&"shield_bearer")
	var def := _enemy.def
	assert_float(_enemy.take_hit(40.0, Vector3(0, 0, 2))).is_equal(40.0 * def.guard_damage)
	_enemy.reset(Enemy.Action.IDLE)
	assert_float(_enemy.take_hit(40.0, Vector3(3, 0, -0.5))).is_equal(40.0)
	assert_bool(Combat.attack(def.attacks[0]).parryable).is_true()


func test_berserker_leaps_from_a_distance_and_hacks_up_close() -> void:
	_kind(&"berserker")
	_enemy.home = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	_player.place(Vector3(0, 0, 7))
	_enemy.action_time = 100
	await _run(1)
	assert_int(_enemy.action).is_equal(Enemy.Action.WINDUP)
	assert_int(_enemy.attack).is_equal(1)
	assert_float(Combat.attack(&"berserker_leap").recover).is_greater(1.0)
	_enemy.reset(Enemy.Action.IDLE)
	_player.place(Vector3(0, 0, 1.5))
	_enemy.action_time = 100
	await _run(1)
	assert_int(_enemy.attack).is_equal(0)


func test_leap_hits_who_stood_and_misses_a_roll_away() -> void:
	_kind(&"berserker")
	_player.place(Vector3(0, 0, 7))
	_enemy._start_attack(1)
	await _run(Combat.ticks(1.2))
	assert_float(_player.health).is_less(Tuning.data().max_health)


func test_elite_combos_and_slams_from_range() -> void:
	_kind(&"barrow_elite")
	_player.place(Vector3(0, 0, 2.0))
	_enemy.action_time = 100
	await _run(1)
	assert_int(_enemy.attack).is_equal(0)
	var cleave := Combat.attack(&"elite_cleave")
	await _run(Combat.ticks(cleave.windup + cleave.active) + 1)
	assert_int(_enemy.attack).is_equal(1)
	assert_int(_enemy.action).is_equal(Enemy.Action.WINDUP)
	_enemy.reset(Enemy.Action.IDLE)
	_player.place(Vector3(0, 0, 4.5))
	_enemy.action_time = 100
	await _run(1)
	assert_int(_enemy.attack).is_equal(2)
	assert_float(Combat.attack(&"elite_slam").offset).is_greater(0.0)
