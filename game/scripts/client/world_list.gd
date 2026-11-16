class_name WorldList
extends VBoxContainer
## The world picker behind the main menu's Play (M23 task 5): a row per file in
## `user://worlds/`, Continue (the newest save), a new world (name, optional seed) and Delete
## with a confirmation. Solo or Host is chosen on top; joining by code never asks.

## `seed_text` is "" for a world that exists.
signal chosen(mode: String, world_name: String, seed_text: String)
signal closed

var folder := WorldSave.FOLDER
var _mode: OptionButton
var _mode_row: Control
var _list: VBoxContainer
var _name: LineEdit
var _seed: LineEdit
var _note: Label
var _confirm: VBoxContainer
var _body: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size.x = 520
	add_child(Menus.title("WORLDS", 28))
	_mode = OptionButton.new()
	_mode.add_item("Solo")
	_mode.add_item("Host a room")
	_mode_row = Menus.row("Play as", _mode)
	add_child(_mode_row)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	add_child(_body)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 190
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_list)
	_body.add_child(scroll)
	_body.add_child(Menus.button("Continue", _continue))

	_name = LineEdit.new()
	_name.placeholder_text = "New world name"
	_name.max_length = 32
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed = LineEdit.new()
	_seed.placeholder_text = "Seed (random)"
	_seed.max_length = 12
	_seed.custom_minimum_size.x = 170
	var create := HBoxContainer.new()
	create.add_child(_name)
	create.add_child(_seed)
	_body.add_child(create)
	_body.add_child(Menus.button("New world", _create))

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_font_override("font", Menus.body_font())
	_body.add_child(_note)
	_body.add_child(Menus.button("Back", func() -> void: closed.emit()))

	_confirm = VBoxContainer.new()
	_confirm.visible = false
	add_child(_confirm)
	refresh()


## Reads the folder again and rebuilds the rows.
func refresh() -> void:
	for row in _list.get_children():
		_list.remove_child(row)
		row.queue_free()
	var worlds := WorldSave.list(folder)
	if worlds.is_empty():
		var none := Label.new()
		none.text = "No worlds yet. Make one below."
		_list.add_child(none)
	for world in worlds:
		_list.add_child(_row(world))


func _row(world: Dictionary) -> Control:
	var line := HBoxContainer.new()
	var world_name := world["name"] as String
	var text := Label.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if world["readable"]:
		text.text = "%s\nseed %d, %s, %s" % [world_name, world["seed"], _size(world), _ago(world)]
		var flags := world["flags"] as Array
		if not flags.is_empty():
			text.text += ", " + ", ".join(flags)
	else:
		text.text = "%s\nunreadable" % world_name
		text.add_theme_color_override("font_color", Color(0.85, 0.45, 0.35))
	line.add_child(text)
	if world["readable"]:
		line.add_child(Menus.button("Play", _play.bind(world_name, "")))
	line.add_child(Menus.button("Delete", _ask_delete.bind(world_name)))
	return line


func _size(world: Dictionary) -> String:
	var bytes := int(world["size"])
	return "%d KB" % ceili(bytes / 1024.0) if bytes >= 1024 else "%d B" % bytes


func _ago(world: Dictionary) -> String:
	var seconds := maxi(int(Time.get_unix_time_from_system()) - int(world["mtime"]), 0)
	if seconds < 90:
		return "just now"
	if seconds < 5400:
		return "%d min ago" % roundi(seconds / 60.0)
	if seconds < 129600:
		return "%d h ago" % roundi(seconds / 3600.0)
	return "%d days ago" % roundi(seconds / 86400.0)


func _play(world_name: String, seed_text: String) -> void:
	chosen.emit("host" if _mode.selected == 1 else "solo", world_name, seed_text)


func _continue() -> void:
	for world in WorldSave.list(folder):
		if world["readable"]:
			_play(world["name"], "")
			return
	_note.text = "No world to continue."


func _create() -> void:
	var world_name := SaveFile.clean(_name.text, "")
	if world_name == "":
		_note.text = "Give the world a name (letters, digits, - and _)."
		return
	var seed_text := _seed.text.strip_edges()
	if seed_text != "" and not seed_text.is_valid_int():
		_note.text = "The seed is a whole number, or empty for a random one."
		return
	# A world of that name that exists keeps its own seed: the server reads it from the file.
	_play(world_name, seed_text if seed_text != "" else str(randi() & 0x7fffffff))


func _ask_delete(world_name: String) -> void:
	_body.visible = false
	_mode_row.visible = false
	for child in _confirm.get_children():
		_confirm.remove_child(child)
		child.queue_free()
	var ask := Label.new()
	ask.text = (
		(
			'Delete the world "%s"? Its bosses, camps and objects are lost. The files go to '
			+ "the OS trash if that works, else they are removed for good."
		)
		% world_name
	)
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm.add_child(ask)
	_confirm.add_child(Menus.button("Delete %s" % world_name, _delete.bind(world_name)))
	_confirm.add_child(Menus.button("Keep it", _leave_confirm))
	_confirm.visible = true


func _delete(world_name: String) -> void:
	var how := WorldSave.remove(world_name, folder)
	if how == "trash":
		_note.text = "%s moved to the trash." % world_name
	elif how == "removed":
		_note.text = "%s deleted for good (the trash was not available)." % world_name
	else:
		_note.text = "%s was already gone." % world_name
	_leave_confirm()


func _leave_confirm() -> void:
	_confirm.visible = false
	_body.visible = true
	_mode_row.visible = true
	refresh()
