extends GdUnitTestSuite
## Scatter and the arrival are solid (M35 task 1): shapes are a pure function of the seed, a
## walking player stops at a trunk and at a ring stone, a bolt ends at a trunk, the gate stays
## open, and nothing stands on the spawn ring or the dummy posts.

const DELTA := 1.0 / 30.0
const SEED := 1234
const TICKS_PER_FRAME := 6
## How far a walker starts from what it walks into (m).
const RUN_UP := 6.0
## The walker's capsule radius is about this (m); it may touch a shape's skin, not pass it.
const BODY := 0.5

var _world: World
var _realm: RealmDef
var _player: SimPlayer


func before_test() -> void:
	_realm = Layout.realms()[0]
	_world = auto_free(World.new(false)) as World
	add_child(_world)
	_world.build(SEED, "t")
	_player = auto_free(SimPlayer.new()) as SimPlayer
	add_child(_player)


func after_test() -> void:
	Layout.set_world_seed(0)


## The solids of the chunks around the arrival, realm relative.
func _solids(radius := 3) -> Array[ScatterShape.Solid]:
	var at := Terrain.chunk_at(_realm, _realm.arrival)
	var found: Array[ScatterShape.Solid] = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var points := Scatter.points(_realm, SEED, Vector3i(at.x, at.y + dx, at.z + dy))
			found.append_array(ScatterShape.solids(points))
	return found


## World position of the arrival point on the ground.
func _arrival() -> Vector3:
	return Terrain.surface(_realm, SEED, _realm.arrival)


func _flat(a: Vector3, b: Vector3, up: Vector3) -> float:
	var d := a - b
	return (d - up * d.dot(up)).length()


## A trunk (world position, up) whose run-up of RUN_UP m toward it from the arrival side crosses
## no other solid.
func _free_trunk(kind: int) -> Array:
	var solids := _solids()
	var arrival := _arrival()
	for solid in solids:
		if solid.shape == ScatterShape.of_kind(kind):
			var target := solid.transform.origin + _realm.center
			var up := solid.transform.basis.y
			var way := SimPlayer._tangent(target - arrival, up)
			var start := target - way * RUN_UP
			var clear := true
			for other in solids:
				if other == solid:
					continue
				var spot := other.transform.origin + _realm.center
				var along := (spot - start).dot(way)
				if along > -3.0 and along < RUN_UP + 3.0 and _flat_line(spot, start, way) < 5.0:
					clear = false
					break
			if clear:
				return [target, up, way]
	return []


## Distance of a point from the line through start along way, in 3D.
func _flat_line(point: Vector3, start: Vector3, way: Vector3) -> float:
	var d := point - start
	return (d - way * d.dot(way)).length()


func _stand(feet: Vector3, forward: Vector3) -> void:
	_player.place(feet, forward)
	_world.chunks.ensure_around(feet)


func _on_ground(point: Vector3) -> Vector3:
	var direction := (point - _realm.center).normalized()
	return Terrain.surface(_realm, SEED, direction) + direction * 0.05


## Runs ticks of walking forward, TICKS_PER_FRAME to a physics frame.
func _walk(ticks: int, until := Callable()) -> void:
	for i in ticks:
		if i % TICKS_PER_FRAME == 0:
			await get_tree().physics_frame
		_player.stamina = 100.0
		_player.step(Vector2(0, 1), 0.0, 0, DELTA)
		if until.is_valid() and until.call():
			return


func test_same_chunk_same_shapes() -> void:
	var at := Terrain.chunk_at(_realm, _realm.arrival)
	for dx in range(-2, 3):
		var chunk := Vector3i(at.x, at.y + dx, at.z)
		var a := ScatterShape.solids(Scatter.points(_realm, SEED, chunk))
		var b := ScatterShape.solids(Scatter.points(_realm, SEED, chunk))
		assert_int(a.size()).is_equal(b.size())
		for i in a.size():
			assert_bool(a[i].transform == b[i].transform).is_true()
			assert_bool(a[i].extents() == b[i].extents()).is_true()
			assert_object(a[i].shape).is_same(b[i].shape)
	# The streamed body holds the ground and one shape per solid.
	var key: Variant = _world.chunks.key_at(_arrival())
	var body := _world.chunks.bodies[key] as StaticBody3D
	var expected := ScatterShape.solids(Scatter.points(_realm, SEED, at)).size() + 1
	assert_int(body.get_child_count()).is_equal(expected)


func test_a_trunk_stops_a_walker() -> void:
	var trunk := _free_trunk(Scatter.Kind.PINE_GROWN)
	assert_int(trunk.size()).is_equal(3)
	var target: Vector3 = trunk[0]
	var way: Vector3 = trunk[2]
	var up: Vector3 = trunk[1]
	_stand(_on_ground(target - way * RUN_UP), way)
	await _walk(90)
	var gap := _flat(_player.global_position, target, up)
	var past := (_player.global_position - target).dot(way)
	assert_float(past).is_less(0.0)
	assert_float(gap).is_greater(0.2)
	assert_float(gap).is_less(BODY + 0.6)


func test_a_bolt_ends_at_a_trunk() -> void:
	var trunk := _free_trunk(Scatter.Kind.PINE_GROWN)
	assert_int(trunk.size()).is_equal(3)
	var target: Vector3 = trunk[0]
	var way: Vector3 = trunk[2]
	var up: Vector3 = trunk[1]
	_world.chunks.ensure_around(target)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var from := target - way * RUN_UP + up * 1.5
	var hit := Combat.ray(_world, from, target + way * RUN_UP + up * 1.5)
	assert_bool(hit.is_empty()).is_false()
	assert_float(_flat(hit.position, target, up)).is_between(0.1, 0.5)
	assert_float(hit.position.distance_to(from)).is_less(RUN_UP + 0.1)


func test_a_ring_stone_stops_a_walker() -> void:
	var stones := _world.arena._arrival_stones(_realm)
	assert_int(stones.size()).is_greater(5)
	var center := _arrival()
	for i in 3:
		var stone: Transform3D = stones[i]
		var at: Vector3 = stone.origin + _realm.center
		var up: Vector3 = stone.basis.y
		var way := SimPlayer._tangent(at - center, up)
		_stand(_on_ground(center), way)
		await _walk(60)
		var reached := _flat(_player.global_position, center, up)
		var stone_gap := _flat(_player.global_position, at, up)
		assert_float(reached).is_less(_flat(at, center, up) - 0.4)
		assert_float(stone_gap).is_greater(0.4)


func test_the_gate_opening_stays_passable() -> void:
	# A gate behind the arrival (none stands there until M57), added after the world is built.
	var spot := Layout.arrival_spot(_realm, -10.0, 0.0)
	var gate := Portal.at(spot[0], Vector3.ZERO, Vector3.BACK, "Test gate")
	gate.up = spot[1]
	gate.realm = _realm.id
	Layout.portals().append(gate)
	_world.arena.add_arrival_solids()
	var up := gate.up
	var way := SimPlayer._tangent(Vector3.FORWARD, up)
	var before := _player.respawns
	_stand(_on_ground(gate.position - way * 5.0), way)
	await _walk(120, func() -> bool: return _player.respawns != before)
	assert_int(_player.respawns).is_equal(before + 1)
	# Through the gate to the arrival ring, away from it.
	assert_str(Layout.place_at(_player.global_position)).is_equal(_realm.id)
	# A pillar is solid: walking at one stops the walker beside the opening.
	var side := up.cross(way).normalized()
	_stand(_on_ground(gate.position + side * Arena.GATE_PILLAR_X - way * 5.0), way)
	await _walk(90)
	assert_int(_player.respawns).is_equal(before + 1)
	assert_float((_player.global_position - gate.position).dot(way)).is_less(0.0)


func test_nothing_stands_on_the_spawn_ring_or_the_dummy_posts() -> void:
	var up := (_arrival() - _realm.center).normalized()
	var spots: Array[Vector3] = []
	for peer in Layout.SPAWN_SLOTS:
		spots.append(Layout.spawn_point(peer) - _realm.center)
	for i in Layout.DUMMIES.size():
		spots.append((Layout.dummy_post(i)[0] as Vector3) - _realm.center)
	for solid in _solids():
		var reach := solid.shape.footprint(solid.extents()) + BODY
		if solid.shape.form == ScatterShape.Form.SPHERE:
			reach = 0.0
		for spot in spots:
			assert_float(_flat(solid.transform.origin, spot, up)).is_greater(reach)
	for stone in _world.arena._arrival_stones(_realm):
		for spot in spots:
			assert_float(_flat(stone.origin, spot + _realm.center, up)).is_greater(
				Arena.STONE_SOLID.x + BODY
			)


func test_a_mob_chasing_a_player_goes_around_a_trunk() -> void:
	var trunk := _free_trunk(Scatter.Kind.PINE_GROWN)
	assert_int(trunk.size()).is_equal(3)
	var target: Vector3 = trunk[0]
	var way: Vector3 = trunk[2]
	var up: Vector3 = trunk[1]
	_world.chunks.ensure_around(target)
	_stand(_on_ground(target + way * 4.0), way)
	var enemy := _world.pool_slot(Spawner.FIRST_SLOT)
	var start := _on_ground(target - way * 4.0)
	var post := Transform3D(SimPlayer.frame(up, way), start)
	enemy.become(Combat.enemy_kind(&"swordsman"), post, Enemy.Action.IDLE)
	var reach := enemy.attack_def().reach + 0.2
	var near := false
	for i in 300:
		if i % TICKS_PER_FRAME == 0:
			await get_tree().physics_frame
		enemy._rollback_tick(DELTA, 0, true)
		if enemy.global_position.distance_to(_player.global_position) < reach + 0.8:
			near = true
			break
	assert_bool(near).is_true()
