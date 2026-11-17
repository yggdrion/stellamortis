class_name FernKind
extends RefCounted
## A fern: a rosette of arching fronds, wider at the base, one sided facing up.

## Width, height, depth in meters.
const NOMINAL := Vector3(1.2, 0.6, 1.2)
const FRONDS := 8
const WIDTH := 0.16
## Per level (full, half, far): points per frond (5 points make 7 triangles, 3 make 3).
const POINTS: Array[int] = [5, 3, 3]


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var fronds: Array = []
	for i in FRONDS:
		fronds.append(
			[
				TAU * (i + rng.randf_range(0.0, 0.6)) / FRONDS,
				NOMINAL.x * 0.5 * rng.randf_range(0.7, 1.0),
				NOMINAL.y * rng.randf_range(0.7, 1.0)
			]
		)
	var parts: Array = []
	for f: Array in fronds:
		var out := Vector3(cos(f[0] as float), 0.0, sin(f[0] as float))
		var path := PackedVector3Array()
		for k in POINTS[lod]:
			var t := float(k) / (POINTS[lod] - 1)
			path.append(out * (0.04 + f[1] * t) + Vector3(0.0, f[2] * sin(t * 1.9) / 0.95, 0.0))
		parts.append(MeshKit.blade(path, WIDTH, Vector3.UP, false, Vector3(-out.z, 0.0, out.x)))
	return MeshKit.paint(MeshKit.merge(parts), palette.color(&"leaf"), rng, Vector3.DOWN, look)
