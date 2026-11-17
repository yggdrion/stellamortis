shader_type spatial;
// The one shader of every generated model (docs/STYLE.md section 2, M36): vertex color is the
// albedo, the color's alpha is the roughness. No ALPHA is written, so the alpha channel is never
// transparency (the render mode stays opaque). Flat normals come from the mesh (unshared vertices).
// Vertex colors are authored as sRGB (palette values), the shader converts them.
// The hooks below stay at zero until they are used: glow for the meaning roles (a model that glows
// needs its own copy of the material), wind (M42), burn away (deaths, like burn_away.gdshader).

uniform float glow = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.35, 0.1);
uniform float wind_strength = 0.0;
uniform float wind_speed = 1.5;
uniform float burn_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 local;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	local = VERTEX;
	float sway = sin(TIME * wind_speed + VERTEX.x * 0.5 + VERTEX.z * 0.7) * wind_strength;
	VERTEX.xz += vec2(sway, sway * 0.6) * max(VERTEX.y, 0.0);
}

void fragment() {
	if (burn_amount > 0.0 && hash(floor(local * 12.0)) < burn_amount) {
		discard;
	}
	vec3 c = COLOR.rgb;
	vec3 lin = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	ALBEDO = lin;
	ROUGHNESS = COLOR.a;
	EMISSION = glow_color * glow;
}
