class_name Gallery
extends Node3D
## `--gallery[=ID]` (M36): every registered generator kind (or the one named) standing on flat
## ground under dusk light. One block per kind, variants left to right, levels of detail front
## to back (full, half, far), a 1.8 m figure for scale. No server, no world.

const REALM := "barrowlands"
const VARIANTS := 5
const SPACING := 4.0
## Distance between the rows of one kind, and between kinds.
const ROW := 5.0
const KIND_GAP := 4.0
const FIGURE_HEIGHT := 1.8
const FIGURE_RADIUS := 0.25
const LOD_NAMES: Array[String] = ["full", "half", "far"]

## One kind id, "" for all.
var only := ""
## Camera yaw and pitch in degrees (yaw 0 looks along -Z), null for the default.
var look: Variant = null
var graphics := ""
var screenshot_path := ""
var screenshot_delay := 2.0

var _camera: Camera3D
var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	var palette := Palette.of(REALM)
	var ids := Generators.ids()
	if only != "":
		assert(only in ids, "no generator named " + only)
		ids = [only] as Array[String]
	_add_light()
	var depth := ids.size() * (3 * ROW + KIND_GAP)
	var width := (VARIANTS - 1) * SPACING
	_add_ground(width, depth, palette)
	for k in ids.size():
		var z := -k * (3 * ROW + KIND_GAP)
		for lod in 3:
			_add_label(
				"%s  %s" % [ids[k], LOD_NAMES[lod]], Vector3(-width * 0.5 - 3.5, 0.2, z - lod * ROW)
			)
		for variant in VARIANTS:
			var meshes := Generators.build(ids[k], variant + 1, palette)
			for lod in 3:
				var instance := MeshInstance3D.new()
				instance.mesh = meshes[lod]
				instance.position = Vector3(
					(variant - (VARIANTS - 1) * 0.5) * SPACING, 0.0, z - lod * ROW
				)
				add_child(instance)
	_add_figure(Vector3(-width * 0.5 - 1.5, 0.0, 2.5), palette)
	var back := width * 0.5 + 1.0
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.position = Vector3(0.0, 5.0, back + 6.0)
	var angles := look as Vector2 if look is Vector2 else Vector2(0.0, -12.0)
	_camera.rotation = Vector3(deg_to_rad(angles.y), deg_to_rad(angles.x), 0.0)
	add_child(_camera)
	_camera.make_current()
	if graphics != "":
		Graphics.preset = maxi(0, Graphics.NAMES.find(graphics.capitalize())) as Graphics.Preset
	_apply_graphics()
	if screenshot_path != "":
		_take_screenshot()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()


## Dusk: a low warm sun from the camera's right, a cool ambient, a warm horizon (like Arena's
## environment but daylight's last hour instead of night, so the colors can be judged).
func _add_light() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-22.0, 40.0, 0.0)
	_sun.light_color = Color(1.0, 0.68, 0.46)
	_sun.light_energy = 1.6
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 120.0
	add_child(_sun)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.16, 0.2, 0.36)
	sky_material.sky_horizon_color = Color(0.7, 0.5, 0.45)
	sky_material.ground_horizon_color = Color(0.7, 0.5, 0.45)
	sky_material.ground_bottom_color = Color(0.2, 0.2, 0.26)
	var sky := Sky.new()
	sky.sky_material = sky_material
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.42, 0.45, 0.58)
	_env.ambient_light_energy = 1.2
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.1
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.3, 0.26, 0.3)
	_env.fog_density = 0.004
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)


## The graphics preset's part that matters here (Graphics.apply needs an Arena).
func _apply_graphics() -> void:
	var medium_up := Graphics.preset >= Graphics.Preset.MEDIUM
	_env.ssao_enabled = medium_up
	_env.ssil_enabled = Graphics.preset >= Graphics.Preset.HIGH
	_sun.shadow_enabled = true
	RenderingServer.directional_shadow_atlas_set_size(4096 if medium_up else 2048, true)


func _add_ground(width: float, depth: float, palette: Palette) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(width + 40.0, depth + 40.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = palette.color(&"moss")
	material.albedo_color.a = 1.0
	material.roughness = 1.0
	plane.material = material
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.position = Vector3(0.0, 0.0, -depth * 0.5 + 10.0 + ROW)
	add_child(ground)


func _add_figure(at: Vector3, palette: Palette) -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = FIGURE_RADIUS
	capsule.height = FIGURE_HEIGHT
	var material := StandardMaterial3D.new()
	material.albedo_color = palette.color(&"cloth")
	material.albedo_color.a = 1.0
	capsule.material = material
	var figure := MeshInstance3D.new()
	figure.mesh = capsule
	figure.position = at + Vector3(0.0, FIGURE_HEIGHT * 0.5, 0.0)
	add_child(figure)


func _add_label(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	label.modulate = Color(0.85, 0.8, 0.72)
	add_child(label)


func _take_screenshot() -> void:
	await get_tree().create_timer(screenshot_delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(screenshot_path)
	print("Saved ", screenshot_path)
	get_tree().quit()
