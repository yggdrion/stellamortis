class_name GrassKind
extends RefCounted
## Grass tufts (low, green) and tall grass (dry, higher): a few bent blades, wider at the base,
## one sided and facing outward, lighter toward the tip.

## Per id: width, height, depth in meters.
const NOMINAL := {
	"grass_tuft": Vector3(0.35, 0.35, 0.35),
	"grass_tall": Vector3(0.4, 0.9, 0.4),
}
const ROLE := {"grass_tuft": &"grass", "grass_tall": &"leaf_dry"}
## Blade width at the base.
const WIDTH := {"grass_tuft": 0.1, "grass_tall": 0.07}
const DRAWN := 6
## Per level (full, half, far): blades, and points per blade (3 points make 3 triangles, 2 make 1).
const BLADES: Array[int] = [4, 6, 6]
const POINTS: Array[int] = [3, 2, 2]


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, id: String) -> Array:
	var nominal: Vector3 = NOMINAL[id]
	var look := MeshKit.jitter(rng)
	var shared: Array = []
	for i in DRAWN:
		shared.append(
			[
				TAU * (i + rng.randf_range(0.0, 0.7)) / DRAWN,
				rng.randf_range(0.0, nominal.x * 0.15),
				nominal.y * rng.randf_range(0.65, 1.0),
				nominal.x * rng.randf_range(0.25, 0.5)
			]
		)
	var parts: Array = []
	var points := POINTS[lod]
	for i in BLADES[lod]:
		var angle: float = shared[i][0]
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var path := PackedVector3Array()
		for k in points:
			var t := float(k) / (points - 1)
			var reach: float = shared[i][1] + shared[i][3] * t * t
			path.append(out * reach + Vector3(0.0, shared[i][2] * t, 0.0))
		var facing := (out + Vector3.UP * 0.4).normalized()
		var across := Vector3(-out.z, 0.0, out.x)
		parts.append(MeshKit.blade(path, WIDTH[id], facing, false, across))
	return MeshKit.paint(MeshKit.merge(parts), palette.color(ROLE[id]), rng, Vector3.DOWN, look)
