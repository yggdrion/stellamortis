class_name EnemyView
extends Node3D
## How an enemy looks (PLAN §4.5, §4.6): a KayKit skeleton posed from its state, with the
## telegraph that makes dodging fair: an orange glow building up over the windup and the
## swing's area drawn on the ground. Parries flash yellow, hits pop damage numbers, a bar shows
## health (the Warden's is on the HUD), bolts glow magenta, the Warden's gravity well is a
## pulsing shell with motes falling in.

const SKELETONS := "res://assets/kaykit_skeletons/"
const TELEGRAPH := Color(1.0, 0.45, 0.1)
const LOCKED := Color(1.0, 0.85, 0.35)
## Moving faster than this (m/s) plays the walk.
const WALKING := 0.4

var enemy: Enemy
var _model: CharacterModel
var _arc: MeshInstance3D
var _arc_material: StandardMaterial3D
## Arc meshes by attack id.
var _arcs := {}
var _bar: MeshInstance3D
var _bar_material: ShaderMaterial
var _well: MeshInstance3D
var _well_material: ShaderMaterial
var _motes: GPUParticles3D
var _last_health := -1.0
var _was_parried := false
var _locked := false
var _marker: MeshInstance3D


func _init(of: Enemy) -> void:
	enemy = of
	name = "View"
	_model = _make_model()
	add_child(_model)
	_add_arc()
	_add_bar()
	_add_marker()
	if not enemy.bolt_life.is_empty():
		add_child(BoltsView.new(enemy, BoltsView.ENEMY_COLOR))
	if enemy is Warden:
		_add_well()


## Which skeleton, holding what, at which size.
func _make_model() -> CharacterModel:
	if enemy is Warden:
		var blade := SKELETONS + "Skeleton_Blade.gltf"
		return CharacterModel.new(
			SKELETONS + "Skeleton_Warrior.glb",
			{"blade": ["handslot.r", blade]},
			enemy.height / Enemy.HEIGHT
		)
	if enemy is Mob and (enemy as Mob).ranged:
		var crossbow := SKELETONS + "Skeleton_Crossbow.gltf"
		return CharacterModel.new(
			SKELETONS + "Skeleton_Rogue.glb", {"crossbow": ["handslot.r", crossbow]}
		)
	if enemy is Mob:
		var axe := SKELETONS + "Skeleton_Axe.gltf"
		return CharacterModel.new(SKELETONS + "Skeleton_Minion.glb", {"axe": ["handslot.r", axe]})
	var sword := "res://assets/kaykit/sword_1handed.gltf"
	return CharacterModel.new(SKELETONS + "Skeleton_Warrior.glb", {"blade": ["handslot.r", sword]})


## Marks this enemy as the own player's lock-on target: an outline and a dot on its chest.
func set_locked(locked: bool) -> void:
	if locked == _locked:
		return
	_locked = locked
	_marker.visible = locked
	_model.outline(LOCKED if locked else Color(0, 0, 0, 0))


func _add_arc() -> void:
	_arc_material = StandardMaterial3D.new()
	_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_material.albedo_color = Color(TELEGRAPH, 0.0)
	_arc = MeshInstance3D.new()
	_arc.material_override = _arc_material
	_arc.position.y = 0.05
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc)


## The ground shape a melee attack hits: a fan of its reach and arc around its origin.
func _arc_mesh(def: AttackDef) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var points := PackedVector3Array()
	var half := deg_to_rad(def.arc_degrees) / 2.0
	var steps := 48
	var reach := def.reach + SimPlayer.RADIUS
	var origin := Vector3(0, 0, -def.offset)
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		points.append(origin)
		points.append(origin + Vector3(sin(a0), 0, -cos(a0)) * reach)
		points.append(origin + Vector3(sin(a1), 0, -cos(a1)) * reach)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_bar() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 0.12)
	_bar_material = ShaderMaterial.new()
	_bar_material.shader = load("res://shaders/billboard_bar.gdshader")
	_bar = MeshInstance3D.new()
	_bar.mesh = quad
	_bar.material_override = _bar_material
	_bar.position.y = enemy.height + 0.5
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
	_marker.position.y = enemy.height * 0.6
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)


func _add_well() -> void:
	var shell := SphereMesh.new()
	shell.radius = Warden.WELL_REACH
	shell.height = Warden.WELL_REACH * 2.0
	_well_material = ShaderMaterial.new()
	_well_material.shader = load("res://shaders/gravity_well.gdshader")
	_well = MeshInstance3D.new()
	_well.mesh = shell
	_well.material_override = _well_material
	_well.position.y = enemy.height / 2.0
	_well.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_well.visible = false
	add_child(_well)
	_motes = GPUParticles3D.new()
	_motes.amount = 400
	_motes.lifetime = 1.2
	_motes.emitting = false
	_motes.position.y = enemy.height / 2.0
	_motes.visibility_aabb = AABB(
		Vector3.ONE * -Warden.WELL_REACH, Vector3.ONE * Warden.WELL_REACH * 2
	)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	process.emission_sphere_radius = Warden.WELL_REACH - 0.5
	process.gravity = Vector3.ZERO
	process.radial_accel_min = -16.0
	process.radial_accel_max = -10.0
	process.scale_min = 0.5
	process.scale_max = 1.2
	_motes.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var mote := StandardMaterial3D.new()
	mote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mote.albedo_color = Color(0.75, 0.5, 1.0)
	mote.emission_enabled = true
	mote.emission = Color(0.6, 0.25, 1.0)
	mote.emission_energy_multiplier = 4.0
	quad.material = mote
	_motes.draw_pass_1 = quad
	add_child(_motes)


func _process(_delta: float) -> void:
	visible = enemy.action != Enemy.Action.HIDDEN
	if _last_health >= 0.0 and enemy.health < _last_health and enemy.alive():
		_model.flash(Color(1, 1, 1, 0.6), 0.1)
		_pop_number(_last_health - enemy.health, enemy.parried)
	elif _last_health >= 0.0 and enemy.health < _last_health:
		_pop_number(_last_health - enemy.health, false)
	_last_health = enemy.health
	if enemy.parried and not _was_parried:
		_model.flash(Color(1, 0.9, 0.2, 0.7), 0.3)
		_pop_text("PARRY", Color(1, 0.9, 0.3))
	_was_parried = enemy.parried
	_bar_material.set_shader_parameter("fill", enemy.health / enemy.max_health)
	_bar.visible = (enemy.health < enemy.max_health and enemy.alive() and not enemy is Warden)
	_pose()
	if _well:
		_show_well()


func _show_well() -> void:
	var warden := enemy as Warden
	var seconds := warden.well_time / 30.0
	var strength := clampf(minf(seconds, Warden.WELL_TIME - seconds) * 2.0, 0.0, 1.0)
	_well.visible = strength > 0.0
	_well_material.set_shader_parameter("strength", strength)
	_motes.emitting = warden.well_time > 0


func _pose() -> void:
	var def := enemy.attack_def()
	var time := enemy.action_time + NetworkTime.tick_factor
	var windup := enemy.windup_ticks()
	var active := Combat.ticks(def.active)
	var total := float(windup + active + Combat.ticks(def.recover))
	var seconds := total / 30.0
	_arc_material.albedo_color.a = 0.0
	if def.melee():
		if not _arcs.has(def.resource_path):
			_arcs[def.resource_path] = _arc_mesh(def)
		_arc.mesh = _arcs[def.resource_path]
	match enemy.action:
		Enemy.Action.WINDUP:
			var progress := time / windup
			_model.play_timed(def.animation, time / total, seconds)
			_model.glow(Color(TELEGRAPH, 0.15 + 0.45 * progress))
			if def.melee():
				_arc_material.albedo_color = Color(TELEGRAPH, 0.1 + 0.35 * progress)
		Enemy.Action.STRIKE:
			_model.play_timed(def.animation, (windup + time) / total, seconds)
			_model.glow(Color(1, 0.2, 0.1, 0.6))
			if def.melee():
				_arc_material.albedo_color = Color(1, 0.2, 0.1, 0.6)
		Enemy.Action.RECOVER:
			_model.play_timed(def.animation, (windup + active + time) / total, seconds)
			_model.glow(Color(0, 0, 0, 0))
		Enemy.Action.STAGGER:
			var ticks := Combat.ticks(enemy.stagger_time)
			_model.play_timed(&"Hit_B", time / ticks, enemy.stagger_time)
		Enemy.Action.DOWN:
			_model.play_timed(&"Death_C_Skeletons", time / Combat.ticks(enemy.down_time), 2.0)
		Enemy.Action.RISE:
			var rise := Combat.ticks(Warden.RISE_TIME)
			_model.play_timed(&"Spawn_Ground_Skeletons", time / rise, Warden.RISE_TIME)
		_:
			_idle_or_walk()


func _idle_or_walk() -> void:
	_model.glow(Color(0, 0, 0, 0))
	var moving := enemy.velocity - enemy.up() * enemy.velocity.dot(enemy.up())
	var speed := moving.length()
	if speed > WALKING:
		_model.loop(&"Walking_D_Skeletons", speed / 2.0)
	else:
		_model.loop(&"Idle_Combat")


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
	label.position = Vector3(randf_range(-0.3, 0.3), enemy.height + 0.2, 0)
	add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 0.9, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
