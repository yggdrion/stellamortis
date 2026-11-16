class_name WorldSave
extends RefCounted
## The world file (M23): `user://worlds/<name>.json`, written by the server. What a restart must
## keep: the seed, which bosses fell (and paid), the cleared camps with the seconds left, and the
## world objects (drops, chests with their opened state, graves). Everything else is generated
## from the seed. Pure data in and out: GameServer decides when to read and write.

## The file format version (SaveFile keeps a newer file aside).
const VERSION := 1
const FOLDER := "user://worlds/"


## The file of a world (the name cleaned to `[a-z0-9_-]`).
static func path(world_name: String) -> String:
	return FOLDER + SaveFile.clean(world_name, "world") + ".json"


## What the file holds, empty when there is none or it is unusable.
static func read(world_name: String) -> Dictionary:
	var data := SaveFile.read(path(world_name), VERSION)
	var seed_value: Variant = data.get("seed")
	if not (seed_value is int or seed_value is float):
		if not data.is_empty():
			SaveFile.set_aside(path(world_name))
		return {}
	return data


static func write(world_name: String, data: Dictionary) -> bool:
	return SaveFile.write(path(world_name), data)


## The world as a dictionary: `world_seconds` is how long this world has run.
static func capture(world: World, objects: WorldObjects, world_seconds: float) -> Dictionary:
	var bosses := {}
	for fight in world.encounters:
		bosses[String(fight.realm.id)] = {
			"cleared": fight.phase == Encounter.Phase.CLEARED,
			"looted": world.spawner.boss_looted.has(fight.realm.id),
		}
	var flags: Array[String] = []
	for flag in world.flags():
		flags.append(String(flag))
	return {
		"version": VERSION,
		"seed": world.world_seed,
		"name": world.world_name,
		"world_seconds": world_seconds,
		"flags": flags,
		"bosses": bosses,
		"cleared": world.spawner.cleared_saved(NetworkTime.tick),
		"objects": objects.to_dict(),
	}


## Puts a loaded file's bosses and camps into a freshly built world, before any player is
## spawned (the Warden's corpse must stand on every peer from the start). The objects are
## read with WorldObjects.from_dict by whoever makes the Looting.
static func restore(data: Dictionary, world: World) -> void:
	var bosses: Variant = data.get("bosses")
	if bosses is Dictionary:
		for fight in world.encounters:
			var saved: Variant = (bosses as Dictionary).get(String(fight.realm.id))
			if not saved is Dictionary:
				continue
			if (saved as Dictionary).get("cleared", false) == true:
				fight.restore_cleared()
			if (saved as Dictionary).get("looted", false) == true:
				world.spawner.boss_looted[fight.realm.id] = true
	world.spawner.restore_cleared(data.get("cleared"), NetworkTime.tick)


## The seconds the world ran, 0 for a bad value.
static func seconds_of(data: Dictionary) -> float:
	var seconds: Variant = data.get("world_seconds")
	if (seconds is int or seconds is float) and is_finite(float(seconds)):
		return maxf(float(seconds), 0.0)
	return 0.0


## The world files in `folder`, newest save first: {name, seed, size, mtime, flags, readable}.
## Reads only: a broken file is listed as unreadable, not set aside.
static func list(folder := FOLDER) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() != "json":
			continue
		var file_path := folder + file
		var entry := {
			"name": file.get_basename(),
			"seed": 0,
			"size": _size(file_path),
			"mtime": FileAccess.get_modified_time(file_path),
			"flags": [],
			"readable": false,
		}
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(file_path)) == OK and json.data is Dictionary:
			var data: Dictionary = json.data
			var version: Variant = data.get("version")
			var seed_value: Variant = data.get("seed")
			if (
				(version is int or version is float)
				and int(version) >= 1
				and int(version) <= VERSION
				and (seed_value is int or seed_value is float)
			):
				entry["readable"] = true
				entry["seed"] = int(seed_value)
				var flags: Variant = data.get("flags")
				if flags is Array:
					entry["flags"] = (flags as Array).filter(
						func(f: Variant) -> bool: return f is String
					)
		found.append(entry)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["mtime"] > b["mtime"])
	return found


## Deletes a world's files: to the OS trash when that works ("trash"), else for good ("removed").
## "" when there was nothing to delete.
static func remove(world_name: String, folder := FOLDER, to_trash := true) -> String:
	var file_path := folder + SaveFile.clean(world_name, "world") + ".json"
	if not FileAccess.file_exists(file_path):
		return ""
	var how := "removed"
	if to_trash and OS.move_to_trash(ProjectSettings.globalize_path(file_path)) == OK:
		how = "trash"
	DirAccess.remove_absolute(file_path)
	for extra in [".bak", ".tmp"]:
		DirAccess.remove_absolute(file_path + extra)
	return how


static func _size(file_path: String) -> int:
	var file := FileAccess.open(file_path, FileAccess.READ)
	return file.get_length() if file != null else 0
