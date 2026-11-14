extends GdUnitTestSuite
## Vsync and the frame cap survive a save/load round trip and apply_pacing sets Engine.max_fps.

var _file := PackedByteArray()
var _had_file := false
var _vsync := true
var _max_fps := 0


func before_test() -> void:
	_had_file = FileAccess.file_exists(Graphics.SETTINGS)
	if _had_file:
		_file = FileAccess.get_file_as_bytes(Graphics.SETTINGS)
	_vsync = Settings.vsync
	_max_fps = Settings.max_fps


func after_test() -> void:
	if _had_file:
		var f := FileAccess.open(Graphics.SETTINGS, FileAccess.WRITE)
		f.store_buffer(_file)
	else:
		DirAccess.remove_absolute(Graphics.SETTINGS)
	Settings.vsync = _vsync
	Settings.max_fps = _max_fps
	Settings.vsync_flag = -1
	Settings.max_fps_flag = -1
	Engine.max_fps = 0


func test_round_trip() -> void:
	Settings.vsync = false
	Settings.max_fps = 144
	Settings.save()
	Settings.vsync = true
	Settings.max_fps = 0
	Settings.load_saved()
	assert_bool(Settings.vsync).is_false()
	assert_int(Settings.max_fps).is_equal(144)


func test_apply_sets_engine_cap() -> void:
	Settings.max_fps = 60
	Settings.apply_pacing()
	assert_int(Engine.max_fps).is_equal(60)
	Settings.max_fps_flag = 0
	Settings.apply_pacing()
	assert_int(Engine.max_fps).is_equal(0)
