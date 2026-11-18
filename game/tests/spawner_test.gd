extends GdUnitTestSuite
## The M21 spawner on the real world: camps and roamers from the seed, waking near players,
## sleeping when they leave, a full pool, fights, cleared camps, late joiners and the ground
## under woken enemies.

const SEED := 1234
const DELTA := 1.0 / 30.0
## Tick numbers the spawner acts on are multiples of PERIOD; the first is above 0.
const FAR := 250.0

var _world: World
var _realm: RealmDef
var _spawner: Spawner
var _player: SimPlayer
var _tick := Spawner.PERIOD


func before_test() -> void:
	_realm = Layout.realms()[0]
	_world = auto_free(World.new(false)) as World
	add_child(_world)
	_world.build(SEED, "test")
	_world.add_spawner()
	_spawner = _world.spawner
	_player = auto_free(SimPlayer.new()) as SimPlayer
	_player.peer_id = 1
	_world.players.add_child(_player)
	_tick = Spawner.PERIOD


func after_test() -> void:
	Layout.set_world_seed(0)


## Runs the spawner for this many decisions.
func _update(times := 1) -> void:
	for i in times:
		_spawner.update(_tick)
		_tick += Spawner.PERIOD


## Puts the player on the ground this many meters (along the ground) from a point.
func _stand(point: Spawner.SpawnPoint, away: float) -> void:
	var east := point.up.cross(Vector3.UP).normalized()
	var direction := (point.up * _realm.radius + east * away).normalized()
	var feet := Terrain.surface(_realm, SEED, direction) + direction * Layout.ARRIVAL_LIFT
	_world.chunks.ensure_around(feet)
	_player.place(feet)


func _first(camp: int) -> Spawner.SpawnPoint:
	for point in Spawner.points(_realm, SEED):
		if point.camp == camp:
			return point
	return null


func _awake(unit: int) -> int:
	return _spawner.slots_of(unit).size()


func _awake_slots() -> int:
	var count := 0
	for i in range(Spawner.FIRST_SLOT, World.POOL):
		if _world.pool_slot(i).action != Enemy.Action.HIDDEN:
			count += 1
	return count


func _size(camp: int) -> int:
	var count := 0
	for point in Spawner.points(_realm, SEED):
		count += 1 if point.camp == camp else 0
	return count


func test_camps_mix_kinds_and_archers_stand_behind_bearers() -> void:
	var camps := {}
	for point in Spawner.points(_realm, SEED):
		if not camps.has(point.camp):
			camps[point.camp] = []
		camps[point.camp].append(point)
	var seen := {}
	var behind := 0
	for camp: Array in camps.values():
		for point: Spawner.SpawnPoint in camp:
			seen[Combat.ENEMY_KINDS[point.kind]] = true
		var bearers := camp.filter(
			func(p: Spawner.SpawnPoint) -> bool:
				return p.kind == Combat.enemy_kind(&"shield_bearer")
		)
		var archers := camp.filter(
			func(p: Spawner.SpawnPoint) -> bool: return p.kind == Combat.enemy_kind(&"archer")
		)
		if bearers.is_empty() or archers.is_empty():
			continue
		var front := SimPlayer._tangent(Vector3.FORWARD, camp[0].up).rotated(
			camp[0].up, camp[0].yaw
		)
		var best := -INF
		for bearer: Spawner.SpawnPoint in bearers:
			best = maxf(best, bearer.position.dot(front))
		for archer: Spawner.SpawnPoint in archers:
			behind += 1 if archer.position.dot(front) < best else 0
	for id: StringName in [
		&"swordsman", &"archer", &"shield_bearer", &"berserker", &"barrow_elite"
	]:
		assert_bool(seen.has(id)).override_failure_message("no %s" % id).is_true()
	assert_int(behind).is_greater(0)


func test_points_are_the_same_for_a_seed_and_laid_out_as_designed() -> void:
	var a := Spawner.points(_realm, SEED)
	var b := Spawner._find_points(_realm, SEED)  # not the cache: found again
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_vector(a[i].position).is_equal(b[i].position)
		assert_int(a[i].kind).is_equal(b[i].kind)
		assert_int(a[i].camp).is_equal(b[i].camp)
	assert_bool(a.size() > 500).is_true()
	assert_bool(Spawner.points(_realm, SEED + 1)[0].position != a[0].position).is_true()
	var sizes := {}
	var arrival := Terrain.surface(_realm, SEED, _realm.arrival)
	for point in a:
		sizes[point.camp] = int(sizes.get(point.camp, 0)) + 1
		assert_float(point.position.distance_to(arrival)).is_greater(Spawner.ARRIVAL_CLEAR - 5.0)
		var flat := Terrain.normal(_realm, SEED, point.up).dot(point.up)
		assert_float(flat).is_greater(Spawner.WALKABLE - 0.1)
	var lone := 0
	for size: int in sizes.values():
		assert_int(size).is_less_equal(Spawner.CAMP_MAX)
		lone += 1 if size == 1 else 0
		if size > 1:
			assert_int(size).is_greater_equal(Spawner.CAMP_MIN)
	assert_int(lone).is_greater(10)


func test_walking_toward_a_camp_wakes_it_and_walking_away_frees_it() -> void:
	var point := _first(0)
	_stand(point, FAR)
	_update()
	assert_int(_awake(0)).is_equal(0)
	_stand(point, 60.0)
	_update()
	assert_int(_awake(0)).is_equal(_size(0))
	for member: int in _spawner.slots_of(0):
		var enemy := _world.pool_slot(_spawner.slots_of(0)[member])
		assert_int(enemy.action).is_equal(Enemy.Action.RISE)
		(
			assert_bool(enemy.def.behavior in [EnemyDef.Behavior.MELEE, EnemyDef.Behavior.RANGED])
			. is_true()
		)
	var slots: Dictionary = _spawner.slots_of(0).duplicate()
	_stand(point, FAR)
	# Just woken: "in a fight" until the quiet time has passed (enemies are not ticked here).
	_update()
	assert_int(_awake(0)).is_equal(_size(0))
	for slot: int in slots.values():
		_world.pool_slot(slot).quiet_time = Combat.ticks(Spawner.FIGHT_QUIET)
	_update()
	assert_int(_awake(0)).is_equal(0)
	for slot: int in slots.values():
		var enemy := _world.pool_slot(slot)
		assert_int(enemy.action).is_equal(Enemy.Action.HIDDEN)
		assert_int(enemy.kind).is_equal(0)


func test_a_full_pool_wakes_nothing_more_and_a_fight_is_never_freed() -> void:
	var point := _first(0)
	var home := point.position
	# Fill the pool with other camps until camp 0 no longer fits.
	var fillers := []
	for other in range(1, _spawner.unit_count()):
		if _awake_slots() > World.POOL - Spawner.FIRST_SLOT - _size(0):
			break
		if _spawner._centers[other].distance_to(home) > Spawner.WAKE + 20.0:
			var filler := _first(other)
			fillers.append(other)
			_stand(filler, 5.0)
			_update()
	_stand(point, 60.0)
	_update()
	assert_int(_awake(0)).is_equal(0)
	# Let the fillers go: the camp wakes.
	_stand(point, FAR)
	for other: int in fillers:
		for slot: int in _spawner.slots_of(other).values():
			_world.pool_slot(slot).quiet_time = 1000
	_update(2)
	for other: int in fillers:
		assert_int(_awake(other)).is_equal(0)
	_stand(point, 60.0)
	_update()
	assert_int(_awake(0)).is_equal(_size(0))
	var enemy := _world.pool_slot(_spawner.slots_of(0).values()[0])
	_stand(point, FAR)
	for slot: int in _spawner.slots_of(0).values():
		_world.pool_slot(slot).quiet_time = 1000
	enemy.quiet_time = 0
	_update(3)
	assert_int(_awake(0)).is_equal(_size(0))
	# One in a swing keeps them all awake too.
	enemy.quiet_time = 1000
	enemy.action = Enemy.Action.WINDUP
	_update()
	assert_int(enemy.action).is_equal(Enemy.Action.WINDUP)
	enemy.action = Enemy.Action.IDLE
	_update()
	assert_int(_awake(0)).is_equal(0)


func test_a_rolled_back_wake_is_made_good() -> void:
	var point := _first(0)
	_stand(point, 60.0)
	_update()
	var slots: Dictionary = _spawner.slots_of(0).duplicate()
	# Netfox restores the tick before the wake: the slots are hidden again.
	for slot: int in slots.values():
		var enemy := _world.pool_slot(slot)
		enemy.become(0, enemy.home, Enemy.Action.HIDDEN)
	_update()
	assert_int(_awake(0)).is_equal(_size(0))
	for slot: int in slots.values():
		var enemy := _world.pool_slot(slot)
		assert_int(enemy.action).is_equal(Enemy.Action.RISE)
		assert_bool(enemy.kind != 0).is_true()


func test_a_rolled_back_sleep_leaves_no_orphans() -> void:
	var point := _first(0)
	_stand(point, 60.0)
	_update()
	var slots: Dictionary = _spawner.slots_of(0).duplicate()
	_stand(point, FAR)
	for slot: int in slots.values():
		_world.pool_slot(slot).quiet_time = 1000
	_update()
	assert_int(_awake(0)).is_equal(0)
	# A restore brings awake enemies back into slots the spawner let go (the ones now free).
	var orphans: Array[int] = []
	for i in range(Spawner.FIRST_SLOT, World.POOL):
		if _world.pool_slot(i).action == Enemy.Action.HIDDEN:
			orphans.append(i)
	assert_int(orphans.size()).is_greater(0)
	for i in orphans:
		var enemy := _world.pool_slot(i)
		enemy.become(Combat.enemy_kind(&"swordsman"), enemy.home, Enemy.Action.IDLE)
	_update()
	for i in orphans:
		assert_int(_world.pool_slot(i).action).is_not_equal(Enemy.Action.IDLE)


func test_a_cleared_camp_stays_empty_until_it_respawns() -> void:
	var point := _first(0)
	_stand(point, 60.0)
	_update()
	for slot: int in _spawner.slots_of(0).values():
		var enemy := _world.pool_slot(slot)
		enemy.action = Enemy.Action.IDLE
		enemy.take_hit(100000.0, Vector3.ZERO)
	_update()
	assert_int(_awake_slots()).is_greater(0)
	# The corpses go after a while.
	_tick += Combat.ticks(Spawner.CORPSE_TIME) / Spawner.PERIOD * Spawner.PERIOD + Spawner.PERIOD
	_update()
	assert_int(_awake(0)).is_equal(0)
	_stand(point, FAR)
	_update()
	_stand(point, 30.0)
	_update(3)
	assert_int(_awake(0)).is_equal(0)
	# The debug map hears of it with the seconds left.
	var left := _spawner.cleared_camps(_realm.id, _tick)
	assert_array(left.keys()).is_equal([point.camp])
	assert_float(left[point.camp]).is_greater(Spawner.RESPAWN_MINUTES * 60.0 - 60.0)
	assert_dict(_spawner.cleared_camps(&"nowhere", _tick)).is_empty()
	_tick += Combat.ticks(Spawner.RESPAWN_MINUTES * 60.0) / Spawner.PERIOD * Spawner.PERIOD
	_update(2)
	assert_int(_awake(0)).is_equal(_size(0))


func test_a_late_joiner_sees_awake_enemies_from_state_alone() -> void:
	_stand(_first(0), 60.0)
	_update()
	var theirs := auto_free(World.new(false)) as World
	add_child(theirs)
	for member: int in _spawner.slots_of(0):
		var index: int = _spawner.slots_of(0)[member]
		var mine := _world.pool_slot(index)
		var other := theirs.pool_slot(index)
		other.net_combat = mine.net_combat
		assert_int(other.kind).is_equal(mine.kind)
		assert_int(other.action).is_equal(Enemy.Action.RISE)
		assert_float(other.health).is_equal(mine.health)
		assert_vector(other.global_position).is_equal_approx(
			mine.global_position, Vector3.ONE * 0.01
		)
	var hidden := theirs.pool_slot(World.POOL - 1)
	assert_int(hidden.action).is_equal(Enemy.Action.HIDDEN)


func test_woken_enemies_stand_on_the_ground_the_server_built() -> void:
	_stand(_first(0), 60.0)
	_update()
	assert_int(_awake(0)).is_greater(0)
	for i in 60:
		await get_tree().physics_frame
		for node in get_tree().get_nodes_in_group(Enemy.GROUP):
			node.call("_rollback_tick", DELTA, 0, true)
	for slot: int in _spawner.slots_of(0).values():
		var enemy := _world.pool_slot(slot)
		assert_bool(_world.chunks.bodies.has(_world.chunks.key_at(enemy.global_position))).is_true()
		var local := enemy.global_position - _realm.center
		var over := (
			local.length() - (_realm.radius + Terrain.height(_realm, SEED, local.normalized()))
		)
		assert_float(absf(over)).is_less(0.6)
		assert_bool(enemy.alive()).is_true()
		assert_bool(enemy in _world.chunks.anchors.call()).is_true()


func test_no_post_stands_in_a_scatter_solid() -> void:
	var solids := Spawner.Solids.new(_realm, SEED)
	var points := Spawner.points(_realm, SEED)
	for point in points:
		assert_bool(solids.blocked(point.up)).is_false()
	# The check itself works: a trunk's own spot is blocked.
	var chunk := Terrain.chunk_at(_realm, _realm.arrival)
	for dx in range(-3, 4):
		var found := ScatterShape.solids(
			Scatter.points(_realm, SEED, Vector3i(chunk.x, chunk.y + dx, chunk.z))
		)
		if not found.is_empty():
			assert_bool(solids.blocked(found[0].transform.origin.normalized())).is_true()
			return
	fail("no scatter near the arrival")
