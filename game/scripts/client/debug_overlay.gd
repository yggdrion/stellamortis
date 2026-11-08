class_name DebugOverlay
extends CanvasLayer
## F3: frame and network numbers (PLAN §3.1: watch performance from M0).

var client: GameClient
var _label: Label


func _ready() -> void:
	layer = 10
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
	(
		lines
		. append(
			(
				"FPS %d   frame %.2f ms   draw calls %d"
				% [
					Engine.get_frames_per_second(),
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				]
			)
		)
	)
	lines.append(
		(
			"ping %d ms   fake lag %d ms   server %.1f tps, tick max %.2f ms"
			% [client.ping_ms, client.net.lag_ms, client.server_tps, client.server_tick_ms]
		)
	)
	lines.append(
		(
			"players %d   corrections %d (max %.3f m)"
			% [client.player_count(), client.corrections, client.max_error]
		)
	)
	if client.me:
		var p := client.me.global_position
		lines.append("pos %.1f %.1f %.1f   grounded %s" % [p.x, p.y, p.z, client.me.grounded])
	lines.append("%s, %s" % [RenderingServer.get_video_adapter_name(), OS.get_name()])
	_label.text = "\n".join(lines)
