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
