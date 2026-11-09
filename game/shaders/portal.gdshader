shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
// A portal's veil (PLAN §6 M12): a slow swirl of light inside an arched opening, brightest at
// the rim, fading at the bottom where it meets the ground.

uniform vec4 tint : source_color = vec4(0.45, 0.7, 1.0, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	// Arch: a rectangle with a round top, in UV (0..1, y down).
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
	float top = 1.0 - 0.36;
	float inside_arch = p.y < top ? step(abs(p.x), 1.0) : step(length(vec2(p.x, (p.y - top) / 0.36)), 1.0);
	if (inside_arch < 0.5) {
		discard;
	}
	vec2 c = vec2(p.x, (p.y - 0.5) * 1.4);
	float r = length(c);
	float a = atan(c.y, c.x);
	float swirl = noise(vec2(a * 2.0 + TIME * 0.6 - r * 4.0, r * 6.0 - TIME * 0.8));
	float rim = smoothstep(0.55, 1.0, max(abs(p.x), p.y > top ? length(vec2(p.x, (p.y - top) / 0.36)) : 0.0));
	float base = smoothstep(0.0, 0.25, p.y);
	float glow = (0.18 + 0.55 * swirl + 0.9 * rim) * base;
	ALBEDO = tint.rgb * glow * 1.6;
}
