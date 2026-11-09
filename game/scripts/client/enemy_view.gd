class_name EnemyView
extends Node3D
## How an enemy looks (PLAN §4.5, §4.6): a model posed from its state (training mannequins in a
## pale suit, a four legged walker, an eye drone and, for the Warden, a big six legged walker;
## robots from Quaternius, CC0), with the telegraph that makes dodging fair: an orange glow
## building up over the windup and the swing's area drawn on the ground. Parries flash yellow,
## hits pop damage numbers, a bar shows health (the Warden's is on the HUD), bolts glow red, the
## Warden's gravity well is a pulsing shell with motes falling in.

const ROBOTS := "res://assets/quaternius/robots/"
## Clips per model: idle, walk, hit, down (powering off or dying), rise (down played backwards).
## down_time: how long the down clip runs (seconds).
const HUMAN_CLIPS := {
	"idle": &"Sword_Idle",
	"walk": &"Walk",
	"hit": &"Hit_Chest",
	"down": &"Death01",
	"down_time": 1.6
}
const ROBOT_CLIPS := {
	"idle": &"Idle", "walk": &"Walk", "hit": &"Hit", "down": &"TurnOff", "down_time": 0.6
}
const DRONE_CLIPS := {
	"idle": &"Idle", "walk": &"Idle", "hit": &"Hit", "down": &"BackFlip", "down_time": 1.0
}
## Pale suit and orange seams for the training mannequins.
const DUMMY_ARMOR := Color(0.55, 0.56, 0.58)
const DUMMY_ACCENT := Color(1.0, 0.5, 0.15)
## Hover height of the drone's center.
const DRONE_LIFT := 1.3
const TELEGRAPH := Color(1.0, 0.45, 0.1)
## Moving faster than this (m/s) plays the walk.
const WALKING := 0.4

var enemy: Enemy
var _model: CharacterModel
var _arc: MeshInstance3D
var _arc_material: StandardMaterial3D
## The bright edge around the area.
var _edge: MeshInstance3D
var _edge_material: StandardMaterial3D
## Fill and edge meshes by attack path: [fill, edge].
var _arcs := {}
var _bar: MeshInstance3D
var _bar_material: ShaderMaterial
var _well: MeshInstance3D
var _well_material: ShaderMaterial
var _motes: GPUParticles3D
var _last_health := -1.0
var _was_parried := false
var _clips := ROBOT_CLIPS


func _init(of: Enemy) -> void:
	enemy = of
	name = "View"
	_model = _make_model()
	add_child(_model)
	_add_arc()
	_add_bar()
	if not enemy.bolt_life.is_empty():
		add_child(BoltsView.new(enemy, BoltsView.ENEMY_COLOR))
	if enemy is Warden:
		_add_well()


## Which model at which size, with its clips. Robots light up their emission maps (eyes,
## vents); the textures ship with the pack but the glTF files don't reference them.
func _make_model() -> CharacterModel:
	var model: CharacterModel
	if enemy is Warden:
		model = CharacterModel.new(ROBOTS + "Enemy_Trilobite.gltf", {}, enemy.height / 2.5)
		model.light_up(load(ROBOTS + "T_Enemies_Large_Emissive.png"), 6.0)
		return model
	if enemy is Mob and (enemy as Mob).ranged:
		_clips = DRONE_CLIPS
		model = CharacterModel.new(ROBOTS + "Enemy_EyeDrone.gltf", {}, 0.8, DRONE_LIFT)
		model.light_up(load(ROBOTS + "T_Enemies_Emissive.png"), 6.0)
		return model
	if enemy is Mob:
		model = CharacterModel.new(ROBOTS + "Enemy_QuadShell.gltf", {}, 1.1)
		model.light_up(load(ROBOTS + "T_Enemies_Emissive.png"), 6.0)
		return model
	_clips = HUMAN_CLIPS
	model = CharacterModel.new(
		CharacterModel.HUMAN,
		{
			"blade": ["RightHand", Gear.blade(DUMMY_ACCENT)],
			"visor": ["Head", Gear.visor(DUMMY_ACCENT)]
		}
	)
	var suit := Gear.suit(DUMMY_ACCENT, DUMMY_ARMOR)
	model.skin(suit[0], {1: suit[1]})
	return model


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
	_edge_material = _arc_material.duplicate() as StandardMaterial3D
	_edge = MeshInstance3D.new()
	_edge.material_override = _edge_material
	_edge.position.y = 0.06
	_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_edge)


## The ground shape a melee attack hits: a fan of its reach and arc around its origin, and a
## thin band along its border.
func _arc_meshes(def: AttackDef) -> Array[ArrayMesh]:
	var fill := PackedVector3Array()
	var edge := PackedVector3Array()
	var half := deg_to_rad(def.arc_degrees) / 2.0
	var steps := 48
	var reach := def.reach + SimPlayer.RADIUS
	var width := 0.12
	var origin := Vector3(0, 0, -def.offset)
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		var d0 := Vector3(sin(a0), 0, -cos(a0))
		var d1 := Vector3(sin(a1), 0, -cos(a1))
		fill.append_array([origin, origin + d0 * reach, origin + d1 * reach])
		_quad(
			edge,
			origin + d0 * (reach - width),
			origin + d0 * reach,
			origin + d1 * reach,
			origin + d1 * (reach - width)
		)
	if def.arc_degrees < 359.0:
		for side in [-half, half]:
			var d := Vector3(sin(side), 0, -cos(side))
			var across := d.cross(Vector3.UP) * width * 0.5
			_quad(
				edge,
				origin - across,
				origin + across,
				origin + d * reach + across,
				origin + d * reach - across
			)
	return [_mesh(fill), _mesh(edge)]


static func _quad(
	points: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3
) -> void:
	points.append_array([a, b, c, a, c, d])


static func _mesh(points: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
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
	_edge_material.albedo_color.a = 0.0
	if def.melee():
		if not _arcs.has(def.resource_path):
			_arcs[def.resource_path] = _arc_meshes(def)
		_arc.mesh = _arcs[def.resource_path][0]
		_edge.mesh = _arcs[def.resource_path][1]
	if _clips == DRONE_CLIPS and enemy.action != Enemy.Action.DOWN:
		_model.lift(DRONE_LIFT)
	match enemy.action:
		Enemy.Action.WINDUP:
			var progress := time / windup
			_model.play_timed(def.animation, time / total, seconds)
			_model.glow(Color(TELEGRAPH, 0.1 + 0.3 * progress))
			# Visible from the first windup tick, filling in toward the hit.
			if def.melee():
				_arc_material.albedo_color = Color(TELEGRAPH, 0.2 + 0.4 * progress)
				_edge_material.albedo_color = Color(
					TELEGRAPH.lightened(0.3), 0.75 + 0.25 * progress
				)
		Enemy.Action.STRIKE:
			_model.play_timed(def.animation, (windup + time) / total, seconds)
			_model.glow(Color(1, 0.2, 0.1, 0.45))
			if def.melee():
				_arc_material.albedo_color = Color(1, 0.2, 0.1, 0.65)
				_edge_material.albedo_color = Color(1, 0.35, 0.2, 1.0)
		Enemy.Action.RECOVER:
			_model.play_timed(def.animation, (windup + active + time) / total, seconds)
			_model.glow(Color(0, 0, 0, 0))
		Enemy.Action.STAGGER:
			var ticks := Combat.ticks(enemy.stagger_time)
			_model.play_timed(_clips["hit"], time / ticks, enemy.stagger_time)
		Enemy.Action.DOWN:
			var down: float = _clips["down_time"]
			var fallen := time / Combat.ticks(down)
			_model.play_timed(_clips["down"], fallen, down)
			if _clips == DRONE_CLIPS:
				_model.lift(lerpf(DRONE_LIFT, 0.45, clampf(fallen, 0.0, 1.0)))
		Enemy.Action.RISE:
			var rise := Combat.ticks(Warden.RISE_TIME)
			_model.play_timed(_clips["down"], time / rise, Warden.RISE_TIME, true)
		_:
			_idle_or_walk()


func _idle_or_walk() -> void:
	_model.glow(Color(0, 0, 0, 0))
	var moving := enemy.velocity - enemy.up() * enemy.velocity.dot(enemy.up())
	var speed := moving.length()
	if speed > WALKING:
		_model.loop(_clips["walk"], speed / 2.0)
	else:
		_model.loop(_clips["idle"])


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
