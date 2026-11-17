class_name WeaponStandKind
extends RefCounted
## A rack with two rails and shafts leaning in it. Origin: ground, center, rails along X.

const NOMINAL := Vector3(1.2, 1.4, 0.5)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var parts: Array = []
	for x in [-0.55, 0.55]:
		var post := Vector3(0.08, 1.3, 0.08)
		parts.append(PropKit.box(palette, rng, &"wood", post, Vector3(x, 0.65, 0), look, lod, 0.0))
		var foot := Vector3(0.08, 0.08, 0.5)
		parts.append(PropKit.box(palette, rng, &"wood", foot, Vector3(x, 0.04, 0), look, lod, 0.0))
	var bar := Vector3(1.2, 0.08, 0.08)
	parts.append(PropKit.box(palette, rng, &"wood", bar, Vector3(0, 1.36, 0), look, lod, 0.0))
	for y in [0.45, 0.9]:
		var rail := Vector3(1.1, 0.06, 0.06)
		parts.append(PropKit.box(palette, rng, &"wood", rail, Vector3(0, y, 0.06), look, lod, 0.0))
	var shafts := 3 if lod == Budgets.FULL else 2
	for i in shafts:
		var x := -0.25 + 0.25 * i
		var path := PackedVector3Array([Vector3(x, 0.08, 0.17), Vector3(x + 0.04, 1.3, 0.1)])
		var sides := 5 if lod == Budgets.FULL else 3
		var shaft := MeshKit.tube(path, PackedFloat32Array([0.025, 0.02]), sides, 0.0, rng)
		var role := &"steel" if i == 1 else &"wood"
		parts.append(MeshKit.paint(shaft, palette.color(role), rng, Vector3.DOWN, look))
	return PropKit.shaped(MeshKit.merge(parts), shape)
