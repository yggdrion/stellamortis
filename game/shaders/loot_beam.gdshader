shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, fog_disabled;
// The light that stands over a rare drop or a chest (M23): a soft column, brightest at the
// ground and at its middle seen from the side, fading with height, with a slow shimmer. The
// color is the item's rarity. The mesh is a cylinder `beam_height` tall whose base sits at the
// node's origin.

uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 1.0;
uniform float beam_height = 6.0;

varying float rise;

void vertex() {
	rise = clamp(VERTEX.y / beam_height + 0.5, 0.0, 1.0);
}

void fragment() {
	float center = pow(clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.6);
	float fade = pow(1.0 - rise, 1.7);
	float shimmer = 0.85 + 0.15 * sin(TIME * 2.2 + rise * 7.0);
	ALBEDO = tint.rgb;
	ALPHA = center * fade * shimmer * strength;
}
