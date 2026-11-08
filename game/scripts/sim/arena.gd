class_name Arena
extends Node3D
## The PoC arena (PLAN §4.4): collision on both sides, meshes, light and sky only on clients.
## Built in code so server and client always get the same collision.

const SIZE := 160.0

var visual := false


func _init(with_visuals: bool) -> void:
	visual = with_visuals
	name = "Arena"


func _ready() -> void:
	var ground := Color(0.36, 0.33, 0.38)
	var rock := Color(0.48, 0.42, 0.40)
	var metal := Color(0.55, 0.58, 0.62)
	_box(Vector3(0, -0.5, 0), Vector3(SIZE, 1, SIZE), ground, 0.95)
	# Blocks to walk around and jump on.
	for i in 8:
		var angle := TAU * i / 8.0
		var at := Vector3(cos(angle), 0, sin(angle)) * 18.0
		var height := 1.0 + (i % 3) * 0.8
		_box(at + Vector3(0, height / 2.0, 0), Vector3(3, height, 3), rock, 0.8)
	# A ramp and a stair to test slopes and steps.
	_box(Vector3(-8, 1.2, -30), Vector3(4, 0.4, 10), metal, 0.4, Vector3(deg_to_rad(15), 0, 0))
	for s in 6:
		_box(Vector3(8, 0.2 + s * 0.2, -26 - s * 0.8), Vector3(4, 0.4 + s * 0.4, 0.8), metal, 0.4)
	# A wall at the edge.
	_box(Vector3(0, 3, 45), Vector3(40, 6, 1), metal, 0.5)
	if visual:
		_add_environment()


func _box(
	at: Vector3, size: Vector3, color: Color, roughness: float, rotation_euler := Vector3.ZERO
) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = SimPlayer.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	body.rotation = rotation_euler
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if visual:
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = size
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		material.metallic = 0.6 if roughness < 0.6 else 0.0
		material.uv1_triplanar = true
		cube.material = material
		mesh.mesh = cube
		body.add_child(mesh)
	add_child(body)


## Sun, sky and post-processing (PLAN §3.1). An alien dusk until M1 brings the space sky.
func _add_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(30), 0)
	sun.light_color = Color(1.0, 0.92, 0.85)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.05, 0.05, 0.15)
	sky_material.sky_horizon_color = Color(0.55, 0.35, 0.45)
	sky_material.ground_horizon_color = Color(0.3, 0.2, 0.25)
	sky_material.ground_bottom_color = Color(0.05, 0.04, 0.06)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssil_enabled = true
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.32, 0.42)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
