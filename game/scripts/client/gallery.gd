class_name Gallery
extends Node3D
## `--gallery[=ID]` (M36): every registered generator kind (or the one named) standing on flat
## ground under dusk light. One block per kind, variants left to right, levels of detail front
## to back (full, half, far), a 1.8 m figure for scale. No server, no world.
## `--gallery-stress=N` (`stress`) is the cost mode: see `_run_stress`.

const REALM := "barrowlands"
const VARIANTS := 5
const SPACING := 4.0
## Distance between the rows of one kind, and between kinds.
const ROW := 5.0
const KIND_GAP := 4.0
const FIGURE_HEIGHT := 1.8
const FIGURE_RADIUS := 0.25
## Side of the square the stress mode scatters instances over, meters.
const FIELD := 140.0
const LOD_NAMES: Array[String] = ["full", "half", "far"]

## One kind id, "" for all.
var only := ""
## Camera yaw and pitch in degrees (yaw 0 looks along -Z), null for the default.
var look: Variant = null
var graphics := ""
var screenshot_path := ""
var screenshot_delay := 2.0
## `--gallery-stress=N`: instances per kind (0 = the plain gallery).
var stress := 0
## Seconds measured per test in the stress mode.
var seconds := 2.0
var quit_when_done := false

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
	if stress > 0:
		_run_stress(ids, palette)
		return
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
	_set_graphics()
	if screenshot_path != "":
		await _take_screenshot()
		get_tree().quit()


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


func _set_graphics() -> void:
	if graphics != "":
		Graphics.preset = maxi(0, Graphics.NAMES.find(graphics.capitalize())) as Graphics.Preset
	_apply_graphics()


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


## Cost mode (M36 task 3). Prints, per kind: build time on a worker per variant and the main
## thread commit time per variant (its three levels); then, per kind and level, `stress`
## instances through one `MultiMeshInstance3D` per variant: average and worst frame time and the
## renderer's own CPU and GPU time over `seconds`. "grass" is a tuft built here at the grass
## budget (4 times `stress` instances; a registered kind comes with M37); pine_young full is also
## run with `MeshKit.burn_material()` ("burn", the shader with the discard) against the plain
## one. Frame times are uncapped (no vsync, no fps limit): the cost, not the display.
func _run_stress(ids: Array[String], palette: Palette) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var ground := PlaneMesh.new()
	ground.size = Vector2(FIELD + 60.0, FIELD + 60.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = palette.color(&"moss")
	ground.material = floor_material
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = ground
	floor_node.position.z = -FIELD * 0.3
	add_child(floor_node)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.position = Vector3(0.0, 45.0, 55.0)
	_camera.rotation = Vector3(deg_to_rad(-35.0), 0.0, 0.0)
	add_child(_camera)
	_camera.make_current()
	_set_graphics()
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	print("STRESS preset=%s n=%d seconds=%.1f" % [Graphics.NAMES[Graphics.preset], stress, seconds])
	var kit: Dictionary = {}  # kind id -> per variant: Array of 3 meshes
	var t0 := Time.get_ticks_usec()
	MeshKit.material()
	print("STRESS first MeshKit.material() %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	for id in ids:
		kit[id] = await _stress_build(id, palette)
	var grass: Array = []
	for variant in VARIANTS:
		grass.append(_grass_meshes(variant + 1, palette))
	kit["grass"] = grass
	var plain: ShaderMaterial = MeshKit.material()
	var burn := MeshKit.burn_material()
	var tests: Array = []
	for id: String in kit:
		for lod in 3:
			if ((kit[id][0] as Array)[lod] as ArrayMesh).get_surface_count() > 0:
				tests.append([id, lod, plain, ""])
	for i in 2:
		tests.append(["pine_young", 0, burn, "burn"])
		tests.append(["pine_young", 0, plain, "again"])
	var first := true
	for t: Array in tests:
		var count := stress * (4 if t[0] == "grass" else 1)
		var holder := _stress_field(kit[t[0]], t[1], count, t[2])
		await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		if first and screenshot_path != "":
			first = false
			await _take_screenshot()
		var frames := PackedFloat64Array()
		var cpu := 0.0
		var gpu := 0.0
		var end := Time.get_ticks_usec() + int(seconds * 1e6)
		var last := Time.get_ticks_usec()
		while last < end:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frames.append((now - last) / 1000.0)
			last = now
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		var n := maxf(frames.size(), 1.0)
		print(
			(
				"STRESS %-12s lod=%d %-9s n=%-6d frame_avg=%.2f worst=%.2f render_cpu=%.2f gpu=%.2f ms"
				% [t[0], t[1], t[3], count, _avg(frames), _max(frames), cpu / n, gpu / n]
			)
		)
		holder.queue_free()
	if quit_when_done:
		get_tree().quit()


## Builds the arrays of every variant on a worker thread, then commits them here; prints both.
func _stress_build(id: String, palette: Palette) -> Array:
	var worker_ms := PackedFloat64Array()
	var arrays: Array = []
	var thread := Thread.new()
	thread.start(
		func() -> void:
			for variant in VARIANTS:
				var t0 := Time.get_ticks_usec()
				arrays.append(Generators.arrays(id, variant + 1, palette))
				worker_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	)
	while thread.is_alive():
		await get_tree().process_frame
	thread.wait_to_finish()
	var variants: Array = []
	var commit_ms := PackedFloat64Array()
	for levels: Array in arrays:
		var t0 := Time.get_ticks_usec()
		var meshes: Array = []
		for part: Array in levels:
			meshes.append(MeshKit.commit([part]))
		commit_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		variants.append(meshes)
	print(
		(
			"STRESS build %-12s worker avg=%.2f max=%.2f ms/variant, commit avg=%.2f max=%.2f ms/variant"
			% [id, _avg(worker_ms), _max(worker_ms), _avg(commit_ms), _max(commit_ms)]
		)
	)
	return variants


## `count` instances of a kind's level over the field, split over its variants.
func _stress_field(variants: Array, lod: int, count: int, material: Material) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for variant in variants.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[variant][lod]
		mm.instance_count = count / variants.size()
		for i in mm.instance_count:
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			basis = basis.scaled(Vector3.ONE * rng.randf_range(0.8, 1.2))
			var at := Vector3(
				rng.randf_range(-FIELD * 0.5, FIELD * 0.5),
				0.0,
				rng.randf_range(-FIELD * 0.8, FIELD * 0.2)
			)
			mm.set_instance_transform(i, Transform3D(basis, at))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = material
		holder.add_child(node)
	return holder


## A grass tuft at the budget (12, 6 triangles): four, then two one sided blades.
func _grass_meshes(variant_seed: int, palette: Palette) -> Array:
	var meshes: Array = []
	for lod in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = variant_seed
		var parts: Array = []
		var look := MeshKit.jitter(rng)
		var blades := 4 - 2 * lod
		for k in blades:
			var yaw := (k + rng.randf()) * TAU / blades
			var dir := Vector3(sin(yaw), 0.0, cos(yaw))
			var path := PackedVector3Array(
				[Vector3.ZERO, dir * 0.08 + Vector3.UP * 0.2, dir * 0.2 + Vector3.UP * 0.35]
			)
			var blade := MeshKit.blade(path, 0.08, dir, false, dir.cross(Vector3.UP))
			parts.append(MeshKit.paint(blade, palette.color(&"grass"), rng, Vector3.DOWN, look))
		meshes.append(MeshKit.commit(parts))
	meshes.append(ArrayMesh.new())
	return meshes


static func _avg(values: PackedFloat64Array) -> float:
	var sum := 0.0
	for v in values:
		sum += v
	return sum / maxf(values.size(), 1.0)


static func _max(values: PackedFloat64Array) -> float:
	var m := 0.0
	for v in values:
		m = maxf(m, v)
	return m
