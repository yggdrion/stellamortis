class_name Hud
extends CanvasLayer
## Health and stamina bars, the death notice, a controls hint (PLAN §4.5), and on top the
## encounter: mobs left, the Warden's bar, the victory notice (PLAN §4.6).

const HINT := (
	"Sword: LMB attack   Q heavy   RMB block (just before a hit: parry)\n"
	+ "Crossbow: RMB aim   hold LMB to draw, release to shoot\n"
	+ "MMB / Tab lock-on (flick the mouse or wheel: switch target)\n"
	+ "1 / 2 / wheel weapon   Ctrl / C roll   Shift sprint   Space jump   F3 debug   F4 graphics"
)

var player: SimPlayer
var encounter: Encounter
var _health: ProgressBar
var _stamina: ProgressBar
var _dead: Label
var _weapon: Label
var _crosshair: Crosshair
var _goal: Label
var _boss_bar: ProgressBar


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

	_weapon = Label.new()
	_weapon.add_theme_font_size_override("font_size", 15)
	box.add_child(_weapon)
	box.move_child(_weapon, 0)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_crosshair)

	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 20)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top)
	_goal = Label.new()
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal.add_theme_font_size_override("font_size", 20)
	_goal.add_theme_constant_override("outline_size", 6)
	_goal.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	top.add_child(_goal)
	_boss_bar = _bar(Color(0.62, 0.2, 0.9), 560)
	_boss_bar.custom_minimum_size.y = 16
	top.add_child(_boss_bar)

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
	var crossbow := player.weapon == SimPlayer.Weapon.CROSSBOW
	_weapon.text = "[2] Crossbow" if crossbow else "[1] Sword and shield"
	_crosshair.visible = crossbow and player.action != SimPlayer.Action.DEAD
	var draw := 0.0
	if player.action == SimPlayer.Action.DRAW:
		draw = clampf(float(player.action_time) / Combat.ticks(t.draw_time), 0.0, 1.0)
	_crosshair.charge = draw
	_show_encounter()


func _show_encounter() -> void:
	_boss_bar.visible = false
	if encounter == null:
		_goal.text = ""
		return
	match encounter.phase:
		Encounter.Phase.MOBS:
			var left := encounter.mobs_left()
			_goal.text = "Skeletons to the south: %d of %d left" % [left, encounter.mobs.size()]
		Encounter.Phase.BOSS:
			var boss := encounter.boss
			var phase := "  (enraged)" if boss.phase_2() else ""
			_goal.text = "The Warden" + phase
			_boss_bar.visible = true
			_boss_bar.max_value = boss.max_health
			_boss_bar.value = boss.health
		Encounter.Phase.CLEARED:
			var seconds := Encounter.RESTART_AFTER - encounter.phase_time / 30.0
			_goal.text = "The Warden has fallen. The arena wakes again in %d s" % ceili(seconds)


## A dot with a ring that fills while the crossbow is drawn.
class Crosshair:
	extends Control

	var charge := 0.0:
		set(value):
			if value != charge:
				charge = value
				queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1, 0.9))
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
		if charge > 0.0:
			var full := charge >= 1.0
			var color := Color(0.4, 1.0, 1.0) if full else Color(1, 1, 1, 0.9)
			draw_arc(Vector2.ZERO, 14.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 48, color, 3.0, true)
