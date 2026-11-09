class_name EnemyView
extends Node3D
## How an enemy looks (PLAN §4.5): the KayKit skeleton warrior posed from its state, with the
## telegraph that makes dodging fair: an orange glow building up over the windup and the swing's
## reach and arc drawn on the ground. Parries flash yellow, hits pop damage numbers, a bar shows
## health.

const MODEL := "res://assets/kaykit_skeletons/Skeleton_Warrior.glb"
const BLADE := "res://assets/kaykit/sword_1handed.gltf"
const TELEGRAPH := Color(1.0, 0.45, 0.1)
const LOCKED := Color(1.0, 0.85, 0.35)

var enemy: Enemy
var _model: CharacterModel
var _arc: MeshInstance3D
var _arc_material: StandardMaterial3D
var _bar: MeshInstance3D
var _bar_material: ShaderMaterial
var _last_health := -1.0
var _was_parried := false
var _locked := false
var _marker: MeshInstance3D


func _init(of: Enemy) -> void:
	enemy = of
	name = "View"
	_model = CharacterModel.new(MODEL, {"blade": ["handslot.r", BLADE]})
	add_child(_model)
	_add_arc()
	_add_bar()
	_add_marker()


## Marks this enemy as the own player's lock-on target: an outline and a dot on its chest.
func set_locked(locked: bool) -> void:
	if locked == _locked:
		return
	_locked = locked
	_marker.visible = locked
	_model.outline(LOCKED if locked else Color(0, 0, 0, 0))


func _add_arc() -> void:
	var def := enemy.attack_def()
	var mesh := ArrayMesh.new()
	var points := PackedVector3Array()
	var half := deg_to_rad(def.arc_degrees) / 2.0
	var steps := 24
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		points.append(Vector3.ZERO)
		points.append(Vector3(sin(a0), 0, -cos(a0)) * def.reach)
		points.append(Vector3(sin(a1), 0, -cos(a1)) * def.reach)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_arc_material = StandardMaterial3D.new()
	_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_material.albedo_color = Color(TELEGRAPH, 0.0)
	_arc = MeshInstance3D.new()
	_arc.mesh = mesh
	_arc.material_override = _arc_material
	_arc.position.y = 0.05
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc)


func _add_bar() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 0.12)
	_bar_material = ShaderMaterial.new()
	_bar_material.shader = load("res://shaders/billboard_bar.gdshader")
	_bar = MeshInstance3D.new()
	_bar.mesh = quad
	_bar.material_override = _bar_material
	_bar.position.y = Enemy.HEIGHT + 0.5
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)


func _add_marker() -> void:
	var dot := SphereMesh.new()
	dot.radius = 0.1
	dot.height = 0.2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Transparent, so it draws after the bodies and no_depth_test keeps it on top.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = LOCKED
	material.render_priority = 1
	_marker = MeshInstance3D.new()
	_marker.mesh = dot
	_marker.material_override = material
	_marker.position.y = Enemy.HEIGHT * 0.6
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)


func _process(_delta: float) -> void:
	if _last_health >= 0.0 and enemy.health < _last_health:
		_model.flash(Color(1, 1, 1, 0.6), 0.1)
		_pop_number(_last_health - enemy.health, enemy.parried)
	_last_health = enemy.health
	if enemy.parried and not _was_parried:
		_model.flash(Color(1, 0.9, 0.2, 0.7), 0.3)
		_pop_text("PARRY", Color(1, 0.9, 0.3))
	_was_parried = enemy.parried
	_bar_material.set_shader_parameter("fill", enemy.health / enemy.max_health)
	_bar.visible = enemy.health < enemy.max_health and enemy.alive()
	_pose()


func _pose() -> void:
	var def := enemy.attack_def()
	var time := enemy.action_time + NetworkTime.tick_factor
	var total := def.total_ticks()
	_arc_material.albedo_color.a = 0.0
	match enemy.action:
		Enemy.Action.WINDUP:
			var progress := time / def.windup_ticks()
			_model.play_timed(def.animation, time / total, total / 30.0)
			_model.glow(Color(TELEGRAPH, 0.15 + 0.45 * progress))
			_arc_material.albedo_color.a = 0.1 + 0.35 * progress
		Enemy.Action.STRIKE:
			var at := def.windup_ticks() + time
			_model.play_timed(def.animation, at / total, total / 30.0)
			_model.glow(Color(1, 0.2, 0.1, 0.6))
			_arc_material.albedo_color = Color(1, 0.2, 0.1, 0.6)
		Enemy.Action.RECOVER:
			var at := def.active_end_ticks() + time
			_model.play_timed(def.animation, at / total, total / 30.0)
			_model.glow(Color(0, 0, 0, 0))
		Enemy.Action.STAGGER:
			var ticks := Combat.ticks(enemy.stagger_time)
			_model.play_timed(&"Hit_B", time / ticks, enemy.stagger_time)
		Enemy.Action.DOWN:
			_model.play_timed(&"Death_C_Skeletons", time / Combat.ticks(enemy.down_time), 2.0)
		_:
			_model.loop(&"Idle_Combat")
			_model.glow(Color(0, 0, 0, 0))


func _pop_number(amount: float, riposte: bool) -> void:
	_pop_text("%d" % roundi(amount), Color(1, 0.85, 0.3) if riposte else Color.WHITE)


func _pop_text(text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 64
	label.pixel_size = 0.006
	label.outline_size = 14
	label.position = Vector3(randf_range(-0.3, 0.3), Enemy.HEIGHT + 0.2, 0)
	add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 0.9, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
