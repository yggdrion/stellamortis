extends GdUnitTestSuite
## The world list (M23 task 5): files in a folder are listed newest first with their seed and
## flags, a broken file shows as unreadable (and is not touched), remove deletes the files, the
## name is sanitized.

const DIR := "user://test_worlds/"


func before_test() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)


func after_test() -> void:
	_clean()


func _clean() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)
	DirAccess.remove_absolute(DIR)


func _put(file: String, text: String) -> void:
	var handle := FileAccess.open(DIR + file, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()


func test_list_reads_seed_and_flags() -> void:
	_put("alpha.json", JSON.stringify({"version": 1, "seed": 77, "flags": ["warden_fallen"]}))
	_put("notes.txt", "not a world")
	var found := WorldSave.list(DIR)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]["name"]).is_equal("alpha")
	assert_int(found[0]["seed"]).is_equal(77)
	assert_bool(found[0]["readable"]).is_true()
	assert_array(found[0]["flags"]).contains_exactly(["warden_fallen"])
	assert_int(found[0]["size"]).is_greater(0)
	assert_int(found[0]["mtime"]).is_greater(0)


func test_unreadable_files_are_listed_and_kept() -> void:
	_put("broken.json", "{ nope")
	_put("future.json", JSON.stringify({"version": 99, "seed": 1}))
	_put("noseed.json", JSON.stringify({"version": 1}))
	var found := WorldSave.list(DIR)
	assert_int(found.size()).is_equal(3)
	for entry in found:
		assert_bool(entry["readable"]).is_false()
	assert_bool(FileAccess.file_exists(DIR + "broken.json")).is_true()
	assert_int(DirAccess.get_files_at(DIR).size()).is_equal(3)


func test_remove_deletes_files() -> void:
	_put("gone.json", JSON.stringify({"version": 1, "seed": 5}))
	_put("gone.json.bak", "x")
	assert_str(WorldSave.remove("gone", DIR, false)).is_equal("removed")
	assert_array(DirAccess.get_files_at(DIR)).is_empty()
	assert_str(WorldSave.remove("gone", DIR, false)).is_equal("")


func test_remove_cannot_leave_the_folder() -> void:
	_put("keep.json", JSON.stringify({"version": 1, "seed": 5}))
	assert_str(WorldSave.remove("../keep", DIR, false)).is_equal("")
	assert_bool(FileAccess.file_exists(DIR + "keep.json")).is_true()


func test_names_are_sanitized() -> void:
	assert_str(SaveFile.clean("My World!", "x")).is_equal("my_world_")
	assert_str(SaveFile.clean("../etc", "x")).is_equal("___etc")
	assert_str(SaveFile.clean("   ", "x")).is_equal("x")
	assert_int(SaveFile.clean("a".repeat(50), "x").length()).is_equal(32)
