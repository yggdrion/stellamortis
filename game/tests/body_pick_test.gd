extends GdUnitTestSuite
## The body picked in the menu (M40 task 4): saved in Settings, one distinct body per index.

var _file := PackedByteArray()
var _had_file := false
var _body := 0


func before_test() -> void:
	_had_file = FileAccess.file_exists(Graphics.SETTINGS)
	if _had_file:
		_file = FileAccess.get_file_as_bytes(Graphics.SETTINGS)
	_body = Settings.body


func after_test() -> void:
	if _had_file:
		var f := FileAccess.open(Graphics.SETTINGS, FileAccess.WRITE)
		f.store_buffer(_file)
	else:
		DirAccess.remove_absolute(Graphics.SETTINGS)
	Settings.body = _body


func test_body_round_trip_and_clamp() -> void:
	Settings.body = 3
	Settings.save()
	Settings.body = 0
	Settings.load_saved()
	assert_int(Settings.body).is_equal(3)
	var config := ConfigFile.new()
	config.load(Graphics.SETTINGS)
	config.set_value("player", "body", 9)
	config.save(Graphics.SETTINGS)
	Settings.load_saved()
	assert_int(Settings.body).is_equal(3)


func test_ranger_pick_overrides_peer_id() -> void:
	var seen := {}
	for i in Gear.PLAYER_BODIES.size():
		var model := auto_free(Gear.ranger(5, {}, i)) as CharacterModel
		var key := ""
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var shape := (mesh as MeshInstance3D).mesh
			key += "%s:%d;" % [shape.resource_path, shape.get_surface_count()]
		seen[key] = true
	assert_int(seen.size()).is_equal(4)
	assert_str(Gear.PLAYER_BODIES[0]).is_equal("male_a")
	assert_str(Gear.PLAYER_BODIES[3]).is_equal("female_b")


func test_body_picker_builds() -> void:
	var picker := auto_free(BodyPicker.new()) as BodyPicker
	add_child(picker)
	assert_int(picker.get_child_count()).is_equal(4)
