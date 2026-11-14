extends GdUnitTestSuite
## The M5 encounter with the real world (arena, dummies, mobs, Warden): mobs chase and hit,
## the ranged mob's bolts hit and can be rolled through, killing the mobs raises the Warden
## with health for the player count, its slam hits in front only, phase 2 speeds it up and its
## well pulls, a fallen Warden opens the portal home, and an empty realm resets.

const DELTA := 1.0 / 30.0
const B := PlayerControls.Buttons

var _world: World
var _players: Array[SimPlayer] = []


func before_test() -> void:
	_world = auto_free(World.new(false)) as World
	add_child(_world)
	_players.clear()
	_add_player(Vector3(0, 0, -2))


func _add_player(at: Vector3) -> SimPlayer:
	var player := SimPlayer.new()
	player.peer_id = _players.size() + 1
	_world.players.add_child(player)
	player.place(at)
	_players.append(player)
	return player


func _mob(i: int) -> Mob:
	return _world.encounter.mobs[i]


func _boss() -> Warden:
	return _world.encounter.boss


## Ticks the encounter, every enemy and every player (players hold buttons and move).
func _run(ticks: int, buttons := 0, move := Vector2.ZERO) -> void:
	for i in ticks:
		await get_tree().physics_frame
		_world.encounter._rollback_tick(DELTA, 0, true)
		for node in get_tree().get_nodes_in_group(Enemy.GROUP):
			node.call("_rollback_tick", DELTA, 0, true)
		for player in _players:
			player.step(move, 0.0, buttons, DELTA)


func _kill_mobs() -> void:
	for mob in _world.encounter.mobs:
		mob.take_hit(10000.0, Vector3.ZERO)


func test_starts_with_mobs_at_their_posts_and_the_warden_hidden() -> void:
	assert_int(_world.encounter.phase).is_equal(Encounter.Phase.MOBS)
	assert_int(_world.encounter.mobs_left()).is_equal(3)
	for i in Layout.MOBS.size():
		assert_vector(_mob(i).global_position).is_equal_approx(
			Layout.MOBS[i][0], Vector3.ONE * 0.01
		)
	assert_int(_boss().action).is_equal(Enemy.Action.HIDDEN)
	assert_bool(_boss().alive()).is_false()


func test_melee_mob_chases_and_hits() -> void:
	var mob := _mob(0)
	_players[0].place(mob.global_position + Vector3(0, 0, -7))
	await _run(150)
	assert_float(_players[0].health).is_less(Tuning.data().max_health)
	assert_float(mob.global_position.distance_to(Layout.MOBS[0][0])).is_greater(3.0)


func test_mob_gives_up_beyond_its_leash() -> void:
	var mob := _mob(0)
	_players[0].place(mob.global_position + Vector3(0, 0, -7))
	await _run(30)
	_players[0].place(Vector3(0, 0, -40))
	await _run(240)
	assert_float(mob.global_position.distance_to(Layout.MOBS[0][0])).is_less(1.5)


func test_ranged_bolts_hit_a_standing_player() -> void:
	var shooter := _mob(2)
	_mob(0).take_hit(10000.0, Vector3.ZERO)
	_mob(1).take_hit(10000.0, Vector3.ZERO)
	_players[0].place(shooter.global_position + Vector3(0, 0, -11))
	await _run(150)
	assert_float(_players[0].health).is_less(Tuning.data().max_health)


func test_rolling_through_a_bolt_is_safe() -> void:
	var t := Tuning.data()
	var shooter := _mob(2)
	var player := _players[0]
	player.place(shooter.global_position + Vector3(0, 0, -6))
	shooter._fire(shooter.shot_def(), player.center())
	for i in 15:
		# Held inside the roll's i-frames while the bolt passes.
		player.action = SimPlayer.Action.ROLL
		player.action_time = Combat.ticks(t.roll_iframes_start) + 1
		shooter._fly_bolts(DELTA)
		player._defend(t)
	assert_float(player.health).is_equal(t.max_health)
	player.action = SimPlayer.Action.NONE
	shooter._fire(shooter.shot_def(), player.center())
	for i in 15:
		shooter._fly_bolts(DELTA)
		player._defend(t)
	assert_float(player.health).is_equal(t.max_health - shooter.shot_def().damage)


func test_killing_the_mobs_raises_the_warden_with_health_per_player() -> void:
	_add_player(Vector3(2, 0, -2))
	_kill_mobs()
	await _run(1)
	assert_int(_world.encounter.phase).is_equal(Encounter.Phase.BOSS)
	assert_int(_boss().action).is_equal(Enemy.Action.RISE)
	assert_float(_boss().max_health).is_equal(Warden.BASE_HEALTH * 1.5)
	assert_float(_boss().take_hit(50.0, Vector3.ZERO)).is_equal(0.0)
	await _run(Combat.ticks(Warden.RISE_TIME) + 1)
	assert_bool(_boss().alive()).is_true()
	assert_float(_boss().take_hit(50.0, Vector3.ZERO)).is_equal(50.0)


func test_slam_hits_in_front_only() -> void:
	var boss := _boss()
	boss.reset(Enemy.Action.IDLE)
	boss.attack = Warden.Move.SLAM
	boss.action = Enemy.Action.STRIKE
	var front := _players[0]
	var behind := _add_player(Vector3.ZERO)
	front.place(boss.global_position + boss.facing * 3.5)
	behind.place(boss.global_position - boss.facing * 2.5)
	front._defend(Tuning.data())
	behind._defend(Tuning.data())
	var full := Tuning.data().max_health
	assert_float(front.health).is_equal(full - Combat.attack(&"warden_slam").damage)
	assert_float(behind.health).is_equal(full)


func test_phase_two_speeds_up_and_the_well_pulls() -> void:
	var boss := _boss()
	boss.reset(Enemy.Action.IDLE)
	var calm := boss.windup_ticks()
	boss.health = boss.max_health * 0.4
	assert_bool(boss.phase_2()).is_true()
	assert_int(boss.windup_ticks()).is_less(calm)
	# Freeze it mid-recover so only the well acts on the player.
	boss.well_time = Combat.ticks(Warden.WELL_TIME)
	var player := _players[0]
	player.place(boss.global_position + Vector3(0, 0, -10))
	var start := player.global_position.distance_to(boss.global_position)
	for i in 45:
		await get_tree().physics_frame
		player.step(Vector2.ZERO, 0.0, 0, DELTA)
	assert_float(player.global_position.distance_to(boss.global_position)).is_less(start - 3.0)


func test_a_fallen_warden_opens_the_portal_home() -> void:
	_kill_mobs()
	await _run(Combat.ticks(Warden.RISE_TIME) + 2)
	_players[0].place(Vector3(0, 0, -30))
	_boss().take_hit(100000.0, Vector3.ZERO)
	await _run(1)
	assert_int(_world.encounter.phase).is_equal(Encounter.Phase.CLEARED)
	assert_bool(Encounter.won(_world)).is_true()
	# It stays open: no timer starts the realm over while players are in it.
	await _run(Combat.ticks(25.0))
	assert_int(_world.encounter.phase).is_equal(Encounter.Phase.CLEARED)
	var portal := Layout.portals()[2]
	_players[0].place(portal.position)
	await _run(1)
	assert_bool(Layout.on_hub(_players[0].global_position)).is_true()
	# The realm is empty now, so it resets for the next visit.
	await _run(1)
	assert_int(_world.encounter.phase).is_equal(Encounter.Phase.MOBS)
	assert_int(_world.encounter.mobs_left()).is_equal(3)
	assert_int(_boss().action).is_equal(Enemy.Action.HIDDEN)


func test_the_victory_portal_is_shut_before_the_warden_falls() -> void:
	_players[0].place(Layout.portals()[2].position)
	await _run(2)
	assert_bool(Layout.on_hub(_players[0].global_position)).is_false()


func test_the_keep_gate_leads_to_the_realm_and_the_home_portal_back() -> void:
	var player := _players[0]
	player.place(Layout.portals()[0].position)
	await _run(1)
	assert_float(player.global_position.distance_to(Layout.REALM_ARRIVAL)).is_less(
		Layout.SPAWN_RADIUS + 0.5
	)
	assert_int(player.respawns).is_equal(1)
	player.place(Layout.portals()[1].position)
	await _run(1)
	assert_bool(Layout.on_hub(player.global_position)).is_true()


func test_a_wipe_sends_everyone_home_and_resets_the_realm() -> void:
	_mob(0).take_hit(10000.0, Vector3.ZERO)
	await _run(2)
	_players[0].health = 0.0
	_players[0].action = SimPlayer.Action.DEAD
	_players[0].action_time = 0
	await _run(Combat.ticks(Tuning.data().death_time) + 2)
	assert_bool(Layout.on_hub(_players[0].global_position)).is_true()
	assert_int(_world.encounter.mobs_left()).is_equal(3)
	assert_int(_world.encounter.phase).is_equal(Encounter.Phase.MOBS)
