class_name Arena
extends Node3D
## The two planets (PLAN §4.4, §6 M12): the realm at the origin (the encounter, gravity zones,
## the asteroid) and the hub keep on a plateau of a small planet far above it (Layout.HUB).
## Collision on both sides, meshes, lights and sky only on clients. Built in code so server and
## client always get the same collision. Surfaces are tiling PBR materials mapped world
## triplanar (ambientCG ground and rock, the Medieval Village MegaKit's brick), dressing comes
## from the Quaternius MegaKits (CC0). Clients show one planet at a time (show_planet).

const SIZE := 160.0
const AMBIENTCG := "res://assets/ambientcg/"
const VILLAGE := "res://assets/quaternius/village/"
const PROPS := "res://assets/quaternius/props/"
## Surfaces: an ambientCG set name, or "village:<name>" for a MegaKit texture set.
const GROUND := "Ground020"
const COBBLE := "PavingStones049"
const BRICK := "village:UnevenBrick"
const ROCK := "Rock030"
const ASTEROID := "Rock035"
const TORCH_LIGHT := Color(1.0, 0.62, 0.32)
const MOON_LIGHT := Color(0.62, 0.7, 0.92)

## Clients: which planet is drawn (show_planet), for views to hide what is on the other one.
static var shown_hub := true

var visual := false
## Clients only: what Graphics presets adjust.
var environment: Environment
var sun: DirectionalLight3D
## Every node of each planet, so clients can show one (collision lives here too; hiding a node
## doesn't change physics).
var realm: Node3D
var hub: Node3D
## Materials by name and tint, shared by every box that uses them.
var _materials := {}
## Torch lights; each flickers with its own phase.
var _torches: Array[OmniLight3D] = []
## The portal that opens where the Warden fell (shown once Encounter.won()).
var _victory_portal: Node3D


func _init(with_visuals: bool) -> void:
	visual = with_visuals
	name = "Arena"


func _ready() -> void:
	realm = Node3D.new()
	realm.name = "Realm"
	add_child(realm)
	hub = Node3D.new()
	hub.name = "Hub"
	add_child(hub)
	_build_realm()
	_build_hub()
	if visual:
		_add_environment()
		for portal in Layout.portals():
			var gate := _portal(portal)
			if portal.needs_victory:
				_victory_portal = gate
				gate.visible = false


## Clients: shows the hub or the realm (only one planet is drawn at a time).
func show_planet(on_hub: bool) -> void:
	shown_hub = on_hub
	hub.visible = on_hub
	realm.visible = not on_hub


## Clients: whether something at point is on the planet being drawn.
static func shows(point: Vector3) -> bool:
	return Layout.on_hub(point) == shown_hub


func _process(_delta: float) -> void:
	if not visual:
		return
	var seconds := Time.get_ticks_msec() / 1000.0
	for i in _torches.size():
		var light := _torches[i]
		light.light_energy = (
			2.2 + 0.25 * sin(seconds * 9.0 + i * 1.7) + 0.15 * sin(seconds * 23.0 + i)
		)
	if _victory_portal:
		_victory_portal.visible = Encounter.won(self)


# --- The realm -----------------------------------------------------------------------------


func _build_realm() -> void:
	_box(realm, Vector3(0, -0.5, 0), Vector3(SIZE, 1, SIZE), GROUND, Vector3.ZERO, 0.25)
	# Broken stone blocks to walk around and jump on.
	for i in 8:
		var angle := TAU * i / 8.0
		var at := Vector3(cos(angle), 0, sin(angle)) * 18.0
		var height := 1.0 + (i % 3) * 0.8
		_box(realm, at + Vector3(0, height / 2.0, 0), Vector3(3, height, 3), BRICK)
	# A ramp and a stair to test slopes and steps.
	_box(realm, Vector3(-8, 1.2, -30), Vector3(4, 0.4, 10), ROCK, Vector3(deg_to_rad(15), 0, 0))
	for s in 6:
		_box(realm, Vector3(8, 0.2 + s * 0.2, -26 - s * 0.8), Vector3(4, 0.4 + s * 0.4, 0.8), BRICK)
	# The barrow wall behind the encounter.
	_box(realm, Vector3(0, 3, 45), Vector3(40, 6, 1), BRICK)
	# Grave slabs beside the fight, out of the mobs' way.
	for i in 10:
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * (22.0 + (i % 3) * 2.5), 0.6, 30.0 + (i / 2) * 2.2)
		_box(realm, at, Vector3(1.2, 1.4, 0.3), ROCK, Vector3(0.12 * side, 0.2 * i, 0))
	_add_asteroid()
	if visual:
		for i in 5:
			_torch(realm, Vector3(-16 + i * 8, 3.2, 44.5), Vector3.FORWARD, i == 2)
		_prop(realm, VILLAGE + "Prop_Wagon.gltf", Vector3(-15, 0, -12), 0.6)
		_prop(realm, PROPS + "Barrel.gltf", Vector3(-13, 0, -14.5))
		_prop(realm, PROPS + "Crate_Wooden.gltf", Vector3(-12, 0, -15.5), 0.4)
		_prop(realm, PROPS + "Banner_2.gltf", Vector3(-6, 5.2, 44.38), PI)
		_prop(realm, PROPS + "Banner_2.gltf", Vector3(6, 5.2, 44.38), PI)
		_prop(realm, PROPS + "Chain_Coil.gltf", Vector3(3, 0, 40))
		_add_zone_visuals()
		_add_pads()


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
		body.add_child(_sphere_mesh(Layout.ASTEROID_RADIUS, ASTEROID, 0.12))
	realm.add_child(body)
	# Boulders around the equator and near the top, leaving the bottom pole (return pad) free.
	for i in 7:
		var normal := Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(40 + i * 20)).rotated(
			Vector3.UP, i * 2.1
		)
		var size := Vector3(2.5, 1.6 + (i % 3) * 0.6, 2.5)
		var at := Layout.ASTEROID_CENTER + normal * (Layout.ASTEROID_RADIUS + size.y / 2.0 - 0.3)
		var basis := SimPlayer.frame(normal, SimPlayer._tangent(Vector3.FORWARD, normal))
		_box(realm, at, size, ROCK, basis.get_euler())


# --- The hub -------------------------------------------------------------------------------


## The keep: a cobbled yard inside high brick walls with corner towers, the hall to the north,
## the gate portal to the south, a training corner with the dummies, a smithy corner.
func _build_hub() -> void:
	var yard := Layout.HUB_YARD
	var wall := Layout.HUB_WALL
	var half := Vector3(yard.x / 2.0, 0, yard.y / 2.0)
	_box(hub, _h(0, -0.5, 0), Vector3(yard.x + 4, 1, yard.y + 4), COBBLE, Vector3.ZERO, 0.3)
	_box(hub, _h(0, -8, 0), Vector3(yard.x + 12, 14, yard.y + 12), ROCK, Vector3.ZERO, 0.1)
	var thick := 1.2
	for side: float in [-1.0, 1.0]:
		var z := side * (half.z + thick / 2.0)
		_box(hub, _h(0, wall / 2.0, z), Vector3(yard.x + 2 * thick, wall, thick), BRICK)
		var x := side * (half.x + thick / 2.0)
		_box(hub, _h(x, wall / 2.0, 0), Vector3(thick, wall, yard.y), BRICK)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var at := _h(corner.x * (half.x + 0.6), 5.5, corner.y * (half.z + 0.6))
		_box(hub, at, Vector3(4.5, 11, 4.5), BRICK)
		if visual:
			_prop(hub, VILLAGE + "Roof_Tower_RoundTiles.gltf", at + Vector3(0, 6.0, 0), 0.0, 0.9)
	# The hall along the north wall.
	_box(hub, _h(0, 4.5, -half.z + 3.5), Vector3(22, 9, 7), BRICK)
	if not visual:
		return
	hub.add_child(_sphere_mesh(Layout.HUB_PLANET_RADIUS, ASTEROID, 0.05, _h(0, -64, 0)))
	_prop(hub, VILLAGE + "DoorFrame_Round_Brick.gltf", _h(0, 0, -half.z + 7.02), 0.0, 1.3)
	for x: float in [-7.0, 7.0]:
		_window(_h(x, 4.6, -half.z + 7.05))
		_torch(hub, _h(x * 0.42, 2.6, -half.z + 7.05), Vector3.BACK, true)
	for i in 4:
		var z := -12.0 + i * 8.0
		_torch(hub, _h(-half.x + 0.05, 3.2, z), Vector3.RIGHT, false)
		_torch(hub, _h(half.x - 0.05, 3.2, z), Vector3.LEFT, false)
	for x: float in [-4.0, 4.0]:
		_torch(hub, _h(x, 3.2, half.z - 0.05), Vector3.FORWARD, false)
		_prop(hub, PROPS + "Banner_1.gltf", _h(x * 2.5, wall - 1.2, half.z - 0.12), PI)
	for x: float in [-9.0, 9.0]:
		_prop(hub, PROPS + "Banner_2.gltf", _h(x, 7.6, -half.z + 7.12))
	# Training corner (the dummies stand at Layout.DUMMIES) and the smithy.
	_prop(hub, PROPS + "WeaponStand.gltf", _h(-10, 0, -12), PI / 2.0)
	_prop(hub, PROPS + "Barrel.gltf", _h(-17.5, 0, -13))
	_prop(hub, PROPS + "Barrel.gltf", _h(-17, 0, -11.6))
	_prop(hub, PROPS + "Crate_Wooden.gltf", _h(-17.6, 0, 6), 0.3)
	_prop(hub, PROPS + "Anvil.gltf", _h(11, 0, -10), 0.4)
	_prop(hub, PROPS + "Cauldron.gltf", _h(15, 0, -6))
	_prop(hub, PROPS + "Chest_Wood.gltf", _h(13, 0, -13.5))
	_prop(hub, PROPS + "Crate_Wooden.gltf", _h(17.5, 0, 10), -0.2)
	_prop(hub, PROPS + "Barrel.gltf", _h(16.8, 0, 12))
	for i in 6:
		var vine: String = ["Prop_Vine1", "Prop_Vine2", "Prop_Vine4"][i % 3]
		var x := -half.x + 0.02 if i < 3 else half.x - 0.02
		_prop(
			hub, VILLAGE + vine + ".gltf", _h(x, wall - 0.5, -6 + (i % 3) * 9), PI / 2.0 * signf(-x)
		)


## A point relative to the keep's yard center.
static func _h(x: float, y: float, z: float) -> Vector3:
	return Layout.HUB + Vector3(x, y, z)


# --- Pieces --------------------------------------------------------------------------------


func _box(
	parent: Node3D,
	at: Vector3,
	size: Vector3,
	surface: String,
	rotation_euler := Vector3.ZERO,
	tiles := 0.5
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
	parent.add_child(body)


func _sphere_mesh(
	radius: float, surface: String, tiles: float, at := Vector3.ZERO
) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	sphere.material = _surface(surface, tiles)
	mesh.mesh = sphere
	mesh.position = at
	return mesh


## A model from a MegaKit, turned by yaw around up and scaled; visual only.
func _prop(parent: Node3D, path: String, at: Vector3, yaw := 0.0, scale_by := 1.0) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.position = at
	node.rotation.y = yaw
	node.scale = Vector3.ONE * scale_by
	parent.add_child(node)
	return node


## A wall torch: the MegaKit's iron torch with a flame and a flickering warm light, mounted on
## a wall whose face looks along out.
func _torch(parent: Node3D, at: Vector3, out: Vector3, shadows: bool) -> void:
	var root := Node3D.new()
	root.position = at
	# The model's plate is at its origin and it reaches out along +Z.
	root.basis = Basis.looking_at(-out, Vector3.UP)
	parent.add_child(root)
	root.add_child(_model(PROPS + "Torch_Metal.gltf"))
	var flame := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = 0.07
	shape.height = 0.22
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0, 0.55, 0.2)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.5, 0.15)
	fire.emission_energy_multiplier = 8.0
	shape.material = fire
	flame.mesh = shape
	flame.position = Vector3(0, 0.45, 0.3)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = TORCH_LIGHT
	light.omni_range = 11.0
	light.omni_attenuation = 1.4
	light.position = Vector3(0, 0.6, 0.55)
	light.shadow_enabled = shadows
	root.add_child(light)
	_torches.append(light)
	Sounds.loop(root, &"torch", -14.0, 10.0)


## A lit window in the hall: a warm glowing pane and an area light (Godot 4.7 AreaLight3D)
## spilling into the yard.
func _window(at: Vector3) -> void:
	var pane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.8)
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(0.5, 0.25, 0.08)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.5, 0.18)
	glass.emission_energy_multiplier = 1.2
	quad.material = glass
	pane.mesh = quad
	pane.position = at
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hub.add_child(pane)
	var light := AreaLight3D.new()
	light.area_size = Vector2(1.2, 1.8)
	light.area_range = 14.0
	light.light_color = Color(1.0, 0.66, 0.38)
	light.light_energy = 4.0
	light.position = at + Vector3(0, 0, 0.05)
	# An area light shines along its -Z; turn it to face the yard (+Z).
	light.rotation.y = PI
	hub.add_child(light)


## A standing stone gate with a swirling veil, a light and its name; the planet it stands on
## owns it.
func _portal(portal: Portal) -> Node3D:
	var root := Node3D.new()
	root.position = portal.position
	(hub if Layout.on_hub(portal.position) else realm).add_child(root)
	var stone := _surface(BRICK, 0.6)
	for x: float in [-1.7, 1.7]:
		root.add_child(_block(Vector3(0.6, 4.0, 0.7), Vector3(x, 2.0, 0), stone))
	root.add_child(_block(Vector3(4.2, 0.7, 0.8), Vector3(0, 4.3, 0), stone))
	var veil := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.8, 3.9)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/portal.gdshader")
	var tint := Color(0.95, 0.75, 0.4) if portal.needs_victory else Color(0.45, 0.7, 1.0)
	material.set_shader_parameter("tint", tint)
	quad.material = material
	veil.mesh = quad
	veil.position.y = 2.0
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(veil)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 2.0
	light.omni_range = 8.0
	light.position.y = 2.0
	root.add_child(light)
	Sounds.loop(root, &"portal", -8.0, 14.0)
	var label := Label3D.new()
	label.text = portal.label
	label.font = load(Menus.TITLE_FONT)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 5.2
	label.pixel_size = 0.006
	label.font_size = 44
	label.outline_size = 10
	root.add_child(label)
	return root


func _block(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = at
	return mesh


func _model(path: String) -> Node3D:
	return (load(path) as PackedScene).instantiate() as Node3D


## A tiling PBR material, triplanar at scale tiles per meter: an ambientCG set from
## assets/ambientcg/<name>/ (Color, NormalGL, Roughness, AmbientOcclusion where present) or a
## MegaKit set (village:<name> → T_<name>_BaseColor/Normal/Roughness).
func _surface(surface: String, scale_by := 0.25) -> StandardMaterial3D:
	var key := "%s@%s" % [surface, scale_by]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.normal_enabled = true
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	if surface.begins_with("village:"):
		var base := VILLAGE + "T_" + surface.trim_prefix("village:")
		material.albedo_texture = load(base + "_BaseColor.png")
		material.normal_texture = load(base + "_Normal.png")
		material.roughness_texture = load(base + "_Roughness.png")
		# Worn and darker than the kit's sunny village.
		material.albedo_color = Color(0.75, 0.72, 0.7)
	else:
		var dir := AMBIENTCG + surface + "/"
		material.albedo_texture = load(dir + "Color.jpg")
		material.normal_texture = load(dir + "NormalGL.jpg")
		material.roughness_texture = load(dir + "Roughness.jpg")
		if ResourceLoader.exists(dir + "AmbientOcclusion.jpg"):
			material.ao_enabled = true
			material.ao_texture = load(dir + "AmbientOcclusion.jpg")
			material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		if surface == GROUND:
			material.albedo_color = Color(0.55, 0.58, 0.5)
		elif surface == COBBLE:
			material.albedo_color = Color(0.7, 0.7, 0.72)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * scale_by
	_materials[key] = material
	return material


## Moonlight, the night sky with its moon, and post-processing (PLAN §3.1, §3.2).
func _add_environment() -> void:
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(deg_to_rad(-38), deg_to_rad(30), 0)
	moon.light_color = MOON_LIGHT
	moon.light_energy = 1.4
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 140.0
	add_child(moon)

	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://shaders/space_sky.gdshader")
	sky_material.set_shader_parameter("nebula_warm", Color(0.1, 0.06, 0.1))
	sky_material.set_shader_parameter("nebula_cold", Color(0.03, 0.04, 0.09))
	sky_material.set_shader_parameter("horizon_glow", Color(0.2, 0.14, 0.16))
	sky_material.set_shader_parameter("planet_size", 0.2)
	sky_material.set_shader_parameter("planet_light", Color(0.78, 0.74, 0.66))
	sky_material.set_shader_parameter("planet_dark", Color(0.5, 0.46, 0.42))
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# The night sky is mostly black, so ambient light comes from a fixed color instead.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Bright enough that shadowed sides still read (the 2026-11-10 play-test found it far too dark).
	env.ambient_light_color = Color(0.42, 0.45, 0.58)
	env.ambient_light_energy = 1.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.ssao_enabled = true
	env.ssao_intensity = 1.2
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_bloom = 0.06
	# Muted: grim, not cute. Barely any extra contrast, which crushed the shadows to black.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.02
	env.adjustment_saturation = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.1, 0.14)
	env.fog_density = 0.007
	env.fog_sky_affect = 0.0
	# Only the zones' FogVolumes add volumetric fog.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_emission_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	environment = env
	sun = moon
	add_child(world_env)


## Gravity zones are tinted mist with drifting motes and a glowing rune line on the ground: pale
## blue and rising where the realm's pull is weak, ember red and falling where it is strong.
func _add_zone_visuals() -> void:
	_zone_look(Layout.LOW_G_CENTER, Layout.LOW_G_SIZE, Color(0.45, 0.7, 1.0), 2.0)
	_zone_look(Layout.HIGH_G_CENTER, Layout.HIGH_G_SIZE, Color(1.0, 0.4, 0.2), -25.0)


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
	realm.add_child(fog)

	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 2.0
	var floor_y := center.y - size.y / 2.0 + 0.03
	for side in 4:
		var along_x := side < 2
		var length := size.x if along_x else size.z
		var offset := (size.z if along_x else size.x) / 2.0 * (1 if side % 2 == 0 else -1)
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(length, 0.04, 0.12) if along_x else Vector3(0.12, 0.04, length)
		box.material = glow
		strip.mesh = box
		strip.position = Vector3(
			center.x + (0.0 if along_x else offset),
			floor_y,
			center.z + (offset if along_x else 0.0)
		)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		realm.add_child(strip)

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
	realm.add_child(motes)


## A rune stone disc with a light, lying on its surface.
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
		material.albedo_color = Color(0.25, 0.6, 0.75)
		material.emission_enabled = true
		material.emission = Color(0.3, 0.75, 0.95)
		material.emission_energy_multiplier = 1.8
		cylinder.material = material
		disc.mesh = cylinder
		disc.position.y = 0.04
		root.add_child(disc)
		var light := OmniLight3D.new()
		light.light_color = Color(0.4, 0.8, 1.0)
		light.light_energy = 1.6
		light.omni_range = 6.0
		light.position.y = 1.0
		root.add_child(light)
		var label := Label3D.new()
		label.text = "Leap: Space"
		label.font = load(Menus.TITLE_FONT)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 2.6
		label.pixel_size = 0.006
		label.font_size = 40
		label.outline_size = 10
		root.add_child(label)
		realm.add_child(root)
