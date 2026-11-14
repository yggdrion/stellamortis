class_name HitEffects
extends RefCounted
## What a hit looks like besides the pose (PLAN §3.2, M19): one-shot particle bursts from a small
## pool, and the numbers views use for hit stop and camera shake. Views call these when they see
## a hit in the state, never the sim. Headless processes draw nothing.

enum Kind { BLOOD, SPARKS, WOOD }

## Damage that counts as a full-strength hit (a heavy swing).
const HEAVY := 50.0
## Hit stop: how long a view holds its pose, seconds, for a hit of damage 0 and of HEAVY.
const STOP_MIN := 0.035
const STOP_MAX := 0.085
## Camera shake (0..1 of CameraRig's trauma) for a hit of HEAVY.
const SHAKE_HEAVY := 0.5
## Particles in one burst at HIGH graphics, per kind; the preset scales them.
const COUNT := {Kind.BLOOD: 24, Kind.SPARKS: 18, Kind.WOOD: 10}
const COUNT_SCALE := [0.4, 0.7, 1.0, 1.5]
## Per kind: lifetime (s), speed min and max (m/s), gravity (m/s^2), size (m), color.
const LOOK := {
	Kind.BLOOD: [0.55, 2.0, 5.0, 9.0, 0.1, Color(0.5, 0.02, 0.02)],
	Kind.SPARKS: [0.35, 3.0, 8.0, 6.0, 0.04, Color(1.0, 0.75, 0.3)],
	Kind.WOOD: [0.5, 1.5, 4.0, 9.0, 0.06, Color(0.45, 0.28, 0.14)],
}
const POOL := 6

static var _pool := {}
static var _next := {}


## 0 for a scratch, 1 for a heavy hit, more for more.
static func weight(damage: float) -> float:
	return damage / HEAVY


static func stop_time(damage: float) -> float:
	return lerpf(STOP_MIN, STOP_MAX, clampf(weight(damage), 0.0, 1.0))


static func shake_strength(damage: float) -> float:
	return clampf(weight(damage), 0.15, 1.0) * SHAKE_HEAVY


## A burst of kind at a world point, thrown along normal. `from` is any node in the tree.
static func burst(from: Node, at: Vector3, normal: Vector3, kind: Kind) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var particles := _take(from, kind)
	var look: Array = LOOK[kind]
	var material := particles.process_material as ParticleProcessMaterial
	material.direction = normal.normalized()
	material.gravity = Gravity.sample(at).normalized() * look[3]
	particles.amount = maxi(1, roundi(COUNT[kind] * COUNT_SCALE[Graphics.preset]))
	particles.global_position = at
	particles.restart()
	particles.emitting = true


static func _take(from: Node, kind: Kind) -> GPUParticles3D:
	var list: Array = _pool.get(kind, [])
	var index: int = _next.get(kind, 0)
	if list.size() <= index:
		list.resize(POOL)
		_pool[kind] = list
	var particles := list[index] as GPUParticles3D
	if not is_instance_valid(particles):
		particles = _make(kind)
		list[index] = particles
	_next[kind] = (index + 1) % POOL
	if not particles.is_inside_tree():
		from.get_tree().root.add_child(particles)
	return particles


static func _make(kind: Kind) -> GPUParticles3D:
	var look: Array = LOOK[kind]
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.explosiveness = 1.0
	particles.lifetime = look[0]
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.spread = 35.0
	process.initial_velocity_min = look[1]
	process.initial_velocity_max = look[2]
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(1, 0))
	var curve := CurveTexture.new()
	curve.curve = fade
	process.scale_curve = curve
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * look[4]
	var color: Color = look[5]
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	paint.albedo_color = color
	if kind == Kind.SPARKS:
		paint.emission_enabled = true
		paint.emission = color
		paint.emission_energy_multiplier = 6.0
	quad.material = paint
	particles.draw_pass_1 = quad
	return particles
