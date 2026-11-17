class_name CauldronKind
extends RefCounted
## An iron cauldron on three short legs with a bail handle and a dark brew. Origin: ground, center.

const NOMINAL := Vector3(1.0, 0.9, 1.0)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var sides := PropKit.sides(lod, 10)
	var pot := PackedVector2Array(
		[Vector2(0.3, 0.15), Vector2(0.48, 0.4), Vector2(0.5, 0.55), Vector2(0.44, 0.7)]
	)
	var brew := PackedVector2Array([Vector2(0.4, 0.64), Vector2(0.4, 0.66)])
	var parts: Array = [
		PropKit.turned(palette, rng, &"iron", pot, sides, Vector3.ZERO, look),
		PropKit.turned(palette, rng, &"stone_dark", brew, sides, Vector3.ZERO, look),
	]
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var at := Vector3(cos(a) * 0.3, 0.08, sin(a) * 0.3)
		parts.append(
			PropKit.box(palette, rng, &"iron", Vector3(0.09, 0.16, 0.09), at, look, lod, 0.0)
		)
	var arc := PackedVector3Array()
	var radii := PackedFloat32Array()
	var points := 5 if lod == Budgets.FULL else 3
	for k in points:
		var t := float(k) / (points - 1)
		arc.append(Vector3(lerpf(-0.45, 0.45, t), 0.7 + 0.2 * sin(PI * t), 0.0))
		radii.append(0.025)
	var bail := MeshKit.tube(arc, radii, 4, 0.0, rng)
	parts.append(MeshKit.paint(bail, palette.color(&"iron"), rng, Vector3.DOWN, look))
	return PropKit.shaped(MeshKit.merge(parts), shape)
