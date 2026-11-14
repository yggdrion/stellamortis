extends GdUnitTestSuite
## Gravity.sample picks the right zone, and the asteroid pulls toward its center.


func test_default_outside_zones() -> void:
	assert_vector(Gravity.sample(Vector3(0, 1, 0))).is_equal(Gravity.DEFAULT)


func test_low_and_high_gravity() -> void:
	assert_vector(Gravity.sample(Layout.LOW_G_CENTER)).is_equal(Vector3.DOWN * Layout.LOW_G)
	assert_vector(Gravity.sample(Layout.HIGH_G_CENTER)).is_equal(Vector3.DOWN * Layout.HIGH_G)


func test_asteroid_pulls_to_center() -> void:
	var above := Layout.ASTEROID_CENTER + Vector3(0, Layout.ASTEROID_RADIUS + 1, 0)
	var g := Gravity.sample(above)
	assert_vector(g.normalized()).is_equal_approx(Vector3.DOWN, Vector3.ONE * 0.001)
	assert_float(g.length()).is_equal_approx(Layout.ASTEROID_G, 0.001)
	var east := Layout.ASTEROID_CENTER + Vector3(Layout.ASTEROID_RADIUS + 1, 0, 0)
	assert_vector(Gravity.sample(east).normalized()).is_equal_approx(
		Vector3.LEFT, Vector3.ONE * 0.001
	)


func test_asteroid_wins_over_low_gravity() -> void:
	# A point inside both the low-g box and the asteroid's reach.
	var point := Vector3(40, 17, 0)
	assert_bool(Layout.LOW_G_SIZE.y / 2.0 + Layout.LOW_G_CENTER.y >= point.y).is_true()
	assert_str(Gravity.zone_at(point).label).is_equal("asteroid")


func test_zone_edges() -> void:
	var edge := Layout.LOW_G_CENTER + Vector3(Layout.LOW_G_SIZE.x / 2.0 + 0.01, 0, 0)
	assert_object(Gravity.zone_at(edge)).is_null()


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
	# Past the reach, and in the keep and the old realm, nothing changes.
	assert_object(Gravity.zone_at(realm.center + Vector3.UP * (realm.reach() + 1.0))).is_null()
	assert_vector(Gravity.sample(Layout.HUB)).is_equal(Gravity.DEFAULT)
	assert_vector(Gravity.sample(Vector3.ZERO)).is_equal(Gravity.DEFAULT)
