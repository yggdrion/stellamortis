extends GdUnitTestSuite
## The boss fight of M22 on the Barrowlands, with the real world: the Warden waits hidden in its
## reserved pool slot until a player enters the ring of the boss site, rises with health for the
## players inside, resets when nobody living is within reach, and when it falls the world flag is
## set for good (a late joiner gets it with the encounter's state). The fight happens on curved
## ground: the slam hits in front only, bolts fly under the realm's pull, the well drags players
## along the ground, and gates read the flag.

const DELTA := 1.0 / 30.0
const SEED := 1234
const B := PlayerControls.Buttons

var _world: World
var _site: BossSite
var _players: Array[SimPlayer] = []


func after_test() -> void:
	Layout.set_world_seed(0)


func before_test() -> void:
	_world = _build()
	_site = _world.encounter.site
	_players.clear()
	_add_player(_ground(30.0))


func _build() -> World:
	var world := auto_free(World.new(false)) as World
	add_child(world)
	world.build(SEED, "test")
	# The ground of the fight stands; no streaming (and none of its checks) while tests move bodies.
	world.chunks.anchors = func() -> Array: return []
	world.chunks.ensure_around(world.encounter.site.center(), 36.0)
	return world


func _add_player(at: Vector3) -> SimPlayer:
	var player := SimPlayer.new()
	player.peer_id = _players.size() + 1
	_world.players.add_child(player)
	player.place(at)
	_players.append(player)
	return player


func _east() -> Vector3:
	var up := _site.direction
	return up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()


## A spot on the ground this many meters from the ring's center (along the ground).
func _ground(meters: float, side := 0.0) -> Vector3:
	var up := _site.direction
	var realm := _site.realm
	var north := up.cross(_east())
	var toward := (up * realm.radius + _east() * meters + north * side).normalized()
	return Terrain.surface(realm, SEED, toward) + toward * 0.1


func _boss() -> Enemy:
	return _world.encounter.boss


func _fight() -> Encounter:
	return _world.encounter


## Ticks the encounter, every enemy and every player (players hold buttons and move).
func _run(ticks: int, buttons := 0, move := Vector2.ZERO) -> void:
	for i in ticks:
		await get_tree().physics_frame
		_fight()._rollback_tick(DELTA, 0, true)
		for node in get_tree().get_nodes_in_group(Enemy.GROUP):
			node.call("_rollback_tick", DELTA, 0, true)
		for player in _players:
			player.step(move, 0.0, buttons, DELTA)


## Raises the Warden with one player in the ring and lets it finish rising.
func _raise() -> void:
	_players[0].place(_ground(4.0))
	await _run(1)
	await _run(Combat.ticks(_boss().def.rise_time) + 1)


func test_the_warden_waits_hidden_at_the_site() -> void:
	assert_int(_fight().phase).is_equal(Encounter.Phase.IDLE)
	assert_int(_boss().action).is_equal(Enemy.Action.HIDDEN)
	assert_bool(_boss().alive()).is_false()
	assert_str(_boss().name).is_equal("Pool0")
	assert_vector(_boss().home.origin).is_equal_approx(
		_site.center() + _site.direction * Spawner.LIFT, Vector3.ONE * 0.01
	)
	assert_vector(_boss().home.basis.y).is_equal_approx(_site.direction, Vector3.ONE * 0.001)
	assert_array(_world.flags()).is_empty()
	await _run(30)
	assert_int(_fight().phase).is_equal(Encounter.Phase.IDLE)


func test_entering_the_ring_raises_the_warden() -> void:
	# Within reach of the fight but outside the ring: nothing happens.
	_players[0].place(_ground(BossSite.RING_RADIUS + 4.0))
	await _run(5)
	assert_int(_fight().phase).is_equal(Encounter.Phase.IDLE)
	_players[0].place(_ground(BossSite.RING_RADIUS - 3.0))
	await _run(1)
	assert_int(_fight().phase).is_equal(Encounter.Phase.BOSS)
	assert_int(_boss().action).is_equal(Enemy.Action.RISE)
	assert_float(_boss().max_health).is_equal(_boss().def.health)
	# It cannot be hurt while it rises, then it can.
	assert_float(_boss().take_hit(50.0, Vector3.ZERO)).is_equal(0.0)
	await _run(Combat.ticks(_boss().def.rise_time) + 1)
	assert_bool(_boss().alive()).is_true()
	assert_float(_boss().take_hit(50.0, Vector3.ZERO)).is_equal(50.0)


func test_health_scales_with_the_players_in_the_ring() -> void:
	_add_player(_ground(2.0))
	_add_player(_ground(0.0, 3.0))
	# A fourth one outside the ring does not count.
	_add_player(_ground(BossSite.RING_RADIUS + 8.0))
	_players[0].place(_ground(4.0))
	await _run(1)
	assert_int(_fight().phase).is_equal(Encounter.Phase.BOSS)
	assert_float(_boss().max_health).is_equal(_boss().def.health * 2.0)
	assert_float(_boss().health).is_equal(_boss().max_health)


func test_leaving_resets_the_fight() -> void:
	await _raise()
	var boss := _boss()
	boss.take_hit(100.0, Vector3.ZERO)
	assert_float(boss.health).is_less(boss.max_health)
	# Out of the ring but still within reach: the fight goes on.
	_players[0].place(_ground(BossSite.RING_RADIUS + 30.0))
	await _run(10)
	assert_int(_fight().phase).is_equal(Encounter.Phase.BOSS)
	# Beyond reach (nobody falls through: no chunk there, but a few ticks only).
	_players[0].place(_ground(BossSite.REACH + 20.0))
	await _run(1)
	assert_int(_fight().phase).is_equal(Encounter.Phase.IDLE)
	assert_int(boss.action).is_equal(Enemy.Action.HIDDEN)
	assert_vector(boss.global_position).is_equal_approx(boss.home.origin, Vector3.ONE * 0.01)
	# And it rises again, with full health, when someone comes back.
	_players[0].place(_ground(3.0))
	await _run(1)
	assert_int(_fight().phase).is_equal(Encounter.Phase.BOSS)
	assert_float(boss.health).is_equal(boss.max_health)


func test_a_wipe_resets_the_fight() -> void:
	await _raise()
	_players[0].health = 0.0
	_players[0].action = SimPlayer.Action.DEAD
	_players[0].action_time = 0
	await _run(1)
	assert_int(_fight().phase).is_equal(Encounter.Phase.IDLE)
	assert_int(_boss().action).is_equal(Enemy.Action.HIDDEN)
	# The dead do not raise it either, standing in the ring.
	await _run(5)
	assert_int(_fight().phase).is_equal(Encounter.Phase.IDLE)


func test_the_kill_sets_the_flag_for_good() -> void:
	await _raise()
	assert_bool(Encounter.flag_set(_world, &"warden_fallen")).is_false()
	_boss().take_hit(100000.0, Vector3.ZERO)
	await _run(1)
	assert_int(_fight().phase).is_equal(Encounter.Phase.CLEARED)
	assert_bool(Encounter.flag_set(_world, &"warden_fallen")).is_true()
	assert_array(_world.flags()).is_equal([&"warden_fallen"])
	# Everyone leaves, and long after nothing starts it over.
	_players[0].place(_ground(BossSite.REACH + 20.0))
	await _run(Combat.ticks(3.0))
	assert_int(_fight().phase).is_equal(Encounter.Phase.CLEARED)
	assert_bool(Encounter.flag_set(_world, &"warden_fallen")).is_true()
	assert_bool(Encounter.flag_set(_world, &"something_else")).is_false()


func test_a_late_joiner_gets_the_flag_with_the_state() -> void:
	await _raise()
	_boss().take_hit(100000.0, Vector3.ZERO)
	await _run(1)
	# A second world is a client that joins now: netfox hands it the synchronized state.
	Layout.set_world_seed(0)
	var late := _build()
	assert_array(late.flags()).is_empty()
	Wire.unpack(late.encounter, Encounter.STATE, Wire.pack(_fight(), Encounter.STATE))
	late.encounter.boss.net_combat = _boss().net_combat
	assert_array(late.flags()).is_equal([&"warden_fallen"])
	assert_int(late.encounter.boss.action).is_equal(Enemy.Action.DOWN)


func test_a_gate_opens_with_the_flag() -> void:
	var gate := Portal.at(_ground(60.0), Vector3.ZERO, Vector3.BACK, "To nowhere", &"warden_fallen")
	gate.realm = _site.realm.id
	gate.up = _site.direction
	assert_bool(gate.is_open(_world)).is_false()
	(
		assert_bool(Portal.at(Vector3.ZERO, Vector3.ZERO, Vector3.BACK, "Open").is_open(_world))
		. is_true()
	)
	await _raise()
	_boss().take_hit(100000.0, Vector3.ZERO)
	await _run(1)
	assert_bool(gate.is_open(_world)).is_true()
	# Stepping into it moves a player to the realm's arrival ring, once the flag is set.
	Layout.portals().append(gate)
	var player := _players[0]
	player.place(gate.position)
	await _run(1)
	assert_float(player.global_position.distance_to(Layout.spawn_point(1))).is_less(0.01)


func test_a_shut_gate_stays_shut() -> void:
	var gate := Portal.at(_ground(30.0), Vector3.ZERO, Vector3.BACK, "To nowhere", &"warden_fallen")
	gate.realm = _site.realm.id
	gate.up = _site.direction
	Layout.portals().append(gate)
	var player := _players[0]
	player.place(gate.position)
	await _run(2)
	assert_float(player.global_position.distance_to(gate.position)).is_less(1.0)


func test_slam_hits_in_front_only_on_the_curved_ground() -> void:
	await _raise()
	var boss := _boss()
	boss.attack = Warden.Move.SLAM
	boss.action = Enemy.Action.STRIKE
	assert_float(boss.up.angle_to(Vector3.UP)).is_greater(0.1)
	var front := _players[0]
	var behind := _add_player(Vector3.ZERO)
	var ahead := boss.facing
	front.place(boss.global_position + ahead * 3.5)
	behind.place(boss.global_position - ahead * 2.5)
	front._defend(Tuning.data())
	behind._defend(Tuning.data())
	var full := Tuning.data().max_health
	assert_float(front.health).is_equal(full - Combat.attack(&"warden_slam").damage)
	assert_float(behind.health).is_equal(full)


func test_volley_bolts_fly_under_the_realms_pull_and_hit() -> void:
	await _raise()
	var boss := _boss()
	var player := _players[0]
	# Inside the ring: its stones are solid and stop bolts.
	player.place(_ground(6.0, 4.0))
	boss._fire(boss.shot_def(), player.center())
	for i in 40:
		boss._fly_bolts(DELTA)
		player._defend(Tuning.data())
	assert_float(player.health).is_less(Tuning.data().max_health)


func test_phase_two_speeds_up_and_the_well_pulls_along_the_ground() -> void:
	await _raise()
	var boss := _boss()
	var calm := boss.windup_ticks()
	boss.health = boss.max_health * 0.4
	assert_bool(boss.phase_2()).is_true()
	assert_int(boss.windup_ticks()).is_less(calm)
	# Freeze it mid-recover so only the well acts on the player.
	boss.reset(Enemy.Action.IDLE)
	boss.health = boss.max_health * 0.4
	boss.well_time = Combat.ticks(boss.def.well_time)
	var player := _players[0]
	player.place(boss.global_position + boss.facing * 10.0)
	var start := player.global_position.distance_to(boss.global_position)
	for i in 45:
		await get_tree().physics_frame
		player.step(Vector2.ZERO, 0.0, 0, DELTA)
	assert_float(player.global_position.distance_to(boss.global_position)).is_less(start - 3.0)
	# Along the ground, not through it: still standing on it.
	var local := player.global_position - _site.realm.center
	var ground := _site.realm.radius + Terrain.height(_site.realm, SEED, local.normalized())
	assert_float(local.length() - ground).is_between(-0.1, 0.6)
	assert_bool(player.grounded).is_true()


func test_the_warden_walks_the_ground_toward_a_player() -> void:
	await _raise()
	var boss := _boss()
	var player := _players[0]
	player.place(_ground(0.0, 16.0))
	var start := boss.global_position.distance_to(player.global_position)
	await _run(120)
	assert_float(boss.global_position.distance_to(player.global_position)).is_less(start - 4.0)
	var local := boss.global_position - _site.realm.center
	var ground := _site.realm.radius + Terrain.height(_site.realm, SEED, local.normalized())
	assert_float(local.length() - ground).is_between(-0.1, 0.5)
