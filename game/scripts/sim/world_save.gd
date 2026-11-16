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
