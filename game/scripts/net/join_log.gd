class_name JoinLog
extends RefCounted
## A trace of the steps of opening a room and joining it (PLAN §4.7): one file per process in
## user://logs/, appended and flushed per line so a crash keeps it, and the last lines in memory
## for the F3 overlay. Never put TURN credentials or full SDP in a step.

## Lines kept in memory.
const KEEP := 40

var role := ""
var lines := PackedStringArray()
var _file: FileAccess
var _path := ""


## role is "client" or "server". Without a writable file the log stays in memory.
func _init(log_role: String, path := "") -> void:
	role = log_role
	_path = path if path != "" else "user://logs/join-%s.log" % log_role
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	_file = FileAccess.open(
		_path, FileAccess.READ_WRITE if FileAccess.file_exists(_path) else FileAccess.WRITE
	)
	if _file == null:
		push_warning("join log: cannot write %s, keeping it in memory" % _path)
		return
	_file.seek_end()


func step(what: String, detail := "", room := "", peer := 0) -> void:
	var line := (
		"%s %s room=%s peer=%d %s %s"
		% [Time.get_datetime_string_from_system(true), role, room, peer, what, detail]
	)
	line = line.strip_edges()
	lines.append(line)
	if lines.size() > KEEP:
		lines.remove_at(0)
	if _file != null:
		_file.store_line(line)
		_file.flush()
	print(line)


## The log file for the player to find, "" when memory only.
func path_shown() -> String:
	return ProjectSettings.globalize_path(_path) if _file != null else ""
