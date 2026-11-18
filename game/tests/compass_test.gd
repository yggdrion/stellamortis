extends GdUnitTestSuite
## The compass bar's geometry and markers (M43).


func test_wrap_keeps_angles_in_half_open_range() -> void:
	assert_float(Compass.wrap(3.0 * PI)).is_equal_approx(PI, 0.0001)
	assert_float(Compass.wrap(-PI)).is_equal_approx(PI, 0.0001)
	assert_float(Compass.wrap(0.1)).is_equal_approx(0.1, 0.0001)


func test_offset_takes_the_short_way() -> void:
	var turn := Compass.offset(deg_to_rad(350.0), deg_to_rad(10.0))
	assert_float(turn).is_equal_approx(deg_to_rad(20.0), 0.0001)


func test_markers_include_arrival_and_boss_site_in_the_start_realm() -> void:
	var realm := Layout.start_realm()
	var list := Compass.markers(realm, 1234, false)
	assert_int(list.size()).is_equal(2 + Layout.portals().size())
	var site := BossSite.at(realm, 1234)
	var center := realm.arrival.normalized()
	var north := Layout.north(realm, center)
	var boss: Array = list[list.size() - 1]
	assert_str(boss[2]).is_equal("boss site")
	assert_float(Compass.bearing_to(center, north, boss[0])).is_equal_approx(
		Layout.bearing(center, north, site.direction - center), 0.0001
	)
	var fallen := Compass.markers(realm, 1234, true)
	assert_bool(fallen[fallen.size() - 1][1] == MapPanel.SITE).is_false()
