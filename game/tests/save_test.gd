extends GdUnitTestSuite
## Saves and graves (M23 task 4): the save file helper (round trip, atomic write, broken files
## kept aside), the world file (a cleared Warden and camps and the objects survive a reload into
## a fresh World with the same seed), graves (one per death, owner only for ten minutes) and a
## hostile character file.

const DIR := "user://test_saves/"
const SEED := 1234
const MINE := "me"
const OTHER := "someone_else"

var _world: World


func before_test() -> void:
	_clean()


func after_test() -> void:
	_clean()
	Layout.set_world_seed(0)


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(DIR)


func _bad_files() -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(DIR):
		if ".bad-" in file:
			found.append(file)
	return found


func test_round_trip_and_overwrite() -> void:
	var path := DIR + "a.json"
	assert_bool(SaveFile.write(path, {"version": 1, "x": 5, "name": "one"})).is_true()
	assert_int(int(SaveFile.read(path)["x"])).is_equal(5)
	# The second write replaces the first (DirAccess.rename does not replace on Windows).
	assert_bool(SaveFile.write(path, {"version": 1, "x": 9})).is_true()
	assert_int(int(SaveFile.read(path)["x"])).is_equal(9)
	assert_bool(FileAccess.file_exists(path + ".tmp")).is_false()
	assert_bool(FileAccess.file_exists(path + ".bak")).is_false()


func test_missing_file_reads_empty() -> void:
	assert_dict(SaveFile.read(DIR + "none.json")).is_empty()
	assert_array(_bad_files()).is_empty()


func test_truncated_json_is_kept_aside() -> void:
	var path := DIR + "b.json"
	SaveFile.write(path, {"version": 1, "x": 1})
	var text := FileAccess.get_file_as_string(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text.left(text.length() - 3))
	file.close()
	assert_dict(SaveFile.read(path)).is_empty()
	assert_bool(FileAccess.file_exists(path)).is_false()
	assert_int(_bad_files().size()).is_equal(1)


func test_newer_version_is_kept_aside() -> void:
	var path := DIR + "c.json"
	SaveFile.write(path, {"version": SaveFile.VERSION + 1, "x": 1})
	assert_dict(SaveFile.read(path)).is_empty()
	assert_int(_bad_files().size()).is_equal(1)


func test_stale_temp_leaves_the_real_file_alone() -> void:
	var path := DIR + "d.json"
	SaveFile.write(path, {"version": 1, "x": 3})
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string('{"version": 1, "x": 99')
	file.close()
	assert_int(int(SaveFile.read(path)["x"])).is_equal(3)
	# A write after the power cut still works.
	assert_bool(SaveFile.write(path, {"version": 1, "x": 4})).is_true()
	assert_int(int(SaveFile.read(path)["x"])).is_equal(4)


func test_names_are_cleaned() -> void:
	assert_str(WorldSave.path("My World/../x")).is_equal("user://worlds/my_world____x.json")
	assert_str(CharacterSave.path("")).is_equal("user://characters/player.json")


func _build_world() -> World:
	var world := World.new(false)
	add_child(world)
	world.build(SEED, "test")
	world.add_spawner()
	return world


func test_world_file_round_trip() -> void:
	var realm := Layout.realms()[0]
	var camps: Array[int] = []
	for point in Spawner.points(realm, SEED):
		if not camps.has(point.camp):
			camps.append(point.camp)
		if camps.size() == 2:
			break
	var first := _build_world()
	first.encounter.restore_cleared()
	var tick := NetworkTime.tick
	for camp in camps:
		var unit := first.spawner.unit_of(String(realm.id), camp)
		first.spawner._cleared_until[unit] = tick + Combat.ticks(300.0 + camp)
	var objects := WorldObjects.new()
	var drop := objects.add_drop(
		Inventory.Stack.new(&"bone", 7), Vector3(10, 20, 30), Vector3.UP, 12.0
	)
	var data := WorldSave.capture(first, objects, 321.0)
	assert_bool(SaveFile.write(DIR + "w.json", data)).is_true()
	var read := SaveFile.read(DIR + "w.json", WorldSave.VERSION)
	first.free()
	Layout.set_world_seed(0)

	var second := _build_world()
	WorldSave.restore(read, second)
	assert_int(second.encounter.phase).is_equal(Encounter.Phase.CLEARED)
	assert_array(second.flags()).contains([realm.boss_flag])
	for camp in camps:
		var unit := second.spawner.unit_of(String(realm.id), camp)
		var left := float(second.spawner._cleared_until[unit] - NetworkTime.tick)
		assert_float(left / Combat.TICKRATE).is_between(299.0 + camp, 301.0 + camp)
	var loaded := WorldObjects.from_dict(read["objects"])
	assert_int(loaded.entries.size()).is_equal(1)
	assert_int((loaded.at(drop) as WorldObjects.Entry).stack().count).is_equal(7)
	assert_float(WorldSave.seconds_of(read)).is_equal(321.0)
	second.free()


func test_unusable_world_file_is_kept_aside() -> void:
	var path := WorldSave.path("test_world_bad")
	SaveFile.write(path, {"version": 1, "name": "no seed"})
	assert_dict(WorldSave.read("test_world_bad")).is_empty()
	assert_bool(FileAccess.file_exists(path)).is_false()
	for file in DirAccess.get_files_at(WorldSave.FOLDER):
		if file.begins_with("test_world_bad.json.bad-"):
			DirAccess.remove_absolute(WorldSave.FOLDER + file)


func _graves_setup() -> Dictionary:
	var world := _build_world()
	_world = world
	var inventories := Inventories.new()
	inventories.net = auto_free(Net.new()) as Net
	inventories.world = world
	add_child(inventories)
	var looting := Looting.new()
	looting.world = world
	looting.inventories = inventories
	add_child(looting)
	var graves := Graves.new()
	graves.world = world
	graves.inventories = inventories
	graves.looting = looting
	add_child(graves)
	var players := {}
	for peer in [1, 2]:
		var player := SimPlayer.new()
		player.peer_id = peer
		player.name = "Player%d" % peer
		world.players.add_child(player)
		inventories.add_peer(peer, Inventory.starting_kit(), MINE if peer == 1 else OTHER)
		players[peer] = player
	var at := Layout.spawn_point(1)
	world.chunks.ensure_around(at)
	for peer in players:
		(players[peer] as SimPlayer).place(at)
	return {"inventories": inventories, "looting": looting, "graves": graves, "players": players}


func test_one_grave_per_death_and_owner_only_at_first() -> void:
	var s := _graves_setup()
	var inventories: Inventories = s["inventories"]
	var looting: Looting = s["looting"]
	var graves: Graves = s["graves"]
	var me: SimPlayer = s["players"][1]
	var other: SimPlayer = s["players"][2]
	var kit := inventories.inventory(1).cell_dict()
	inventories.inventory(1).add(&"bone", 5)
	var before := looting.objects.entries.size()
	me.respawns = 3
	me.action = SimPlayer.Action.DEAD
	# The same death seen on several (replayed) ticks makes one grave.
	for tick in 4:
		graves._watch(tick)
	assert_int(looting.objects.entries.size()).is_equal(before + 1)
	var grave_id := 0
	for id: int in looting.objects.entries:
		if (looting.objects.at(id) as WorldObjects.Entry).kind == WorldObjects.Kind.GRAVE:
			grave_id = id
	assert_int(grave_id).is_greater(0)
	# The bag is empty; the gear is not touched.
	for cell in Inventory.BAG_SIZE:
		assert_object(inventories.inventory(1).cells[cell]).is_null()
	assert_bool(kit.size() > 0).is_true()
	# A new life and a second death make a second grave once the bag holds something.
	me.action = SimPlayer.Action.NONE
	me.respawns = 4
	inventories.inventory(1).add(&"hide", 2)
	me.action = SimPlayer.Action.DEAD
	graves._watch(9)
	var graves_now := 0
	for id: int in looting.objects.entries:
		if (looting.objects.at(id) as WorldObjects.Entry).kind == WorldObjects.Kind.GRAVE:
			graves_now += 1
	assert_int(graves_now).is_equal(2)
	# Another player cannot open the grave before ten minutes, its owner can.
	me.action = SimPlayer.Action.NONE
	assert_bool(looting.open(2, grave_id)).is_false()
	assert_bool(looting.objects.at(grave_id) != null).is_true()
	assert_bool(looting.open(1, grave_id)).is_true()
	assert_object(looting.objects.at(grave_id)).is_null()
	assert_int(inventories.inventory(1).count_of(&"bone")).is_equal(5)
	# After GRAVE_LOCK anyone can take the second one.
	looting.world_seconds += Looting.GRAVE_LOCK + 1.0
	var second := 0
	for id: int in looting.objects.entries:
		second = id
	assert_bool(looting.open(2, second)).is_true()
	assert_int(inventories.inventory(2).count_of(&"hide")).is_equal(2)
	assert_object(other).is_not_null()


func test_hostile_character_is_clamped() -> void:
	var cells := {}
	for i in 500:
		cells[str(i)] = {"id": "no_such_item_%d" % i, "count": 1000000000}
	cells["0"] = {"id": "bone", "count": 1000000000}
	cells["1"] = {"id": "hide", "count": -4}
	cells["2"] = "garbage"
	var inventory := Inventory.from_dict(cells)
	var held := 0
	for cell in Inventory.CELLS:
		var stack := inventory.cells[cell]
		if stack != null:
			held += 1
			assert_bool(Items.has(stack.id)).is_true()
			assert_int(stack.count).is_between(1, Items.by_id(stack.id).stack)
	assert_int(held).is_less_equal(Inventory.CELLS)
	assert_array(CharacterSave.junk_of(["bone", "nope", 5, "bone"])).is_equal([&"bone"])
	assert_str(CharacterSave.clean_id("ab c/../d")).is_equal("abcd")
	assert_int(CharacterSave.clean_id("x".repeat(500)).length()).is_equal(64)
