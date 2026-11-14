extends GdUnitTestSuite
## Scatter is a pure function of (realm, seed, chunk): the same inputs give the same points, a
## different seed gives others, every point stands on the ground, and the arrival is clear.

const SEED := 1234
## A hash of the points of a patch of chunks around the arrival under SEED. If this changes on
## purpose (new numbers in Scatter), print patch_hash() and update it.
const PATCH_HASH := -8688739338686721129
const PATCH := 2


func _realm() -> RealmDef:
	return Layout.realms()[0]


func _chunks() -> Array[Vector3i]:
	var at := Terrain.chunk_at(_realm(), _realm().arrival)
	var found: Array[Vector3i] = []
	for dx in range(-PATCH, PATCH + 1):
		for dy in range(-PATCH, PATCH + 1):
			found.append(Vector3i(at.x, at.y + dx, at.z + dy))
	return found


func _patch_hash(world_seed: int) -> int:
	var h := 1469598103934665603
	for chunk in _chunks():
		for point in Scatter.points(_realm(), world_seed, chunk):
			h = (h ^ roundi(point.position.x * 100.0)) * 1099511628211
			h = (h ^ roundi(point.position.z * 100.0)) * 1099511628211
			h = (h ^ (point.kind * 7 + roundi(point.rank * 1000.0))) * 1099511628211
	return h


func test_same_inputs_same_points() -> void:
	assert_int(_patch_hash(SEED)).is_equal(_patch_hash(SEED))
	assert_int(_patch_hash(SEED)).is_equal(PATCH_HASH)
	assert_int(_patch_hash(SEED + 1)).is_not_equal(_patch_hash(SEED))


func test_points_stand_on_the_ground_and_leave_the_arrival_clear() -> void:
	var realm := _realm()
	var field := Terrain.Field.new(realm, SEED)
	var arrival := Terrain.surface(realm, SEED, realm.arrival) - realm.center
	var kinds := {}
	var total := 0
	for chunk in _chunks():
		for point in Scatter.points(realm, SEED, chunk):
			var ground := field.surface(point.up)
			assert_float(point.position.distance_to(ground)).is_less(0.001)
			assert_float(point.position.distance_to(arrival)).is_greater(Scatter.CLEARING - 1.0)
			assert_float(point.rank).is_between(0.0, 1.0)
			kinds[point.kind] = true
			total += 1
	assert_int(total).is_greater(100)
	assert_int(kinds.size()).is_greater(3)
