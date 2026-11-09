shader_type spatial;
// The Warden's gravity well (PLAN §4.6): a glowing shell with bands sliding inward, seen from
// inside and outside. strength fades it in and out.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.55, 0.2, 1.0);

void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float bands = 0.5 + 0.5 * sin(UV.y * 60.0 + TIME * 7.0 + sin(UV.x * 18.0) * 1.5);
	ALBEDO = tint * (rim * 1.6 + bands * 0.12) * strength;
}
