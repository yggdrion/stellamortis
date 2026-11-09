shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
// The player's shield: a thin hard-light disc, bright at the rim and along a hex grid, faint in
// between, with a slow shimmer. strength rises while blocking.

uniform vec4 tint : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform float strength = 0.4;

float hex_lines(vec2 p) {
	p *= 9.0;
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	float edge = max(dot(q, normalize(vec2(1.0, 1.7320508))), q.x);
	return smoothstep(0.42, 0.5, edge);
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float radius = length(centered);
	if (radius > 1.0) {
		discard;
	}
	float rim = smoothstep(0.75, 1.0, radius);
	float shimmer = 0.5 + 0.5 * sin(TIME * 3.0 + radius * 12.0);
	float glow = 0.08 + 0.35 * hex_lines(centered) * (0.6 + 0.4 * shimmer) + 0.9 * rim;
	ALBEDO = tint.rgb * glow * strength * 2.0;
}
