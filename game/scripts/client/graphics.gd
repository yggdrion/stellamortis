class_name Graphics
extends RefCounted
## Graphics presets (PLAN §3.1), cycled with F4 and saved in user://settings.cfg. Low and
## Medium render at a lower resolution and upscale with FSR 2; Ultra adds SDFGI and SSR.

enum Preset { LOW, MEDIUM, HIGH, ULTRA }

const NAMES := ["Low", "Medium", "High", "Ultra"]
const SETTINGS := "user://settings.cfg"

static var preset := Preset.HIGH


static func load_saved() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		preset = clampi(int(config.get_value("graphics", "preset", Preset.HIGH)), 0, 3) as Preset


static func save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("graphics", "preset", preset)
	config.save(SETTINGS)


static func cycle(viewport: Viewport, arena: Arena) -> void:
	preset = ((preset + 1) % NAMES.size()) as Preset
	apply(viewport, arena)
	save()


static func apply(viewport: Viewport, arena: Arena) -> void:
	var env := arena.environment
	var low := preset == Preset.LOW
	var medium_up := preset >= Preset.MEDIUM
	var high_up := preset >= Preset.HIGH
	var ultra := preset == Preset.ULTRA

	if high_up:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0
	else:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		viewport.scaling_3d_scale = 0.67 if low else 0.8
	# FSR 2 brings its own temporal anti-aliasing.
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_SMAA
		if high_up and not ultra
		else Viewport.SCREEN_SPACE_AA_DISABLED
	)
	viewport.use_taa = ultra

	env.ssao_enabled = medium_up
	env.ssil_enabled = high_up
	env.volumetric_fog_enabled = medium_up
	env.sdfgi_enabled = ultra
	env.ssr_enabled = ultra
	env.glow_enabled = true

	RenderingServer.directional_shadow_atlas_set_size(2048 if low else 4096, true)
	(
		RenderingServer
		. directional_soft_shadow_filter_set_quality(
			[
				RenderingServer.SHADOW_QUALITY_SOFT_LOW,
				RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
				RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
				RenderingServer.SHADOW_QUALITY_SOFT_ULTRA,
			][preset]
		)
	)
	arena.sun.directional_shadow_max_distance = 80.0 if low else 140.0
