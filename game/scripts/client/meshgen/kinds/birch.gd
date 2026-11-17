class_name BirchKind
extends RefCounted
## Birch: pale slender trunk, a few small leaf clumps high up on thin limbs.

## Per id: trunk radius above the root flare and height in meters.
const NOMINAL := {
	"birch_young": Vector2(0.08, 4.5),
	"birch_grown": Vector2(0.15, 9.5),
	"birch_old": Vector2(0.4, 17.0),
}
const FLARE: Array[float] = [1.0, 1.1, 1.35]
const CLUMPS: Array[Vector3i] = [Vector3i(3, 2, 1), Vector3i(5, 3, 2), Vector3i(7, 4, 3)]
const LIMBS: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(3, 2, 0), Vector3i(5, 3, 0)]
## Clump radius as a fraction of the height.
const CROWN: Array[float] = [0.09, 0.085, 0.085]
const DETAIL: Array[int] = [1, 0, 0]


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, age: int) -> Array:
	var a := TreeKit.axis(rng, NOMINAL["birch_" + TreeKit.AGES[age]], 0.25, FLARE[age], 6.0)
	var h := a.height
	var look := MeshKit.jitter(rng)
	var total := CLUMPS[age].x
	var centers := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in total:
		var t := (i + 0.5) / total
		var y := lerpf(0.55 * h, 0.93 * h, t) + rng.randf_range(-0.03, 0.03) * h
		var r := CROWN[age] * h * rng.randf_range(0.8, 1.2) * lerpf(1.0, 0.75, t)
		var angle := rng.randf_range(0.0, TAU)
		var off := r * rng.randf_range(0.5, 1.0) * (0.0 if i == total - 1 else 1.0)
		centers.append(a.pos(y) + Vector3(cos(angle) * off, r * 0.2, sin(angle) * off))
		radii.append(r)
	var pale: Array = [TreeKit.trunk(a, rng, lod, h * 0.97, TreeKit.POINTS[age][lod])]
	pale.append_array(TreeKit.ridges(a, rng, TreeKit.RIDGES[age][lod]))
	var dark: Array = []
	var leaves: Array = []
	for i in TreeKit.pick(total, CLUMPS[age][lod]):
		var c := centers[i]
		leaves.append(TreeKit.clump(rng, c, radii[i], DETAIL[lod], 0.8))
		if i < LIMBS[age][lod] and i < total - 1:
			var from := a.pos(maxf(c.y - radii[i] * 1.2, 0.5))
			var to := c - Vector3(0.0, radii[i] * 0.3, 0.0)
			dark.append(TreeKit.limb(from, to, a.radius(c.y) * 0.6, 0.0, lod, rng))
	var parts: Array = [
		TreeKit.painted(pale, &"bark_pale", palette, rng, look),
		TreeKit.painted(leaves, &"leaf", palette, rng, look),
	]
	if not dark.is_empty():
		parts.append(TreeKit.painted(dark, &"bark", palette, rng, look))
	return MeshKit.merge(parts)
