class_name BushKind
extends RefCounted
## A bush: a few leaf masses piled together. `cluster` is also the heather's and pebbles' shape.

## Width, height, depth in meters.
const NOMINAL := Vector3(1.4, 1.1, 1.4)
const ROLES: Array[StringName] = [&"leaf", &"leaf", &"leaf_dry"]
## Masses per level (full, half, far).
const COUNTS := Vector3i(3, 1, 1)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	return cluster(rng, palette, lod, NOMINAL, ROLES, COUNTS)


## Blobs of the given roles (the first is the biggest, in the middle) heaped into `nominal`'s
## box, `counts` of them per level. Every blob is drawn for every level.
static func cluster(
	rng: RandomNumberGenerator,
	palette: Palette,
	lod: int,
	nominal: Vector3,
	roles: Array[StringName],
	counts: Vector3i
) -> Array:
	var look := MeshKit.jitter(rng)
	var blobs: Array = []
	for i in roles.size():
		var angle := rng.randf_range(0.0, TAU)
		var spread := 0.0 if i == 0 else nominal.x * rng.randf_range(0.18, 0.3)
		var width := nominal.x * (0.62 if i == 0 else 0.5) * rng.randf_range(0.85, 1.15)
		var height := nominal.y * (1.0 if i == 0 else 0.8) * rng.randf_range(0.85, 1.0)
		var whole := height / (1.0 - RockKind.SINK)
		var at := Vector3(cos(angle) * spread, whole * (0.5 - RockKind.SINK), sin(angle) * spread)
		blobs.append([Vector3(width, whole, width), at, rng.randi()])
	var parts: Array = []
	for i in counts[lod]:
		var blob_rng := RandomNumberGenerator.new()
		blob_rng.seed = blobs[i][2]
		var mass := RockKind.lump(blob_rng, blobs[i][0], blobs[i][1], 0, [])
		parts.append(MeshKit.paint(mass, palette.color(roles[i]), rng, Vector3.DOWN, look))
	return MeshKit.merge(parts)
