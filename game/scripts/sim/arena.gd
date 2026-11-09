class_name Arena
extends Node3D
## The PoC arena (PLAN §4.4): collision on both sides, meshes, light and sky only on clients.
## Built in code so server and client always get the same collision. Surfaces are tiling PBR
## materials from ambientCG (CC0) mapped triplanar, so any box size works.

const SIZE := 160.0
const MATERIALS := "res://assets/ambientcg/"
const FLOOR := "DiamondPlate008C"
const PANELS := "MetalPlates013"
const PLATES := "MetalPlates006"
const ROCK := "Rock030"
const ASTEROID := "Rock035"

var visual := false
## Clients only: what Graphics presets adjust.
var environment: Environment
var sun: DirectionalLight3D
## Materials by name and tint, shared by every box that uses them.
var _materials := {}


func _init(with_visuals: bool) -> void:
	visual = with_visuals
	name = "Arena"


func _ready() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(SIZE, 1, SIZE), FLOOR, Vector3.ZERO, 0.5)
	# Blocks to walk around and jump on.
	for i in 8:
		var angle := TAU * i / 8.0
		var at := Vector3(cos(angle), 0, sin(angle)) * 18.0
		var height := 1.0 + (i % 3) * 0.8
		_box(at + Vector3(0, height / 2.0, 0), Vector3(3, height, 3), PANELS)
	# A ramp and a stair to test slopes and steps.
	_box(Vector3(-8, 1.2, -30), Vector3(4, 0.4, 10), PLATES, Vector3(deg_to_rad(15), 0, 0))
	for s in 6:
		_box(Vector3(8, 0.2 + s * 0.2, -26 - s * 0.8), Vector3(4, 0.4 + s * 0.4, 0.8), PLATES)
	# A wall at the edge.
	_box(Vector3(0, 3, 45), Vector3(40, 6, 1), PANELS)
	_add_asteroid()
	if visual:
		_add_floodlights()
		_add_environment()
		_add_zone_visuals()
		_add_pads()


func _box(
	at: Vector3, size: Vector3, surface: String, rotation_euler := Vector3.ZERO, tiles := 0.5
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
		cube.material = _surface(surface, tiles)
		mesh.mesh = cube
		body.add_child(mesh)
	add_child(body)


## The asteroid: a sphere with boulders to walk around, standing on its surface.
func _add_asteroid() -> void:
	var body := StaticBody3D.new()
	body.name = "Asteroid"
	body.collision_layer = SimPlayer.LAYER_WORLD
	body.collision_mask = 0
	body.position = Layout.ASTEROID_CENTER
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = Layout.ASTEROID_RADIUS
	shape.shape = sphere
	body.add_child(shape)
	if visual:
		body.add_child(_asteroid_mesh())
	add_child(body)
	# Boulders around the equator and near the top, leaving the bottom pole (return pad) free.
	for i in 7:
		var normal := Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(40 + i * 20)).rotated(
			Vector3.UP, i * 2.1
		)
		var size := Vector3(2.5, 1.6 + (i % 3) * 0.6, 2.5)
		var at := Layout.ASTEROID_CENTER + normal * (Layout.ASTEROID_RADIUS + size.y / 2.0 - 0.3)
		var basis := SimPlayer.frame(normal, SimPlayer._tangent(Vector3.FORWARD, normal))
		_box(at, size, ROCK, basis.get_euler())


func _asteroid_mesh() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = Layout.ASTEROID_RADIUS
	sphere.height = Layout.ASTEROID_RADIUS * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	sphere.material = _surface(ASTEROID, 0.12)
	mesh.mesh = sphere
	return mesh


## A tiling PBR material from assets/ambientcg/<name>/ (Color, NormalGL, Roughness and, where the
## set has them, Metalness and AmbientOcclusion), triplanar at scale tiles per meter.
func _surface(surface: String, scale_by := 0.25) -> StandardMaterial3D:
	var key := "%s@%s" % [surface, scale_by]
	if _materials.has(key):
		return _materials[key]
	var dir := MATERIALS + surface + "/"
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(dir + "Color.jpg")
	material.normal_enabled = true
	material.normal_texture = load(dir + "NormalGL.jpg")
	material.roughness_texture = load(dir + "Roughness.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	if ResourceLoader.exists(dir + "Metalness.jpg"):
		# Full metal mirrors the black sky and goes black; half keeps the plates readable.
		material.metallic = 0.45
		material.metallic_texture = load(dir + "Metalness.jpg")
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	if ResourceLoader.exists(dir + "AmbientOcclusion.jpg"):
		material.ao_enabled = true
		material.ao_texture = load(dir + "AmbientOcclusion.jpg")
		material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * scale_by
	if surface == FLOOR:
		# The tread plate is bright bare steel; dark painted deck reads better under the sky.
		material.albedo_color = Color(0.3, 0.32, 0.35)
	_materials[key] = material
	return material


## Sun, space sky and post-processing (PLAN §3.1).
func _add_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(30), 0)
	sun.light_color = Color(0.86, 0.92, 1.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)

	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://shaders/space_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# The sky is mostly black, so ambient light comes from a fixed color instead.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.48)
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_bloom = 0.05
	# Slightly cold, slightly crushed: a grim, low key grade.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.82
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.13, 0.17)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	# Only the zones' FogVolumes add volumetric fog.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_emission_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	environment = env
	self.sun = sun
	add_child(world_env)


## Floodlights along the long wall: cold lamps with a glowing strip on top, so the encounter
## side has its own light against the dark.
func _add_floodlights() -> void:
	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color(0.1, 0.12, 0.14)
	strip.emission_enabled = true
	strip.emission = Color(0.75, 0.88, 1.0)
	strip.emission_energy_multiplier = 3.0
	var top := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(40, 0.12, 0.2)
	bar.material = strip
	top.mesh = bar
	top.position = Vector3(0, 6.05, 44.4)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(top)
	for i in 5:
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(-16 + i * 8, 5.6, 44.2)
		lamp.rotation = Vector3(deg_to_rad(-50), PI, 0)
		lamp.light_color = Color(0.8, 0.9, 1.0)
		lamp.light_energy = 6.0
		lamp.spot_range = 24.0
		lamp.spot_angle = 50.0
		lamp.shadow_enabled = i % 2 == 0
		add_child(lamp)


## Gravity zones are tinted fog with drifting motes and a glowing border on the ground: blue
## and rising in low gravity, red and falling in high gravity.
func _add_zone_visuals() -> void:
	_zone_look(Layout.LOW_G_CENTER, Layout.LOW_G_SIZE, Color(0.35, 0.75, 1.0), 2.0)
	_zone_look(Layout.HIGH_G_CENTER, Layout.HIGH_G_SIZE, Color(1.0, 0.35, 0.25), -25.0)


func _zone_look(center: Vector3, size: Vector3, color: Color, drift: float) -> void:
	var fog := FogVolume.new()
	fog.size = size
	fog.position = center
	var fog_material := FogMaterial.new()
	fog_material.density = 0.015
	fog_material.albedo = color
	fog_material.emission = color * 0.03
	fog_material.edge_fade = 0.3
	fog.material = fog_material
	add_child(fog)

	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 3.0
	var floor_y := center.y - size.y / 2.0 + 0.03
	for side in 4:
		var along_x := side < 2
		var length := size.x if along_x else size.z
		var offset := (size.z if along_x else size.x) / 2.0 * (1 if side % 2 == 0 else -1)
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(length, 0.06, 0.25) if along_x else Vector3(0.25, 0.06, length)
		box.material = glow
		strip.mesh = box
		strip.position = Vector3(
			center.x + (0.0 if along_x else offset),
			floor_y,
			center.z + (offset if along_x else 0.0)
		)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)

	var motes := GPUParticles3D.new()
	motes.amount = 300
	motes.lifetime = 6.0 if drift > 0 else 1.2
	motes.position = center
	motes.visibility_aabb = AABB(-size / 2.0, size)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = size / 2.0
	process.gravity = Vector3(0, drift, 0)
	process.direction = Vector3.UP if drift > 0 else Vector3.DOWN
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 1.0
	process.scale_min = 0.5
	process.scale_max = 1.0
	motes.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06) if drift > 0 else Vector2(0.03, 0.5)
	var mote_material := StandardMaterial3D.new()
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_material.billboard_mode = (
		BaseMaterial3D.BILLBOARD_PARTICLES if drift > 0 else BaseMaterial3D.BILLBOARD_FIXED_Y
	)
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_material.albedo_color = Color(color, 0.8)
	mote_material.emission_enabled = true
	mote_material.emission = color
	mote_material.emission_energy_multiplier = 4.0
	quad.material = mote_material
	motes.draw_pass_1 = quad
	add_child(motes)


## A glowing disc with a light, lying on its surface.
func _add_pads() -> void:
	for pad in Layout.jump_pads():
		var root := Node3D.new()
		root.basis = SimPlayer.frame(pad.normal, SimPlayer._tangent(Vector3.FORWARD, pad.normal))
		root.position = pad.position
		var disc := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = pad.radius
		cylinder.bottom_radius = pad.radius
		cylinder.height = 0.12
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.2, 0.9, 1.0)
		material.emission_enabled = true
		material.emission = Color(0.2, 0.9, 1.0)
		material.emission_energy_multiplier = 2.5
		cylinder.material = material
		disc.mesh = cylinder
		disc.position.y = 0.04
		root.add_child(disc)
		var light := OmniLight3D.new()
		light.light_color = Color(0.3, 0.9, 1.0)
		light.light_energy = 2.0
		light.omni_range = 6.0
		light.position.y = 1.0
		root.add_child(light)
		var label := Label3D.new()
		label.text = "Jump pad: Space"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 2.6
		label.pixel_size = 0.006
		label.font_size = 40
		label.outline_size = 10
		root.add_child(label)
		add_child(root)
