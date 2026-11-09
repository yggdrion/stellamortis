// Space sky (PLAN §3.1): stars, a faint cold nebula, a thin horizon glow, the sun and a pale
// ice giant lit by the sun. Cheap enough for every preset: a few hashes and 4 noise octaves.
shader_type sky;

uniform vec3 nebula_warm : source_color = vec3(0.07, 0.09, 0.11);
uniform vec3 nebula_cold : source_color = vec3(0.02, 0.05, 0.10);
uniform vec3 horizon_glow : source_color = vec3(0.12, 0.16, 0.21);
uniform vec3 planet_direction = vec3(-0.45, 0.32, -0.83);
// Angular radius in radians.
uniform float planet_size = 0.3;
uniform vec3 planet_light : source_color = vec3(0.52, 0.56, 0.6);
uniform vec3 planet_dark : source_color = vec3(0.36, 0.39, 0.43);
uniform float star_density = 0.9975;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
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

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 cell = floor(d * 320.0);
	float star = step(star_density, hash(cell)) * (0.4 + 1.6 * hash(cell + 7.3));
	float n = fbm(d * 2.5 + vec3(3.0));
	vec3 color = mix(nebula_cold, nebula_warm, smoothstep(0.35, 0.75, n)) * pow(n, 2.5) * 0.9;
	color += vec3(star) * (1.0 - smoothstep(0.0, 0.25, -d.y));
	color += horizon_glow * pow(1.0 - abs(d.y), 10.0) * 0.7;

	float sun = dot(d, LIGHT0_DIRECTION);
	color += LIGHT0_COLOR * (smoothstep(0.9993, 0.9998, sun) * 6.0 + pow(max(sun, 0.0), 300.0) * 0.6);

	vec3 pd = normalize(planet_direction);
	vec3 t = normalize(cross(pd, vec3(0.0, 1.0, 0.1)));
	vec3 b = cross(t, pd);
	vec2 disk = vec2(dot(d, t), dot(d, b)) / sin(planet_size);
	float r2 = dot(disk, disk);
	if (dot(d, pd) > 0.0 && r2 < 1.0) {
		vec3 normal = normalize(t * disk.x + b * disk.y - pd * sqrt(1.0 - r2));
		float lit = clamp(dot(normal, LIGHT0_DIRECTION) * 1.2, 0.0, 1.0) + 0.06;
		float bands = sin(disk.y * 22.0 + fbm(vec3(disk * 3.0, 1.0)) * 4.0) * 0.5 + 0.5;
		vec3 surface = mix(planet_dark, planet_light, bands) * lit;
		float rim = pow(r2, 6.0) * lit;
		color = surface + horizon_glow * rim * 0.8;
	}
	COLOR = color;
}
