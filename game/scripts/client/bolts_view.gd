class_name BoltsView
extends Node3D
## Bolts in flight (PLAN §4.5), a player's or an enemy's: glowing plasma darts with a particle
## trail, drawn from the shooter's bolt state (bolt_pos, bolt_vel, bolt_life) and moved on
## between ticks along their velocity, with a burst where one ends.

const PLAYER_COLOR := Color(0.2, 0.9, 1.0)
const ENEMY_COLOR := Color(1.0, 0.25, 0.12)

## A SimPlayer or an Enemy: anything with the three bolt arrays.
var shooter: Node3D
var color := PLAYER_COLOR
var _darts: Array[Node3D] = []
var _was_flying := PackedInt32Array()


func _init(of: Node3D, tint := PLAYER_COLOR) -> void:
	shooter = of
	color = tint
	name = "Bolts"
	top_level = true


func _ready() -> void:
	for i in (shooter.get("bolt_life") as PackedInt32Array).size():
		_darts.append(_make_dart())
		_was_flying.append(0)


func _make_dart() -> Node3D:
	var root := Node3D.new()
	root.visible = false
	var core := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.07
	capsule.height = 1.1
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color.lightened(0.5)
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 6.0
	capsule.material = glow
	core.mesh = capsule
	core.rotation.x = PI / 2.0
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var trail := GPUParticles3D.new()
	trail.name = "Trail"
	trail.amount = 40
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.emitting = false
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.3
	process.scale_min = 0.6
	process.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(color.lightened(0.3), 0.9))
	fade.set_color(1, Color(color.darkened(0.5), 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	trail.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var mote := StandardMaterial3D.new()
	mote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mote.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.vertex_color_use_as_albedo = true
	mote.emission_enabled = true
	mote.emission = color
	mote.emission_energy_multiplier = 3.0
	quad.material = mote
	trail.draw_pass_1 = quad
	root.add_child(trail)
	add_child(root)
	return root


func _process(_delta: float) -> void:
	var ahead := NetworkTime.tick_factor * NetworkTime.ticktime
	var life: PackedInt32Array = shooter.get("bolt_life")
	var positions: PackedVector3Array = shooter.get("bolt_pos")
	var velocities: PackedVector3Array = shooter.get("bolt_vel")
	for i in _darts.size():
		var dart := _darts[i]
		var flying := life[i] > 0
		if flying:
			var velocity := velocities[i]
			var at := positions[i] + velocity * ahead
			var axis_up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
			dart.global_transform = Transform3D(Basis.looking_at(velocity, axis_up), at)
		elif _was_flying[i] > 0:
			_burst(positions[i])
		dart.visible = flying
		(dart.get_node("Trail") as GPUParticles3D).emitting = flying
		_was_flying[i] = life[i]


func _burst(at: Vector3) -> void:
	var sparks := GPUParticles3D.new()
	sparks.one_shot = true
	sparks.amount = 24
	sparks.lifetime = 0.4
	sparks.explosiveness = 1.0
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 6.0
	process.gravity = Vector3(0, -6, 0)
	sparks.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var mote := StandardMaterial3D.new()
	mote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mote.albedo_color = color.lightened(0.5)
	mote.emission_enabled = true
	mote.emission = color
	mote.emission_energy_multiplier = 5.0
	quad.material = mote
	sparks.draw_pass_1 = quad
	add_child(sparks)
	sparks.global_position = at
	sparks.emitting = true
	get_tree().create_timer(1.0).timeout.connect(sparks.queue_free)
