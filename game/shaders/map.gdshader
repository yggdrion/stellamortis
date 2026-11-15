shader_type canvas_item;
// The map (M33): inverse azimuthal equidistant projection per pixel, sampling the realm's
// equirectangular height image. Must match MapPanel.project/unproject.

uniform sampler2D heights : filter_linear, repeat_enable;
uniform bool ready = false;
uniform vec3 center_dir;
uniform vec3 forward_dir;
uniform vec3 right_dir;
// Pixels per projection unit (the full rim is 1 unit) and the view's size in pixels.
uniform float zoom = 100.0;
uniform vec2 view_size = vec2(800.0);
uniform float realm_radius = 1000.0;
uniform vec2 image_size = vec2(1024.0, 512.0);


float height_at(vec2 uv) {
	return textureLod(heights, uv, 0.0).r;
}

void fragment() {
	vec2 p = (UV - 0.5) * view_size;
	vec2 m = p / zoom;
	float r = length(m);
	if (r > 1.0) {
		COLOR = vec4(0.0);
	} else if (!ready) {
		COLOR = vec4(0.05, 0.045, 0.04, 1.0);
	} else {
		float theta = r * PI;
		vec3 t = r > 0.00001 ? (right_dir * m.x - forward_dir * m.y) / r : forward_dir;
		vec3 d = center_dir * cos(theta) + t * sin(theta);
		vec2 uv = vec2(atan(d.x, d.z) / (2.0 * PI) + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
		float h = height_at(uv);
		// Slope shade from the neighbours, light from the north-west.
		vec2 px = 1.0 / image_size;
		float cell_x = 2.0 * PI * realm_radius * max(cos((uv.y - 0.5) * PI), 0.05) / image_size.x;
		float cell_y = PI * realm_radius / image_size.y;
		float gx = (height_at(uv + vec2(px.x, 0.0)) - height_at(uv - vec2(px.x, 0.0))) / (2.0 * cell_x);
		float gy = (height_at(uv + vec2(0.0, px.y)) - height_at(uv - vec2(0.0, px.y))) / (2.0 * cell_y);
		float shade = clamp(0.8 + 2.2 * (gx + gy) * 0.7071, 0.25, 1.1);
		vec3 low = vec3(0.17, 0.25, 0.14);
		vec3 mid = vec3(0.4, 0.4, 0.27);
		vec3 high = vec3(0.5, 0.48, 0.44);
		vec3 base = mix(low, mid, smoothstep(-4.0, 22.0, h));
		base = mix(base, high, smoothstep(30.0, 60.0, h));
		COLOR = vec4(base * shade, 1.0);
	}
}
