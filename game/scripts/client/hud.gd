class_name Hud
extends CanvasLayer
## Health and stamina bars, the death notice and a controls hint (PLAN §4.5).

const HINT := (
	"LMB attack   Q / MMB heavy   RMB block (tap just before a hit: parry)\n"
	+ "Ctrl / C roll   Shift sprint   Space jump   F3 debug   F4 graphics"
)

var player: SimPlayer
var _health: ProgressBar
var _stamina: ProgressBar
var _dead: Label


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(24, -84)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_health = _bar(Color(0.8, 0.16, 0.14), 320)
	_stamina = _bar(Color(0.35, 0.8, 0.3), 260)
	box.add_child(_health)
	box.add_child(_stamina)

	var hint := Label.new()
	hint.text = HINT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.add_theme_font_size_override("font_size", 13)
	hint.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16
	)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(hint)

	_dead = Label.new()
	_dead.text = "You died"
	_dead.add_theme_font_size_override("font_size", 56)
	_dead.add_theme_color_override("font_color", Color(0.85, 0.15, 0.12))
	_dead.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead.visible = false
	add_child(_dead)


func _bar(color: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 14)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	back.border_color = Color(0, 0, 0, 0.8)
	back.set_border_width_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar


func _process(_delta: float) -> void:
	visible = player != null
	if player == null:
		return
	var t := Tuning.data()
	_health.max_value = t.max_health
	_health.value = player.health
	_stamina.max_value = t.max_stamina
	_stamina.value = player.stamina
	_dead.visible = player.action == SimPlayer.Action.DEAD
