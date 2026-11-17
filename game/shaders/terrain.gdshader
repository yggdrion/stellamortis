// The ground of a generated realm (M20, M37): flat-shaded faces, one palette color each. The chunk
// mesh has unshared vertices and the face's normal; every vertex of a face carries the same
// numbers in its vertex color (TerrainView._grid_arrays), so the color below is computed once per
// face and is the same on all three vertices: r = the forest noise at the face (0.5 = none),
// g = height over sea level, b = cosine of the slope, a = a per face roll. "Up" is away from the
// realm's center, the ground is a sphere. Colors are the realm's palette roles.
shader_type spatial;

uniform vec3 grass_color : source_color = vec3(0.3, 0.36, 0.22);
uniform vec3 heather_color : source_color = vec3(0.38, 0.26, 0.34);
uniform vec3 earth_color : source_color = vec3(0.28, 0.22, 0.17);
uniform vec3 stone_color : source_color = vec3(0.4, 0.4, 0.42);
uniform float ground_roughness = 0.95;
// Decoding of the vertex color: height = g * height_range + height_min.
uniform float height_min = -20.0;
uniform float height_range = 160.0;
// Forest noise (-1 to 1) under which the moor turns to heather, and the width of that edge.
uniform float heather_wood = -0.05;
uniform float heather_edge = 0.25;
// Most heather that shows (the rest is grass), how much a face's roll shifts it, and the share of
// faces that are bare earth.
uniform float heather_share = 0.6;
uniform float heather_roll = 0.3;
uniform float earth_patch = 0.4;
// Forest noise over which the floor is leaf litter (earth), and how much earth shows at most.
uniform float litter_wood = 0.1;
uniform float litter_share = 0.55;
// Meters above sea level where heather starts to win and where the hills turn to bare rock.
uniform float heather_height = 5.0;
uniform float rock_height = 42.0;
// Cosine of the slope: rock starts below slope_from and is all rock below slope_to; earth shows
// on the way (scree) up to scree_share.
uniform float slope_from = 0.9;
uniform float slope_to = 0.76;
uniform float scree_share = 0.5;
// Per face value variation (fraction, docs/STYLE.md: faces differ a little).
uniform float face_value = 0.09;

varying flat vec3 ground;

void vertex() {
	float wood = COLOR.r * 2.0 - 1.0;
	float height = COLOR.g * height_range + height_min;
	float slope = COLOR.b;
	float roll = COLOR.a * 2.0 - 1.0;

	float heather = clamp(
		smoothstep(heather_wood + 0.05, heather_wood - heather_edge, wood)
			+ smoothstep(heather_height, heather_height + 10.0, height) * 0.6
			+ roll * heather_roll,
		0.0, 1.0) * heather_share;
	vec3 color = mix(grass_color, heather_color, heather);
	// Bare earth in patches of single faces, more where the ground tilts.
	color = mix(color, earth_color, smoothstep(0.55, 1.0, COLOR.a) * earth_patch);
	color = mix(color, earth_color, smoothstep(litter_wood, litter_wood + 0.35, wood) * litter_share);
	color = mix(color, earth_color, smoothstep(slope_from + 0.04, slope_from - 0.06, slope) * scree_share);
	float rock = max(
		1.0 - smoothstep(slope_to, slope_from, slope),
		smoothstep(rock_height, rock_height + 8.0, height));
	color = mix(color, stone_color, rock);
	ground = color * (1.0 + roll * face_value);
}

void fragment() {
	ALBEDO = ground;
	ROUGHNESS = ground_roughness;
	SPECULAR = 0.2;
}
