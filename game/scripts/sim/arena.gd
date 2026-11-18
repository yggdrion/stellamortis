class_name Arena
extends Node3D
## A node for every generated realm (the Barrowlands, where players start; TerrainView fills it),
## the arrival's stones and the gates. Collision on both sides, meshes, lights and sky only on
## clients. Built in code so server and client always get the same collision. Every prop and
## worked stone is generated (M38, `Generators`, docs/STYLE.md). Clients show one place at a time
## (show_place).

const STONE_COUNT := 10
const STONE_RING := 6.0
## A ring stone's solid: the `ring_stone` kind (2.0 x 2.4 x 1.4), a little narrower.
const STONE_SOLID := Vector3(1.9, 2.3, 1.3)
## A gate's arch: pillar centers either side of the opening, pillar and lintel boxes, the lintel's
## height. Visual (_portal) and solid (_add_gate_solids) read the same numbers.
const GATE_PILLAR_X := 1.7
const GATE_PILLAR := Vector3(0.6, 4.0, 0.7)
const GATE_LINTEL := Vector3(4.2, 0.7, 0.8)
const GATE_LINTEL_Y := 4.3
## The barrow ring (M22): torch posts and the barrow door, in meters from the ring's center.
const SITE_TORCH_RADIUS := 14.5
const SITE_DOOR_RADIUS := 21.0
const SITE_MOUND := Vector3(7.5, 3.4, 7.5)
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
## Generated meshes by kind and seed, shared by every instance; clients only.
var _meshes := {}
var _fire: ShaderMaterial
## The sky shader: the moon-planet and horizon follow the walker (follow_up).
var _sky: ShaderMaterial
## Torch lights; each flickers with its own phase.
var _torches: Array[OmniLight3D] = []
## The boss site's embers (M22), lit while the Warden fights.
var _site_encounter: Encounter
var _site_embers: GPUParticles3D
var _site_realm := &""
var _site_was := Encounter.Phase.IDLE


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


## Clients: the boss site's look (M22), from BossSite positions, the same on every client.
func add_site_looks(world_seed: int) -> void:
	for def in Layout.realms():
		_site_look(def, BossSite.at(def, world_seed))


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
	_site_embers_update()
	var seconds := Time.get_ticks_msec() / 1000.0
	for i in _torches.size():
		var light := _torches[i]
		light.light_energy = (
			2.2 + 0.25 * sin(seconds * 9.0 + i * 1.7) + 0.15 * sin(seconds * 23.0 + i)
		)


# --- Pieces --------------------------------------------------------------------------------


## One generated model (`Generators`, full level) at a place, shared by seed; visual only.
func _gen(
	parent: Node3D, id: String, seed_of: int, at := Vector3.ZERO, orientation := Basis.IDENTITY
) -> MeshInstance3D:
	var key := "%s#%d" % [id, seed_of]
	if not _meshes.has(key):
		_meshes[key] = Generators.build(id, seed_of, Palette.of(Layout.start_realm().id))[0]
	var node := MeshInstance3D.new()
	node.mesh = _meshes[key]
	node.position = at
	node.basis = orientation
	parent.add_child(node)
	return node


## A plain painted box (a post, a jamb) from the palette's role, like the generated props.
func _part(parent: Node3D, role: StringName, size: Vector3, at: Vector3) -> MeshInstance3D:
	var key := "box:%s:%s" % [role, size]
	if not _meshes.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		var palette := Palette.of(Layout.start_realm().id)
		var box := PropKit.box(palette, rng, role, size, Vector3.ZERO, Vector2.ZERO, Budgets.FULL)
		_meshes[key] = MeshKit.commit([box])
	var node := MeshInstance3D.new()
	node.mesh = _meshes[key]
	node.position = at
	parent.add_child(node)
	return node


## The start: standing stones in a ring around the arrival point (gaps ahead where the
## dummies stand and behind where the gate does) and two torches on posts; visual only, placed
## from the world seed like the gate.
func _arrival_look(realm: RealmDef) -> void:
	var parent := places[StringName(realm.id)] as Node3D
	var stones := _arrival_stones(realm)
	for k in stones.size():
		var root := Node3D.new()
		root.transform = stones[k]
		parent.add_child(root)
		_gen(root, "ring_stone", k)
	for side: float in [-1.0, 1.0]:
		var spot := Layout.arrival_spot(realm, -3.0, side * 5.5)
		var root := Node3D.new()
		root.position = spot[0]
		root.basis = SimPlayer.frame(spot[1], Vector3.BACK)
		parent.add_child(root)
		_part(root, &"wood", Vector3(0.14, 1.7, 0.14), Vector3(0, 0.85, 0))
		_torch(root, Vector3(0, 1.45, 0.07), Vector3.BACK, false)


## The barrow ring: torch posts between the standing stones (which TerrainView draws, solid
## from Scatter), a barrow mound with a brick door at the ring's edge and embers that rise from
## the middle while the Warden fights.
func _site_look(realm: RealmDef, site: BossSite) -> void:
	var parent := places[StringName(realm.id)] as Node3D
	var middle := site.center()
	for n in BossSite.STONES:
		var spot := _site_spot(realm, site, TAU * (n + 0.5) / BossSite.STONES, SITE_TORCH_RADIUS)
		if n % 2 == 1:
			continue
		var root := Node3D.new()
		root.position = spot[0]
		root.basis = _site_frame(spot, middle)
		parent.add_child(root)
		_part(root, &"stone", Vector3(0.22, 2.0, 0.22), Vector3(0, 1.0, 0))
		_torch(root, Vector3(0, 1.7, -0.11), Vector3.FORWARD, false)
	var door := _site_spot(realm, site, TAU * 3.0 / 16.0, SITE_DOOR_RADIUS)
	var root := Node3D.new()
	root.position = door[0]
	root.basis = _site_frame(door, middle)
	parent.add_child(root)
	var mound := _gen(root, "mound", 1, Vector3(0, 0, SITE_MOUND.z * 0.8))
	mound.scale = Vector3(
		SITE_MOUND.x / (MoundKind.NOMINAL.x * 0.5),
		SITE_MOUND.y / MoundKind.NOMINAL.y,
		SITE_MOUND.z / (MoundKind.NOMINAL.z * 0.5)
	)
	for side: float in [-1.0, 1.0]:
		_part(root, &"stone", Vector3(0.5, 3.6, 0.5), Vector3(side * 1.35, 1.8, 0.2))
	_part(root, &"stone_dark", Vector3(3.2, 0.5, 0.6), Vector3(0, 3.85, 0.2))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.01, 0.01, 0.015)
	dark.roughness = 1.0
	root.add_child(_block(Vector3(2.2, 3.6, 0.3), Vector3(0, 1.8, 0.35), dark))
	for side: float in [-1.0, 1.0]:
		var post := Node3D.new()
		post.position = Vector3(side * 2.4, 0, -0.6)
		root.add_child(post)
		_part(post, &"stone", Vector3(0.2, 1.8, 0.2), Vector3(0, 0.9, 0))
		_torch(post, Vector3(0, 1.5, -0.1), Vector3.FORWARD, false)
	_site_realm = StringName(realm.id)
	_site_embers = _make_embers(parent, middle, site.direction)


## (position, up) of a point `meters` from the site's center at an angle, on the ground.
func _site_spot(realm: RealmDef, site: BossSite, angle: float, meters: float) -> Array:
	# The disc is dead flat out to BossSite.FLAT: the ground is the site's level.
	var direction := site.spot(angle, meters)
	return [realm.center + direction * (realm.radius + site.level), direction]


## Standing along a spot's up with its front toward the ring's middle.
func _site_frame(spot: Array, middle: Vector3) -> Basis:
	var up: Vector3 = spot[1]
	var inward := middle - (spot[0] as Vector3)
	return SimPlayer.frame(up, SimPlayer._tangent(inward, up))


## Embers over the ring, off until the Warden rises.
func _make_embers(parent: Node3D, middle: Vector3, up: Vector3) -> GPUParticles3D:
	var embers := GPUParticles3D.new()
	embers.emitting = false
	embers.amount = maxi(16, roundi(160 * HitEffects.COUNT_SCALE[Graphics.preset]))
	embers.lifetime = 3.5
	embers.local_coords = true
	embers.visibility_aabb = AABB(Vector3(-16, -2, -16), Vector3(32, 14, 32))
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = BossSite.RING_RADIUS
	process.emission_ring_inner_radius = 0.0
	process.emission_ring_height = 0.2
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0, 0.3, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	var fade := Curve.new()
	fade.add_point(Vector2(0, 0.2))
	fade.add_point(Vector2(0.2, 1))
	fade.add_point(Vector2(1, 0))
	var curve := CurveTexture.new()
	curve.curve = fade
	process.scale_curve = curve
	embers.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.1
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.gradient = Gradient.new()
	dot.gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.albedo_texture = dot
	paint.albedo_color = Color(1.0, 0.45, 0.1)
	paint.emission_enabled = true
	paint.emission = Color(1.0, 0.45, 0.1)
	paint.emission_energy_multiplier = 6.0
	quad.material = paint
	embers.draw_pass_1 = quad
	embers.position = middle
	embers.basis = SimPlayer.frame(up, SimPlayer._tangent(Vector3.FORWARD, up))
	parent.add_child(embers)
	return embers


## Embers burn while the fight runs; a burst of sparks and a stomp as the Warden rises.
func _site_embers_update() -> void:
	if _site_embers == null:
		return
	if _site_encounter == null:
		_site_encounter = Encounter.of(self, String(_site_realm))
		return
	var phase := _site_encounter.phase
	_site_embers.emitting = phase == Encounter.Phase.BOSS
	if phase == Encounter.Phase.BOSS and _site_was != Encounter.Phase.BOSS:
		var at := _site_embers.global_position
		HitEffects.burst(self, at, _site_embers.global_basis.y, HitEffects.Kind.EMBERS)
	_site_was = phase


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


## A wall torch: the generated iron torch with a glowing flame and a flickering warm light,
## mounted on a wall whose face looks along out.
func _torch(parent: Node3D, at: Vector3, out: Vector3, shadows: bool) -> void:
	var root := Node3D.new()
	root.position = at
	# The torch's plate is at its origin and it reaches out along +Z.
	root.basis = Basis.looking_at(-out, Vector3.UP)
	parent.add_child(root)
	_gen(root, "torch", 0)
	var flame := _gen(root, "torch_flame", 0, TorchKind.FLAME_AT)
	if _fire == null:
		_fire = MeshKit.material().duplicate() as ShaderMaterial
		_fire.set_shader_parameter("glow", 8.0)
	flame.material_override = _fire
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = TORCH_LIGHT
	light.omni_range = 11.0
	light.omni_attenuation = 1.4
	light.position = Vector3(0, 1.0, 0.45)
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
	_gen(root, "gate_arch", 0)
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
	# No SSIL or SDFGI anywhere: they darken shade here (M41 task 1, Graphics).
	env.ssil_enabled = false
	env.sdfgi_enabled = false
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
