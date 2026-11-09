// A health bar that always faces the camera: `fill` 0..1 of `color` over a dark back.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform vec4 color : source_color = vec4(0.85, 0.15, 0.12, 1.0);
uniform vec4 back : source_color = vec4(0.05, 0.05, 0.06, 0.75);

void vertex() {
	// Keep the mesh's world position, drop its rotation: face the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	float border = step(uv.x, 0.01) + step(0.99, uv.x) + step(uv.y, 0.08) + step(0.92, uv.y);
	vec4 c = uv.x <= fill ? color : back;
	c = mix(c, vec4(0.0, 0.0, 0.0, 1.0), clamp(border, 0.0, 1.0));
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
