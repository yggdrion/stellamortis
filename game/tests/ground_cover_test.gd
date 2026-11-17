extends GdUnitTestSuite
## Ground cover (M37 task 3): deterministic, never inside a scatter footprint, never on the spawn
## ring or the arrival clearing.

const SEED := 1234

var _realm: RealmDef


func before_test() -> void:
	_realm = Layout.realms()[0]
	Layout.set_world_seed(SEED)


func after_test() -> void:
	Layout.set_world_seed(0)


## The chunks around the arrival (a square of 2 * radius + 1).
func _chunks(radius: int) -> Array[Vector3i]:
	var at := Terrain.chunk_at(_realm, _realm.arrival)
	var found: Array[Vector3i] = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			found.append(Vector3i(at.x, at.y + dx, at.z + dy))
	return found


func test_deterministic_and_dense_enough() -> void:
	var chunk := _chunks(2)[7]
	var a := GroundCover.points(_realm, SEED, chunk)
	var b := GroundCover.points(_realm, SEED, chunk)
	assert_int(a.size()).is_greater(50)
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_vector(a[i].position).is_equal(b[i].position)
		assert_int(a[i].kind).is_equal(b[i].kind)
	assert_int(GroundCover.points(_realm, SEED, chunk, 0.0).size()).is_equal(0)
	assert_int(GroundCover.points(_realm, SEED, chunk, 0.5).size()).is_less(a.size())


func test_every_kind_has_a_generator() -> void:
	for name_of: String in GroundCover.Kind.keys():
		assert_array(Generators.ids()).contains([name_of.to_lower()])


func test_no_cover_inside_a_footprint() -> void:
	var seen := {}
	for chunk in _chunks(1):
		var cover := GroundCover.points(_realm, SEED, chunk)
		var near := Scatter.points(_realm, SEED, chunk)
		for other in _chunks(1):
			if other != chunk and absi(other.y - chunk.y) <= 1 and absi(other.z - chunk.z) <= 1:
				near.append_array(Scatter.points(_realm, SEED, other))
		for point in cover:
			seen[point.kind] = true
			for thing in near:
				var shape := ScatterShape.of_kind(thing.kind)
				var radius := shape.footprint(shape.size * (0.8 + 0.5 * thing.size))
				assert_float(point.position.distance_to(thing.position)).is_greater(radius)
	assert_int(seen.size()).is_greater(3)


func test_none_on_the_spawn_ring_or_the_clearing() -> void:
	var ground := Terrain.surface(_realm, SEED, _realm.arrival)
	var spots: Array[Vector3] = []
	for peer in Layout.SPAWN_SLOTS:
		spots.append(Layout.spawn_point(peer) - _realm.center)
	for chunk in _chunks(2):
		for point in GroundCover.points(_realm, SEED, chunk):
			assert_float(point.position.distance_to(ground - _realm.center)).is_greater(
				Scatter.CLEARING * 0.95
			)
			for spot in spots:
				assert_float(point.position.distance_to(spot)).is_greater(1.5)
