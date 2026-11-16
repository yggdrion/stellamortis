extends GdUnitTestSuite
## Gravity.sample picks the right zone: the default in open space, the realm's pull to its center,
## and the highest priority where zones overlap (a box and a sphere added here, removed after).

var _added: Array[GravityZone] = []


func after_test() -> void:
	for zone in _added:
		Layout.gravity_zones().erase(zone)
	_added.clear()


func _add(zone: GravityZone) -> GravityZone:
	Layout.gravity_zones().append(zone)
	_added.append(zone)
	return zone


func test_default_outside_zones() -> void:
	assert_vector(Gravity.sample(Vector3(0, 1, 0))).is_equal(Gravity.DEFAULT)
	assert_vector(Gravity.sample(Vector3.ZERO)).is_equal(Gravity.DEFAULT)


func test_box_zone_pulls_one_way_and_has_edges() -> void:
	var center := Vector3(0, 9, 0)
	var size := Vector3(30, 18, 40)
	_add(GravityZone.box("low", center, size, 3.0))
	assert_vector(Gravity.sample(center)).is_equal(Vector3.DOWN * 3.0)
	var edge := center + Vector3(size.x / 2.0 + 0.01, 0, 0)
	assert_object(Gravity.zone_at(edge)).is_null()


func test_sphere_zone_pulls_to_center() -> void:
	var center := Vector3(40, 50, 0)
	_add(GravityZone.sphere("rock", center, 34.0, 7.0))
	var g := Gravity.sample(center + Vector3(0, 19, 0))
	assert_vector(g.normalized()).is_equal_approx(Vector3.DOWN, Vector3.ONE * 0.001)
	assert_float(g.length()).is_equal_approx(7.0, 0.001)
	var east := center + Vector3(19, 0, 0)
	assert_vector(Gravity.sample(east).normalized()).is_equal_approx(
		Vector3.LEFT, Vector3.ONE * 0.001
	)


func test_sphere_wins_over_a_box() -> void:
	_add(GravityZone.box("low", Vector3(40, 9, 0), Vector3(30, 18, 40), 3.0))
	_add(GravityZone.sphere("rock", Vector3(40, 50, 0), 34.0, 7.0))
	# A point inside both the box and the sphere's reach.
	assert_str(Gravity.zone_at(Vector3(40, 17, 0)).label).is_equal("rock")


func test_realm_zone_pulls_to_its_center() -> void:
	var realm := Layout.realms()[0]
	var top := realm.center + Vector3.UP * (realm.radius + 50.0)
	assert_str(Gravity.zone_at(top).label).is_equal(realm.id)
	assert_float(Gravity.sample(top).length()).is_equal_approx(realm.gravity, 0.001)
	assert_vector(Gravity.sample(top).normalized()).is_equal_approx(
		Vector3.DOWN, Vector3.ONE * 0.001
	)
	var side := realm.center + Vector3.RIGHT * (realm.radius + 50.0)
	assert_vector(Gravity.sample(side).normalized()).is_equal_approx(
		Vector3.LEFT, Vector3.ONE * 0.001
	)
	# Past the reach nothing changes.
	assert_object(Gravity.zone_at(realm.center + Vector3.UP * (realm.reach() + 1.0))).is_null()
