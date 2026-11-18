extends GdUnitTestSuite
## The map's projection (azimuthal equidistant) and terrain image.

const SEED := 1234
const SMALL := Vector2i(64, 32)


func _frame(center: Vector3) -> Vector3:
	var axis := Vector3.UP if absf(center.y) < 0.9 else Vector3.RIGHT
	return center.cross(axis).normalized().cross(center).normalized()


func test_round_trip_in_many_directions() -> void:
	var directions := Terrain.sample_directions(200)
	for center in directions.slice(0, 20):
		var heading := _frame(center)
		for d in directions:
			if d.dot(center) < -0.999:
				continue
			var back := MapPanel.unproject(
				center, heading, MapPanel.project(center, heading, d, 300.0), 300.0
			)
			assert_float(back.distance_to(d)).is_less(0.0001)


func test_center_is_the_middle_and_quarter_turn_is_half_radius() -> void:
	var center := Vector3(0.3, 0.5, -0.8).normalized()
	var heading := _frame(center)
	assert_vector(MapPanel.project(center, heading, center, 100.0)).is_equal_approx(
		Vector2.ZERO, Vector2.ONE * 0.001
	)
	var east := heading.cross(center)
	for turn in [heading, east, -heading, -east]:
		var p := MapPanel.project(center, heading, turn, 100.0)
		assert_float(p.length()).is_equal_approx(50.0, 0.001)
	# Heading points up on the map.
	assert_vector(MapPanel.project(center, heading, heading, 100.0)).is_equal_approx(
		Vector2(0, -50), Vector2.ONE * 0.001
	)
	# The antipode sits on the rim.
	assert_float(MapPanel.project(center, heading, -center, 100.0).length()).is_equal_approx(
		100.0, 0.001
	)


func test_same_seed_same_terrain_image() -> void:
	var realm := Layout.realms()[0]
	var a := MapPanel.terrain_image(realm, SEED, SMALL)
	var b := MapPanel.terrain_image(realm, SEED, SMALL)
	var c := MapPanel.terrain_image(realm, SEED + 1, SMALL)
	assert_array(a.get_data()).is_equal(b.get_data())
	assert_array(a.get_data()).is_not_equal(c.get_data())
	assert_int(a.get_width()).is_equal(SMALL.x)


func _pole() -> Vector3:
	return Layout.start_realm().north_pole


func test_north_is_a_unit_tangent_everywhere_but_at_the_pole() -> void:
	var realm := Layout.start_realm()
	var pole := _pole()
	for d in Terrain.sample_directions(200):
		if d.distance_to(pole) < 0.001 or d.distance_to(-pole) < 0.001:
			continue
		var north := Layout.north(realm, d)
		assert_float(north.length()).is_equal_approx(1.0, 0.0001)
		assert_float(absf(north.dot(d))).is_less(0.0001)
		assert_float(north.dot(pole)).is_greater(0.0)


func test_north_falls_back_at_the_pole() -> void:
	var realm := Layout.start_realm()
	for d in [_pole(), -_pole()]:
		var north := Layout.north(realm, d)
		assert_bool(is_nan(north.x) or is_nan(north.y) or is_nan(north.z)).is_false()
		assert_float(north.length()).is_equal_approx(1.0, 0.0001)
		assert_float(absf(north.dot(d))).is_less(0.0001)


func test_arrival_is_not_at_a_pole() -> void:
	var realm := Layout.start_realm()
	assert_float(realm.arrival.angle_to(realm.north_pole)).is_greater(0.5)
	assert_float(realm.arrival.angle_to(-realm.north_pole)).is_greater(0.5)


func test_bearing_is_clockwise_from_north() -> void:
	var realm := Layout.start_realm()
	var d := realm.arrival.normalized()
	var north := Layout.north(realm, d)
	var east := north.cross(d)
	assert_float(Layout.bearing(d, north, north)).is_equal_approx(0.0, 0.0001)
	assert_float(Layout.bearing(d, north, east)).is_equal_approx(PI * 0.5, 0.0001)
	assert_float(absf(Layout.bearing(d, north, -north))).is_equal_approx(PI, 0.0001)
	assert_float(Layout.bearing(d, north, -east)).is_equal_approx(-PI * 0.5, 0.0001)
	# Turning the camera changes the bearing by the angle and leaves north alone.
	var turned := north.rotated(d, -0.7)
	assert_float(Layout.bearing(d, north, turned)).is_equal_approx(0.7, 0.0001)
	assert_vector(Layout.north(realm, d)).is_equal_approx(north, Vector3.ONE * 0.0001)


func test_the_projection_does_not_turn_with_the_camera() -> void:
	var realm := Layout.start_realm()
	var center := Vector3(0.3, 0.6, 0.5).normalized()
	var north := Layout.north(realm, center)
	var target := Vector3(-0.2, 0.7, 0.4).normalized()
	var first := MapPanel.project(center, north, target, 200.0)
	for turn in [0.4, 1.9, -2.5]:
		var look := north.rotated(center, -turn)
		# The camera heading only turns the arrow; the projection keeps its heading.
		assert_float(Layout.bearing(center, north, look)).is_equal_approx(
			wrapf(turn, -PI, PI), 0.0001
		)
		assert_vector(MapPanel.project(center, north, target, 200.0)).is_equal_approx(
			first, Vector2.ONE * 0.0001
		)


func test_input_scope() -> void:
	assert_int(GameClient.input_scope(true, false, false)).is_equal(GameClient.InputScope.FULL)
	assert_int(GameClient.input_scope(false, true, false)).is_equal(GameClient.InputScope.WALK)
	assert_int(GameClient.input_scope(false, true, true)).is_equal(GameClient.InputScope.NONE)
	assert_int(GameClient.input_scope(false, false, false)).is_equal(GameClient.InputScope.NONE)
