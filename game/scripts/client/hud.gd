class_name Hud
extends CanvasLayer
## Health and stamina bars with the damage taken popping next to them, the death notice, a
## controls hint (PLAN §4.5), and on top the encounter: machines left, the Warden's bar, the
## victory notice (PLAN §4.6). Thin flat bars, small spaced capitals in Rajdhani (OFL), muted
## colors: an instrument readout, not a toy.

const HINT := (
	"Blade: LMB attack   Q heavy   RMB shield (just before a hit: parry)\n"
	+ "Revolver: RMB aim   hold LMB to charge, release to fire\n"
	+ "1 / 2 / wheel weapon   Ctrl / C roll   Shift sprint   Space jump\n"
	+ "Esc menu   F3 debug   F4 graphics"
)
const FONT := "res://assets/fonts/Rajdhani-SemiBold.ttf"
const TEXT := Color(0.78, 0.84, 0.88)
const HEALTH := Color(0.74, 0.2, 0.17)
const STAMINA := Color(0.52, 0.62, 0.68)
const BOSS := Color(0.62, 0.12, 0.1)

var player: SimPlayer
var encounter: Encounter
## The lobby room code friends join with, "" when not hosting through the lobby.
var room := ""
var _health: ProgressBar
var _stamina: ProgressBar
var _dead: Label
var _weapon: Label
var _crosshair: Crosshair
var _goal: Label
var _room: Label
var _notice: Label
var _notice_left := 0.0
var _boss_bar: ProgressBar
var _last_health := -1.0
var _respawns := -1


func _ready() -> void:
	var font := FontVariation.new()
	font.base_font = load(FONT)
	font.spacing_glyph = 2
	var theme := Theme.new()
	theme.default_font = font
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.7))
	theme.set_constant("outline_size", "Label", 4)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(24, -84)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 6)
	root.add_child(box)
	_health = _bar(HEALTH, 300)
	_stamina = _bar(STAMINA, 240)
	box.add_child(_health)
	box.add_child(_stamina)

	var hint := Label.new()
	hint.text = HINT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.modulate = Color(1, 1, 1, 0.45)
	hint.add_theme_font_size_override("font_size", 14)
	hint.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16
	)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(hint)

	_weapon = Label.new()
	_weapon.add_theme_font_size_override("font_size", 16)
	box.add_child(_weapon)
	box.move_child(_weapon, 0)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(_crosshair)

	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 20)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(top)
	_goal = Label.new()
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal.add_theme_font_size_override("font_size", 19)
	top.add_child(_goal)
	_boss_bar = _bar(BOSS, 560)
	_boss_bar.custom_minimum_size.y = 8
	top.add_child(_boss_bar)

	_room = Label.new()
	_room.add_theme_font_size_override("font_size", 15)
	_room.modulate = Color(1, 1, 1, 0.8)
	_room.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_room.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_room.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_room)
	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size", 18)
	_notice.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 140
	)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_notice)

	_dead = Label.new()
	_dead.text = "YOU DIED"
	_dead.add_theme_font_size_override("font_size", 52)
	_dead.add_theme_constant_override("outline_size", 0)
	_dead.add_theme_color_override("font_color", Color(0.8, 0.2, 0.16))
	_dead.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead.visible = false
	root.add_child(_dead)


func _bar(color: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 6)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.02, 0.03, 0.04, 0.6)
	back.border_color = Color(TEXT, 0.25)
	back.set_border_width_all(1)
	back.expand_margin_left = 1
	back.expand_margin_right = 1
	back.expand_margin_top = 1
	back.expand_margin_bottom = 1
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar


## A line near the bottom for a few seconds.
func notice(text: String) -> void:
	_notice.text = text
	_notice_left = 2.5


func _process(delta: float) -> void:
	visible = player != null
	if player == null:
		return
	_notice_left = maxf(0.0, _notice_left - delta)
	_notice.visible = _notice_left > 0.0
	_room.text = "Room %s  (F2 copies it)" % room if room != "" else ""
	var t := Tuning.data()
	_health.max_value = t.max_health
	_health.value = player.health
	_show_damage()
	_stamina.max_value = t.max_stamina
	_stamina.value = player.stamina
	_dead.visible = player.action == SimPlayer.Action.DEAD
	var crossbow := player.weapon == SimPlayer.Weapon.CROSSBOW
	_weapon.text = "2  REVOLVER" if crossbow else "1  BLADE · SHIELD"
	_crosshair.visible = crossbow and player.action != SimPlayer.Action.DEAD
	var draw := 0.0
	if player.action == SimPlayer.Action.DRAW:
		draw = clampf(float(player.action_time) / Combat.ticks(t.draw_time), 0.0, 1.0)
	_crosshair.charge = draw
	_show_encounter()


## Pops the damage the own player just took next to the health bar: blocked hits smaller and
## grey. A respawn refills health without popping.
func _show_damage() -> void:
	if _respawns != player.respawns:
		_respawns = player.respawns
		_last_health = player.health
	var lost := _last_health - player.health
	_last_health = player.health
	if lost < 0.5:
		return
	var blocked := player.action == SimPlayer.Action.BLOCK
	var label := Label.new()
	label.text = "-%d" % roundi(lost)
	label.add_theme_font_size_override("font_size", 18 if blocked else 26)
	label.add_theme_color_override(
		"font_color", Color(0.6, 0.62, 0.64) if blocked else HEALTH.lightened(0.25)
	)
	var bar := _health.get_global_rect()
	label.position = Vector2(bar.end.x + 12.0 + randf_range(0.0, 16.0), bar.position.y - 14.0)
	_health.get_parent().get_parent().add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 36.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


func _show_encounter() -> void:
	_boss_bar.visible = false
	if encounter == null:
		_goal.text = ""
		return
	match encounter.phase:
		Encounter.Phase.MOBS:
			var left := encounter.mobs_left()
			_goal.text = "MACHINES TO THE SOUTH   %d / %d" % [left, encounter.mobs.size()]
		Encounter.Phase.BOSS:
			var boss := encounter.boss
			var phase := "   OVERDRIVE" if boss.phase_2() else ""
			_goal.text = "THE WARDEN" + phase
			_boss_bar.visible = true
			_boss_bar.max_value = boss.max_health
			_boss_bar.value = boss.health
		Encounter.Phase.CLEARED:
			var seconds := Encounter.RESTART_AFTER - encounter.phase_time / 30.0
			_goal.text = "WARDEN DOWN   REACTIVATION IN %d S" % ceili(seconds)


## Four short ticks around a gap, and a thin ring that fills while the shot charges.
class Crosshair:
	extends Control

	var charge := 0.0:
		set(value):
			if value != charge:
				charge = value
				queue_redraw()

	func _draw() -> void:
		var tick := Color(TEXT, 0.85)
		for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(direction * 5.0, direction * 11.0, tick, 1.5, true)
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 64, Color(TEXT, 0.15), 1.0, true)
		if charge > 0.0:
			var full := charge >= 1.0
			var color := Gear.ACCENT if full else Color(TEXT, 0.9)
			draw_arc(Vector2.ZERO, 16.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 64, color, 2.0, true)
