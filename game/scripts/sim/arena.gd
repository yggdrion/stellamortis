class_name Arena
extends Node3D
## A node for every generated realm (the Barrowlands, where players start; TerrainView fills it),
## the arrival's stones and the gates. Collision on both sides, meshes, lights and sky only on
## clients. Built in code so server and client always get the same collision. Surfaces are tiling
## PBR materials mapped world triplanar (ambientCG ground and rock, the Medieval Village MegaKit's
## brick), dressing comes from the Quaternius MegaKits (CC0). Clients show one place at a time
## (show_place).

const AMBIENTCG := "res://assets/ambientcg/"
const VILLAGE := "res://assets/quaternius/village/"
const PROPS := "res://assets/quaternius/props/"
## Surfaces: an ambientCG set name, or "village:<name>" for a MegaKit texture set.
const GROUND := "Ground020"
const BRICK := "village:UnevenBrick"
const ROCK := "Rock030"
const NATURE := "res://assets/kenney/nature/"
const STONE_COUNT := 10
const STONE_RING := 6.0
const STONE_SCALE := 2.4
## A ring stone's solid: the model (0.98 x 1.0 x 0.68 units) at STONE_SCALE, a little narrower.
const STONE_SOLID := Vector3(1.9, 2.3, 1.3)
## A gate's arch: pillar centers either side of the opening, pillar and lintel boxes, the lintel's
## height. Visual (_portal) and solid (_add_gate_solids) read the same numbers.
const GATE_PILLAR_X := 1.7
const GATE_PILLAR := Vector3(0.6, 4.0, 0.7)
const GATE_LINTEL := Vector3(4.2, 0.7, 0.8)
const GATE_LINTEL_Y := 4.3
const TORCH_LIGHT := Color(1.0, 0.62, 0.32)
const MOON_LIGHT := Color(0.62, 0.7, 0.92)
const MOON_ROTATION := Vector3(-38.0, 30.0, 0.0)
## Where the sky's banded moon-planet hangs when up is the world's up (the sky shader's default).
const PLANET_DIRECTION := Vector3(-0.45, 0.32, -0.83)
## How fast the moon follows a walker's local up on a round realm (per second, exponential).
const MOON_FOLLOW := 1.5

## Clients: which place is drawn (show_place), for views to hide what is in another one.
static var shown := StringName(Layout.start_realm().id)

var visual := false
## Clients only: what Graphics presets adjust.
var environment: Environment
var sun: DirectionalLight3D
## Place name (Layout.place_at) -> its node, one per generated realm, so clients can show one
## (collision lives here too; hiding a node doesn't change physics).
var places := {}
## Materials by name and tint, shared by every box that uses them.
var _materials := {}
## The sky shader: the moon-planet and horizon follow the walker (follow_up).
var _sky: ShaderMaterial
## Torch lights; each flickers with its own phase.
var _torches: Array[OmniLight3D] = []


func _init(with_visuals: bool) -> void:
	visual = with_visuals
	name = "Arena"


func _ready() -> void:
	for def in Layout.realms():
		var node := Node3D.new()
		node.name = def.id.capitalize()
		add_child(node)
		places[StringName(def.id)] = node
	if visual:
		_add_environment()


## Clients: the gates between realms and the arrival's look, once the world seed is known
## (World.build).
func add_seeded_portals() -> void:
	for portal in Layout.portals():
		_portal(portal)
	_arrival_look(Layout.start_realm())


## Every peer (M35): the arrival's ring stones and the gates' pillars and lintels are solid, from
## the same Layout positions the visuals use, so a client predicts against what the server has.
## Only the pillars and the lintel: the opening a player walks through stays free.
func add_arrival_solids() -> void:
	var start := Layout.start_realm()
	var parent := places[StringName(start.id)] as Node3D
	for stone in _arrival_stones(start):
		_solid(parent, stone, STONE_SOLID, Vector3(0, STONE_SOLID.y * 0.5, 0))
	for portal in Layout.portals():
		var gate := Transform3D(SimPlayer.frame(portal.up, Vector3.FORWARD), portal.position)
		var place := places[Layout.place_at(portal.position)] as Node3D
		for x: float in [-GATE_PILLAR_X, GATE_PILLAR_X]:
			_solid(place, gate, GATE_PILLAR, Vector3(x, GATE_PILLAR.y * 0.5, 0))
		_solid(place, gate, GATE_LINTEL, Vector3(0, GATE_LINTEL_Y, 0))


## A static box of a size at an offset (in the frame of `at`), on the world layer.
func _solid(parent: Node3D, at: Transform3D, size: Vector3, offset: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = SimPlayer.LAYER_WORLD
	body.collision_mask = 0
	body.transform = at * Transform3D(Basis.IDENTITY, offset)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


## Clients: the ground, shell and scatter of every generated realm (TerrainView), once the world
## seed is known.
func add_terrain_views(world_seed: int) -> void:
	for def in Layout.realms():
		(places[StringName(def.id)] as Node3D).add_child(TerrainView.new(def, world_seed))


## Clients: shows one place (only one is drawn at a time).
func show_place(place: StringName) -> void:
	shown = place
	for key: StringName in places:
		(places[key] as Node3D).visible = key == place


## Clients: whether something at point is in the place being drawn.
static func shows(point: Vector3) -> bool:
	return Layout.place_at(point) == shown


func _process(_delta: float) -> void:
	if not visual:
		return
	var seconds := Time.get_ticks_msec() / 1000.0
	for i in _torches.size():
		var light := _torches[i]
		light.light_energy = (
			2.2 + 0.25 * sin(seconds * 9.0 + i * 1.7) + 0.15 * sin(seconds * 23.0 + i)
		)


# --- Pieces --------------------------------------------------------------------------------


## A model from a MegaKit, oriented by a basis (SimPlayer.frame(up, forward) on a round ground)
## and scaled; visual only.
func _prop(
	parent: Node3D, path: String, at: Vector3, orientation := Basis.IDENTITY, scale_by := 1.0
) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.position = at
	node.basis = orientation.scaled(Vector3.ONE * scale_by)
	parent.add_child(node)
	return node


## The start: standing stones in a ring around the arrival point (gaps ahead where the
## dummies stand and behind where the gate does) and two torches on posts; visual only, placed
## from the world seed like the gate.
func _arrival_look(realm: RealmDef) -> void:
	var parent := places[StringName(realm.id)] as Node3D
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.2, 0.2, 0.22)
	rock.roughness = 1.0
	for stone in _arrival_stones(realm):
		var root := Node3D.new()
		root.transform = stone
		parent.add_child(root)
		var model := _prop(
			root, NATURE + "stone_tallA.glb", Vector3.ZERO, Basis.IDENTITY, STONE_SCALE
		)
		_recolor(model, rock)
	for side: float in [-1.0, 1.0]:
		var spot := Layout.arrival_spot(realm, -3.0, side * 5.5)
		var root := Node3D.new()
		root.position = spot[0]
		root.basis = SimPlayer.frame(spot[1], Vector3.BACK)
		parent.add_child(root)
		root.add_child(_block(Vector3(0.14, 1.7, 0.14), Vector3(0, 0.85, 0), _surface(BRICK, 0.3)))
		_torch(root, Vector3(0, 1.45, 0.07), Vector3.BACK, false)


## Where the ring's stones stand (gaps ahead where the dummies are and behind at the gate).
func _arrival_stones(realm: RealmDef) -> Array[Transform3D]:
	var found: Array[Transform3D] = []
	for k in range(1, STONE_COUNT):
		var angle := TAU * k / STONE_COUNT
		if absf(angle - PI) < 0.1:
			continue
		var spot := Layout.arrival_spot(realm, cos(angle) * STONE_RING, sin(angle) * STONE_RING)
		found.append(Transform3D(_frame_at(spot), spot[0]))
	return found


## A basis standing along spot's up, looking at the ring's center.
func _frame_at(spot: Array) -> Basis:
	var center := Layout.arrival_spot(Layout.start_realm(), 0.0, 0.0)
	var up: Vector3 = spot[1]
	var inward := (center[0] as Vector3) - (spot[0] as Vector3)
	inward -= up * inward.dot(up)
	return SimPlayer.frame(up, inward.normalized())


## Gives every surface of a model's meshes one material.
func _recolor(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_recolor(child, material)


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


## A standing stone gate with a swirling veil, a light and its name; the planet it stands on
## owns it.
func _portal(portal: Portal) -> Node3D:
	var root := Node3D.new()
	root.position = portal.position
	root.basis = SimPlayer.frame(portal.up, Vector3.FORWARD)
	(places[Layout.place_at(portal.position)] as Node3D).add_child(root)
	var stone := _surface(BRICK, 0.6)
	for x: float in [-GATE_PILLAR_X, GATE_PILLAR_X]:
		root.add_child(_block(GATE_PILLAR, Vector3(x, GATE_PILLAR.y * 0.5, 0), stone))
	root.add_child(_block(GATE_LINTEL, Vector3(0, GATE_LINTEL_Y, 0), stone))
	var veil := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.8, 3.9)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/portal.gdshader")
	var tint := Color(0.95, 0.75, 0.4) if portal.needs_flag != &"" else Color(0.45, 0.7, 1.0)
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
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * scale_by
	_materials[key] = material
	return material


## Moonlight, the night sky with its moon, and post-processing (PLAN §3.1, §3.2).
func _add_environment() -> void:
	var moon := DirectionalLight3D.new()
	moon.rotation = MOON_ROTATION * (PI / 180.0)
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
	_sky = sky_material
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


## Clients: on a generated realm the moon and the sky's horizon follow the walker's local up (a
## round ground has no single "up"); elsewhere they stay as built. Eased, so crossing a pole of
## the frame does not snap.
func follow_up(point: Vector3, delta: float) -> void:
	if sun == null:
		return
	var def := Layout.realm_at(point)
	var up := Vector3.UP if def == null else (point - def.center).normalized()
	var frame := SimPlayer.frame(up, SimPlayer._tangent(Vector3.FORWARD, up))
	var moon := frame * Basis.from_euler(MOON_ROTATION * (PI / 180.0))
	sun.basis = sun.basis.slerp(moon, 1.0 - exp(-MOON_FOLLOW * delta))
	_sky.set_shader_parameter("sky_up", up)
	_sky.set_shader_parameter(
		"planet_direction",
		sun.basis * Basis.from_euler(MOON_ROTATION * (PI / 180.0)).inverse() * PLANET_DIRECTION
	)
