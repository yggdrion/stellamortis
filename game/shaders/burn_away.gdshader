shader_type spatial;
// A body burning away (M19): noise eats it from the edges while the rim glows like embers.
// Stands in for the model's own material, which it copies the albedo from.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 ember : source_color = vec3(1.0, 0.4, 0.1);
// 0 whole, 1 gone.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Thickness of the glowing rim, in noise units.
uniform float rim = 0.12;
uniform float noise_scale = 5.0;

varying vec3 local;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	float n = value_noise(local * noise_scale) * 0.65 + value_noise(local * noise_scale * 2.7) * 0.35;
	float edge = n - amount * (1.0 + rim);
	if (edge < 0.0) {
		discard;
	}
	float glow = 1.0 - smoothstep(0.0, rim, edge);
	vec4 base = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = mix(base.rgb, vec3(0.02), glow);
	ROUGHNESS = 0.8;
	EMISSION = ember * glow * 5.0;
}
