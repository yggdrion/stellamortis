class_name MoundKind
extends RefCounted
## A burial mound: a low turf dome with a few kerb stones on its rim. The dome follows the
## `ScatterShape` sphere (radius 6.4 m, center 4.6 m under the ground: 1.8 m high, 4.45 m across
## at the ground).

const SPHERE_RADIUS := 6.4
const SPHERE_CENTER := -4.6
## Ground width, height above the ground, ground depth.
const NOMINAL := Vector3(8.9, 1.8, 8.9)
const SINK := 0.4
const WOBBLE := 0.05
## Per level (full, half, far).
const SIDES: Array[int] = [14, 10, 8]
const RINGS: Array[int] = [8, 5, 3]
const STONES: Array[int] = [3, 1, 0]
## A kerb stone: size in meters, and where on the rim (fraction of the ground radius).
const STONE_SIZE := Vector3(1.0, 0.7, 0.8)
const STONE_REACH := 0.97


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var stones: Array = []
	var ground := _radius(0.0)
	for i in STONES[0]:
		var angle := rng.randf_range(0.0, TAU)
		var spot := Vector3(cos(angle), 0.0, sin(angle)) * ground * STONE_REACH
		stones.append([spot, rng.randi()])
	var profile := PackedVector2Array()
	for k in RINGS[lod]:
		var y := lerpf(-SINK, NOMINAL.y, float(k) / (RINGS[lod] - 1))
		profile.append(Vector2(_radius(y), y))
	var dome := MeshKit.lathe(profile, SIDES[lod], WOBBLE, rng, rng.randf_range(0.0, TAU))
	var parts: Array = [MeshKit.paint(dome, palette.color(&"moss"), rng, Vector3.DOWN, look)]
	for i in STONES[lod]:
		var stone_rng := RandomNumberGenerator.new()
		stone_rng.seed = stones[i][1]
		var at: Vector3 = stones[i][0] + Vector3(0.0, STONE_SIZE.y * 0.3, 0.0)
		var stone := RockKind.lump(stone_rng, STONE_SIZE, at, 0, [])
		parts.append(MeshKit.paint(stone, palette.color(&"stone"), rng, Vector3.DOWN, look))
	return MeshKit.merge(parts)


## The dome's radius at height y (0 at the top).
static func _radius(y: float) -> float:
	var d := y - SPHERE_CENTER
	return sqrt(maxf(0.0, SPHERE_RADIUS * SPHERE_RADIUS - d * d))
