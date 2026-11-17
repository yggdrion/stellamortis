class_name DeadTreeKind
extends RefCounted
## Dead tree: a snapped trunk and bare limbs, with twigs on the older ones. No leaves.

## Per id: trunk radius above the root flare and height in meters.
const NOMINAL := {
	"dead_tree_young": Vector2(0.1, 3.5),
	"dead_tree_grown": Vector2(0.26, 9.5),
	"dead_tree_old": Vector2(0.55, 17.0),
}
const FLARE: Array[float] = [1.0, 1.1, 1.4]
const LIMBS: Array[Vector3i] = [Vector3i(2, 2, 1), Vector3i(5, 4, 2), Vector3i(8, 6, 3)]
const TWIGS: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(2, 2, 0), Vector3i(5, 3, 0)]


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, age: int) -> Array:
	var a := TreeKit.axis(rng, NOMINAL["dead_tree_" + TreeKit.AGES[age]], 0.3, FLARE[age], 6.0)
	var h := a.height
	var look := MeshKit.jitter(rng)
	var total := LIMBS[age].x
	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	var starts_r := PackedFloat32Array()
	var twig_dirs := PackedVector3Array()
	var yaw := rng.randf_range(0.0, TAU)
	for i in total:
		var t := (i + 0.5) / total
		var y := lerpf(0.3, 0.88, t) * h * rng.randf_range(0.92, 1.08)
		var angle := yaw + i * 2.4 + rng.randf_range(-0.3, 0.3)
		var elev := deg_to_rad(rng.randf_range(10.0, 50.0))
		var length := h * rng.randf_range(0.14, 0.3) * (1.0 - 0.5 * t)
		var dir := Vector3(cos(angle) * cos(elev), sin(elev), sin(angle) * cos(elev))
		starts.append(a.pos(y))
		starts_r.append(a.radius(y) * 0.55)
		ends.append(a.pos(y) + dir * length)
		var twig := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.4, 1.0), 0.0)
		twig.z = rng.randf_range(-1.0, 1.0)
		twig_dirs.append(twig.normalized())
	var trunk: Array = [TreeKit.trunk(a, rng, lod, h * 0.92, TreeKit.POINTS[age][lod])]
	trunk.append_array(TreeKit.ridges(a, rng, TreeKit.RIDGES[age][lod]))
	var limbs: Array = []
	for i in TreeKit.pick(total, LIMBS[age][lod]):
		limbs.append(TreeKit.limb(starts[i], ends[i], starts_r[i], 0.0, lod, rng, 0.08))
		if i < TWIGS[age][lod]:
			var base := starts[i].lerp(ends[i], 0.55)
			var twig := base + twig_dirs[i] * starts[i].distance_to(ends[i]) * 0.45
			limbs.append(TreeKit.limb(base, twig, starts_r[i] * 0.5, 0.0, lod, rng, 0.05))
	return (
		MeshKit
		. merge(
			[
				TreeKit.painted(trunk, &"bark", palette, rng, look),
				TreeKit.painted(limbs, &"wood", palette, rng, look),
			]
		)
	)
