extends GdUnitTestSuite
## Gates and places on a round realm (M20 task 4): portal reach and ring points along a tilted
## up, the place a point is in, and spawn and dummies on the realm.

const DELTA := 1.0 / 30.0
const SEEDS := [1234, 99]
## Peers that arrive (spawn slots differ).
const PEERS := [1, 4, 7]
## Feet this close above the ground after arriving.
const LANDING := 0.5

var _world: World


func after_test() -> void:
	Layout.set_world_seed(0)


func _realm() -> RealmDef:
	return Layout.realms()[0]


## Meters above the height function under a point.
func _over(point: Vector3, world_seed: int) -> float:
	var local := point - _realm().center
	return (
		local.length()
		- (_realm().radius + Terrain.height(_realm(), world_seed, local.normalized()))
	)


func test_portal_reach_follows_the_up_of_the_walker() -> void:
	var up := Vector3(1, 1, 0).normalized()
	var tangent := up.cross(Vector3.BACK).normalized()
	var gate := Portal.at(Vector3(10, 20, 30), Vector3.ZERO, Vector3.BACK, "x")
	assert_bool(gate.reaches(gate.position + up * 0.2, up)).is_true()
	assert_bool(gate.reaches(gate.position + tangent * 1.0, up)).is_true()
	assert_bool(gate.reaches(gate.position + tangent * 2.0, up)).is_false()
	assert_bool(gate.reaches(gate.position + up * 3.0, up)).is_false()
	# The same offset is "above" for a flat walker.
	assert_bool(gate.reaches(gate.position + Vector3.UP * 0.2)).is_true()
	assert_bool(gate.reaches(gate.position + up * 1.0)).is_true()
	assert_bool(gate.reaches(gate.position + tangent * 1.2 + up * 1.4, up)).is_true()


func test_ring_point_lies_in_the_tangent_plane() -> void:
	var center := Vector3(5, 6, 7)
	var up := Vector3(0.3, 0.8, -0.5).normalized()
	for peer in PEERS:
		var spot := Layout.ring_point(center, peer, up)
		assert_float(spot.distance_to(center)).is_equal_approx(Layout.SPAWN_RADIUS, 0.001)
		assert_float((spot - center).dot(up)).is_equal_approx(0.0, 0.001)
	var flat := Layout.ring_point(center, 3)
	assert_float(flat.y).is_equal_approx(center.y, 0.001)
	assert_float(flat.distance_to(center)).is_equal_approx(Layout.SPAWN_RADIUS, 0.001)


func test_place_at() -> void:
	assert_str(Layout.place_at(Vector3.ZERO)).is_equal(Layout.NO_PLACE)
	assert_str(Layout.place_at(_realm().center + Vector3.UP * 1005.0)).is_equal(_realm().id)
	assert_str(Layout.place_at(_realm().center + Vector3.UP * 1400.0)).is_equal(Layout.NO_PLACE)


func _build(world_seed: int) -> void:
	_world = auto_free(World.new(false)) as World
	add_child(_world)
	_world.build(world_seed, "t")


func test_spawn_and_dummies_stand_on_the_ground() -> void:
	var seen := {}
	for world_seed: int in SEEDS:
		_build(world_seed)
		# The dummies stand on the ground beside the arrival, with a body to hit.
		for i in Layout.DUMMIES.size():
			var dummy := _world.get_node("Enemies/Dummy%d" % i) as Enemy
			assert_float(_over(dummy.global_position, world_seed)).is_equal_approx(0.0, 0.001)
			assert_float(dummy.global_position.distance_to(Layout.spawn_point(1))).is_less(15.0)
			assert_float(dummy.take_hit(10.0, Vector3.ZERO)).is_equal(10.0)
			assert_float(dummy.health).is_equal(dummy.max_health - 10.0)
		for peer: int in PEERS:
			var spawn := Layout.spawn_point(peer)
			assert_str(Layout.place_at(spawn)).is_equal(_realm().id)
			assert_bool(_world.chunks.bodies.has(_world.chunks.key_at(spawn))).is_true()
			var player := SimPlayer.new()
			player.peer_id = peer
			_world.players.add_child(player)
			player.place(spawn)
			assert_float(_over(player.global_position, world_seed)).is_between(0.0, LANDING)
			for i in 30:
				await get_tree().physics_frame
				player.step(Vector2.ZERO, 0.0, 0, DELTA)
			assert_bool(player.grounded).is_true()
			assert_float(_over(player.global_position, world_seed)).is_between(-0.3, LANDING)
			assert_vector(spawn).is_equal(Layout.spawn_point(peer))
			seen[[world_seed, peer]] = spawn
			player.queue_free()
		_world.queue_free()
		await get_tree().process_frame
	# Different seeds, different ground, different spawn.
	assert_vector(seen[[SEEDS[0], 1]]).is_not_equal(seen[[SEEDS[1], 1]])
