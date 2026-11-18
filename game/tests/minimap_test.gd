extends GdUnitTestSuite
## The minimap's scale and when it shows (M43).


func test_minimap_zoom_puts_the_rim_at_half_the_span() -> void:
	var realm := Layout.start_realm()
	var center := Vector3.UP
	var north := Layout.north(realm, center)
	var angle := Minimap.SPAN * 0.5 / realm.radius
	var d := center * cos(angle) + north * sin(angle)
	var p := MapPanel.project(center, north, d, Minimap.zoom_for(realm.radius))
	assert_vector(p).is_equal_approx(Vector2(0.0, -Minimap.SIZE * 0.5), Vector2.ONE)


func test_minimap_is_hidden_outside_a_realm_and_with_the_setting_off() -> void:
	assert_bool(Minimap.shows(false, true, true)).is_true()
	assert_bool(Minimap.shows(true, true, true)).is_false()
	assert_bool(Minimap.shows(false, false, true)).is_false()
	assert_bool(Minimap.shows(false, true, false)).is_false()
	var saved := Settings.minimap
	var minimap := auto_free(Minimap.new()) as Minimap
	minimap.me = auto_free(Node3D.new()) as Node3D
	add_child(minimap)
	add_child(minimap.me)
	minimap.me.global_position = Vector3(1.0e6, 1.0e6, 1.0e6)
	Settings.minimap = true
	minimap._process(0.0)
	assert_bool(minimap.visible).is_false()
	Settings.minimap = saved
