// The ground of a generated realm (M20): grass, heather and rock, all triplanar in world space,
// blended by slope (rock on steep ground), height (heather and bare rock on the hills) and a
// slow patch noise. "Up" is away from the realm's center, the ground is a sphere.
shader_type spatial;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 realm_center;
uniform float realm_radius = 1000.0;
uniform float grass_scale = 0.2;
uniform float rock_scale = 0.16;
uniform vec3 grass_tint : source_color = vec3(0.62, 0.64, 0.46);
uniform vec3 heather_tint : source_color = vec3(0.6, 0.42, 0.5);
uniform vec3 rock_tint : source_color = vec3(0.7, 0.7, 0.72);
// Meters above sea level where heather starts to win and where the hills turn to bare rock.
uniform float heather_height = 5.0;
uniform float rock_height = 42.0;
// Cosine of the slope: rock starts below slope_from and is all rock below slope_to.
uniform float slope_from = 0.9;
uniform float slope_to = 0.76;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 blend_weights(vec3 n) {
	vec3 b = pow(abs(n), vec3(6.0));
	return b / (b.x + b.y + b.z);
}

vec3 tri_color(sampler2D t, vec3 p, vec3 b) {
	return texture(t, p.zy).rgb * b.x + texture(t, p.xz).rgb * b.y + texture(t, p.xy).rgb * b.z;
}

// A tangent space normal from a map that may only keep red and green (compressed).
vec3 unpack(vec2 rg) {
	vec2 xy = rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// Whiteout blend of the three projections' normals, in world space.
vec3 tri_normal(sampler2D t, vec3 p, vec3 n, vec3 b) {
	vec3 tx = unpack(texture(t, p.zy).rg);
	vec3 ty = unpack(texture(t, p.xz).rg);
	vec3 tz = unpack(texture(t, p.xy).rg);
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * b.x + ty.xzy * b.y + tz.xyz * b.z);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 b = blend_weights(n);
	vec3 from_center = world_pos - realm_center;
	vec3 up = normalize(from_center);
	float height = length(from_center) - realm_radius;
	float slope = dot(n, up);

	// Slow patches, from the grass texture read at a very low frequency.
	float patch = texture(grass_albedo, world_pos.xz * 0.0041).g
		+ texture(grass_albedo, world_pos.zy * 0.0057).g;
	patch = patch * 0.5;
	float heather = smoothstep(-0.04, 0.04, patch - 0.5 + (height - heather_height) * 0.012);
	float rock = max(
		1.0 - smoothstep(slope_to, slope_from, slope),
		smoothstep(rock_height, rock_height + 8.0, height + (patch - 0.5) * 16.0));

	vec3 gp = world_pos * grass_scale;
	vec3 rp = world_pos * rock_scale;
	vec3 grass = tri_color(grass_albedo, gp, b);
	// Heather: the same ground read at another scale, in a dull purple brown.
	vec3 moor = mix(grass * grass_tint, tri_color(grass_albedo, gp * 0.37, b) * heather_tint * 1.4, heather);
	vec3 stone = tri_color(rock_albedo, rp, b) * rock_tint;
	ALBEDO = mix(moor, stone, rock);

	vec3 ground_n = tri_normal(grass_normal, gp, n, b);
	vec3 rock_n = tri_normal(rock_normal, rp, n, b);
	vec3 world_n = normalize(mix(ground_n, rock_n, rock));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	ROUGHNESS = mix(0.95, 0.85, rock);
	SPECULAR = 0.2;
}
