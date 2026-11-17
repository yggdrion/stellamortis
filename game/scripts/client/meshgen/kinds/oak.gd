class_name OakKind
extends RefCounted
## Oak: a short thick trunk, heavy limbs that reach out and up, a broad crown of leaf clumps.

## Per id: trunk radius above the root flare and total height in meters (the trunk itself is
## `TRUNK` of the height).
const NOMINAL := {
	"oak_young": Vector2(0.14, 3.8),
	"oak_grown": Vector2(0.38, 9.5),
	"oak_old": Vector2(0.75, 17.0),
}
const TRUNK := 0.44
const FLARE: Array[float] = [1.0, 1.15, 1.5]
const LIMBS: Array[Vector3i] = [Vector3i(2, 2, 0), Vector3i(4, 4, 0), Vector3i(5, 5, 0)]
## Clumps in order: one at each limb end, one on top, then one beside each limb.
const CLUMPS: Array[Vector3i] = [Vector3i(4, 3, 1), Vector3i(8, 5, 2), Vector3i(12, 7, 3)]
## Clump radius as a fraction of the total height.
const CLUMP_R := 0.2
const DETAIL: Array[int] = [1, 0, 0]


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, age: int) -> Array:
	var nominal: Vector2 = NOMINAL["oak_" + TreeKit.AGES[age]]
	var a := TreeKit.axis(rng, Vector2(nominal.x, nominal.y * TRUNK), 0.55, FLARE[age], 4.0)
	var total_h := a.height / TRUNK
	var look := MeshKit.jitter(rng)
	var limb_count := LIMBS[age].x
	var yaw := rng.randf_range(0.0, TAU)
	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	var ends_r := PackedFloat32Array()
	var sides := PackedVector3Array()
	for i in limb_count:
		var y := a.height * rng.randf_range(0.8, 1.0)
		var angle := yaw + i * 2.4 + rng.randf_range(-0.3, 0.3)
		var elev := deg_to_rad(rng.randf_range(35.0, 60.0))
		var length := total_h * rng.randf_range(0.4, 0.52)
		var dir := Vector3(cos(angle) * cos(elev), sin(elev), sin(angle) * cos(elev))
		var from := a.pos(y)
		starts.append(from)
		ends.append(from + dir * length)
		ends_r.append(CLUMP_R * total_h * rng.randf_range(0.85, 1.15))
		var side_angle := rng.randf_range(0.0, TAU)
		sides.append(Vector3(cos(side_angle), 0.5, sin(side_angle)))
	var wood: Array = [TreeKit.trunk(a, rng, lod, a.height, TreeKit.POINTS[age][lod])]
	wood.append_array(TreeKit.ridges(a, rng, TreeKit.RIDGES[age][lod]))
	var centers: Array[Vector3] = []
	var radii: Array[float] = []
	for i in limb_count:
		centers.append(ends[i] + Vector3(0.0, ends_r[i] * 0.2, 0.0))
		radii.append(ends_r[i])
	centers.append(a.pos(a.height) + Vector3(0.0, (total_h - a.height) * 0.85, 0.0))
	radii.append(CLUMP_R * total_h * 0.9)
	for i in limb_count:
		var mid: Vector3 = starts[i].lerp(ends[i], 0.6)
		centers.append(mid + sides[i] * ends_r[i] * Vector3(0.7, 1.0, 0.7))
		radii.append(ends_r[i] * 0.8)
	for i in mini(limb_count, LIMBS[age][lod]):
		var r0 := a.radius(starts[i].y)
		wood.append(TreeKit.limb(starts[i], ends[i], r0 * 0.75, r0 * 0.25, lod, rng, 0.1))
	var leaves: Array = []
	for i in mini(CLUMPS[age][lod], centers.size()):
		leaves.append(TreeKit.clump(rng, centers[i], radii[i], DETAIL[lod], 0.7))
	return (
		MeshKit
		. merge(
			[
				TreeKit.painted(wood, &"bark", palette, rng, look),
				TreeKit.painted(leaves, &"leaf", palette, rng, look),
			]
		)
	)
