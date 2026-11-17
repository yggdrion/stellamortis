class_name CharacterSave
extends RefCounted
## The character file (M23): `user://characters/<name>.json`, kept on the player's machine and
## sent with hello, so it travels between worlds and servers (the server trusts it, clamped).
## Fields: `version`, `id` (the player ID graves know it by), `name`, `inventory`
## (Inventory.to_dict) and `junk` (item ids starred as junk); M54 adds level and perks.

const VERSION := 1
const FOLDER := "user://characters/"


## The file of a character (the name cleaned to `[a-z0-9_-]`).
static func path(character_name: String) -> String:
	return FOLDER + SaveFile.clean(character_name, "player") + ".json"


## The file's content as a dictionary, empty when there is none or it is unusable (a broken file
## is kept aside by SaveFile). `id` is a string and `junk` an array of known items.
static func read(character_name: String) -> Dictionary:
	var data := SaveFile.read(path(character_name), VERSION)
	if data.is_empty():
		return {}
	var player_id: Variant = data.get("id")
	data["id"] = clean_id(player_id) if player_id is String else ""
	data["inventory"] = data["inventory"] if data.get("inventory") is Dictionary else {}
	data["junk"] = junk_of(data.get("junk"))
	return data


## The character as it is written and sent.
static func make(
	player_id: String, character_name: String, inventory: Inventory, junk: Array[StringName]
) -> Dictionary:
	return {
		"version": VERSION,
		"id": player_id,
		"name": character_name,
		"inventory": inventory.to_dict(),
		"junk": junk.map(func(id: StringName) -> String: return String(id)),
	}


static func write(
	player_id: String, character_name: String, inventory: Inventory, junk: Array[StringName]
) -> bool:
	var data := make(player_id, character_name, inventory, junk)
	return SaveFile.write(path(character_name), data)


## The known items out of a saved junk list, whatever the list holds.
static func junk_of(saved: Variant) -> Array[StringName]:
	var junk: Array[StringName] = []
	if saved is Array:
		for id: Variant in saved:
			if id is String and Items.has(StringName(id)) and not junk.has(StringName(id)):
				junk.append(StringName(id))
	return junk


## A player ID as the server keeps it: at most 64 of letters, digits, "_" and "-".
static func clean_id(text: String) -> String:
	var out := ""
	for character in text.left(64):
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			out += character
	return out
