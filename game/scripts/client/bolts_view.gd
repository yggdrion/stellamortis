class_name BoltsView
extends Node3D
## A player's bolts in flight (PLAN §4.5): glowing plasma darts with a particle trail, drawn
## from the player's bolt state and moved on between ticks along their velocity, with a burst
## where one ends.

var player: SimPlayer
var _darts: Array[Node3D] = []
var _was_flying := PackedInt32Array()


func _init(of: SimPlayer) -> void:
	player = of
	name = "Bolts"
	top_level = true


func _ready() -> void:
	for i in SimPlayer.MAX_BOLTS:
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
	glow.albedo_color = Color(0.6, 1.0, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.2, 0.9, 1.0)
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
	fade.set_color(0, Color(0.4, 1.0, 1.0, 0.9))
	fade.set_color(1, Color(0.1, 0.4, 1.0, 0.0))
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
	mote.emission = Color(0.2, 0.8, 1.0)
	mote.emission_energy_multiplier = 3.0
	quad.material = mote
	trail.draw_pass_1 = quad
	root.add_child(trail)
	add_child(root)
	return root


func _process(_delta: float) -> void:
	var ahead := NetworkTime.tick_factor * NetworkTime.ticktime
	for i in SimPlayer.MAX_BOLTS:
		var dart := _darts[i]
		var flying := player.bolt_life[i] > 0
		if flying:
			var velocity := player.bolt_vel[i]
			var at := player.bolt_pos[i] + velocity * ahead
			var axis_up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
			dart.global_transform = Transform3D(Basis.looking_at(velocity, axis_up), at)
		elif _was_flying[i] > 0:
			_burst(player.bolt_pos[i])
		dart.visible = flying
		(dart.get_node("Trail") as GPUParticles3D).emitting = flying
		_was_flying[i] = player.bolt_life[i]


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
	mote.albedo_color = Color(0.5, 1.0, 1.0)
	mote.emission_enabled = true
	mote.emission = Color(0.3, 0.9, 1.0)
	mote.emission_energy_multiplier = 5.0
	quad.material = mote
	sparks.draw_pass_1 = quad
	add_child(sparks)
	sparks.global_position = at
	sparks.emitting = true
	get_tree().create_timer(1.0).timeout.connect(sparks.queue_free)
