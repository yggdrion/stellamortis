class_name SaveFile
extends RefCounted
## Reading and writing the JSON save files (world and character, M23). A write goes to a temp
## file first and replaces the real one only when complete, so a crash or power cut leaves the
## old file whole. A file that cannot be read is kept aside as `<name>.bad-<unix time>` and
## reads as empty: a broken or hostile file never crashes anything and is never overwritten.

## The format version of the files written now; a file with a newer one is kept aside.
const VERSION := 1


## Writes `data` to `path` (the folder is made). The old file is moved to `.bak` first because
## DirAccess.rename does not replace a file on Windows; it is removed once the new one is in.
static func write(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	var stored := file.store_string(JSON.stringify(data))
	file.flush()
	file.close()
	if not stored:
		DirAccess.remove_absolute(temp)
		return false
	var backup := path + ".bak"
	var had_old := FileAccess.file_exists(path)
	if had_old:
		DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(path, backup) != OK:
			DirAccess.remove_absolute(temp)
			return false
	if DirAccess.rename_absolute(temp, path) != OK:
		if had_old:
			DirAccess.rename_absolute(backup, path)
		DirAccess.remove_absolute(temp)
		return false
	if had_old:
		DirAccess.remove_absolute(backup)
	return true


## The file as a dictionary, empty when it is missing or unusable (then it is kept aside).
## `newest` is the highest `version` the caller understands. A `.bak` left by a write that died
## between its two renames stands in for a missing file.
static func read(path: String, newest := VERSION) -> Dictionary:
	if not FileAccess.file_exists(path):
		if not FileAccess.file_exists(path + ".bak"):
			return {}
		path += ".bak"
	var json := JSON.new()
	var parsed := json.parse(FileAccess.get_file_as_string(path)) == OK
	var data: Variant = json.data if parsed else null
	var version: Variant = (data as Dictionary).get("version") if data is Dictionary else null
	if not (version is int or version is float) or int(version) < 1 or int(version) > newest:
		set_aside(path)
		return {}
	return migrate(data as Dictionary)


## Brings an older file up to the current format (nothing differs yet).
static func migrate(data: Dictionary) -> Dictionary:
	return data


## Renames an unusable file so it is neither read again nor overwritten.
static func set_aside(path: String) -> void:
	DirAccess.rename_absolute(path, "%s.bad-%d" % [path, int(Time.get_unix_time_from_system())])


## A name as a file name: lower case letters, digits, "_" and "-", at most 32 characters.
static func clean(text: String, fallback: String) -> String:
	var out := ""
	for character in text.strip_edges().to_lower().left(32):
		out += character if character in "abcdefghijklmnopqrstuvwxyz0123456789_-" else "_"
	return out if out != "" else fallback
