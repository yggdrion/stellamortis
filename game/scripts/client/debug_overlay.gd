class_name DebugOverlay
extends CanvasLayer
## F3: frame and network numbers (PLAN §3.1: watch performance from M0).

var client: GameClient
var _label: Label


func _ready() -> void:
	layer = 10
	# Render times are only measured on request; it costs little, so always on.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	visible = false
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)


func _process(_delta: float) -> void:
	if not visible or client == null:
		return
	var lines := PackedStringArray()
	var viewport := get_viewport().get_viewport_rid()
	(
		lines
		. append(
			(
				(
					"FPS %d   frame %.2f ms (incl. vsync wait)   render CPU %.2f ms   GPU %.2f ms"
					+ "   physics %.2f ms   draw calls %d"
				)
				% [
					Engine.get_frames_per_second(),
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
					(
						RenderingServer.get_frame_setup_time_cpu()
						+ RenderingServer.viewport_get_measured_render_time_cpu(viewport)
					),
					RenderingServer.viewport_get_measured_render_time_gpu(viewport),
					Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"ping %d ms   netfox rtt %d ms   tick %d   server %.1f tps, tick loop max %.2f ms"
				% [
					client.ping_ms,
					NetworkTime.remote_rtt * 1000.0,
					NetworkTime.tick,
					client.server_tps,
					client.server_tick_ms,
				]
			)
		)
	)
	lines.append("players %d" % client.player_count())
	if client.me:
		var p := client.me.global_position
		var zone := Gravity.zone_at(p)
		(
			lines
			. append(
				(
					"pos %.1f %.1f %.1f   grounded %s   gravity %.1f m/s² (%s)"
					% [
						p.x,
						p.y,
						p.z,
						client.me.grounded,
						Gravity.sample(p).length(),
						"normal" if zone == null else zone.label,
					]
				)
			)
		)
	lines.append("%s, %s" % [RenderingServer.get_video_adapter_name(), OS.get_name()])
	_label.text = "\n".join(lines)
