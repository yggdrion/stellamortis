class_name BodyPicker
extends HBoxContainer
## The four player bodies side by side, each a slowly turning idle model; a click picks one and
## saves it in Settings.body (M40 task 4). Skin and hair colors show as peer 0's.

signal picked(index: int)

const SLOT := Vector2(88, 150)
const TURN := 0.6

var _pivots: Array[Node3D] = []
var _frames: Array[PanelContainer] = []


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 6)
	for i in Gear.PLAYER_BODIES.size():
		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_PASS
		var shown := SubViewportContainer.new()
		shown.stretch = true
		shown.custom_minimum_size = SLOT
		shown.mouse_filter = Control.MOUSE_FILTER_STOP
		shown.gui_input.connect(_on_input.bind(i))
		frame.add_child(shown)
		add_child(frame)
		_frames.append(frame)
		shown.add_child(_viewport(i))
		(_pivots[i].get_child(0) as CharacterModel).loop(&"Sword_Idle")
	_mark()


func _process(delta: float) -> void:
	for pivot in _pivots:
		pivot.rotate_y(TURN * delta)


func _viewport(index: int) -> SubViewport:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.size = Vector2i(SLOT)
	var pivot := Node3D.new()
	pivot.add_child(Gear.ranger(0, {}, index))
	view.add_child(pivot)
	_pivots.append(pivot)
	var camera := Camera3D.new()
	camera.fov = 30.0
	view.add_child(camera)
	camera.position = Vector3(0, 0.9, 4.3)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 25, 0)
	sun.light_energy = 1.4
	view.add_child(sun)
	var fill := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.76, 0.72)
	fill.environment = env
	view.add_child(fill)
	return view


func _on_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Settings.body = index
		Settings.save()
		_mark()
		picked.emit(index)


func _mark() -> void:
	for i in _frames.size():
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.09, 0.075, 0.065, 0.6)
		box.border_color = Color(Menus.PARCHMENT, 0.9 if i == Settings.body else 0.15)
		box.set_border_width_all(2 if i == Settings.body else 1)
		_frames[i].add_theme_stylebox_override("panel", box)
