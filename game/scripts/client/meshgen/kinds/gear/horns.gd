class_name HornsKit
extends RefCounted
## Two horns curving up and out of a helm, for the `Head` bone. Params: `size` (1.0), `role`
## (bone), `wear`. A decoration: it covers nothing.

const DEFAULTS := {"size": 1.0}


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var size: float = p["size"]
	var sides := 6 if lod == Budgets.FULL else 4
	var radii := PackedFloat32Array([0.045, 0.036, 0.026, 0.0])
	for i in radii.size():
		radii[i] *= size
	var parts: Array = []
	for side: float in [-1.0, 1.0]:
		var path := PackedVector3Array(
			[
				Vector3(0.12, 0.16, 0.0),
				Vector3(0.19, 0.19, -0.02),
				Vector3(0.25, 0.28, -0.04),
				Vector3(0.26, 0.4, -0.05),
			]
		)
		for k in path.size():
			var at := path[k]
			var from := Vector3(0.12, 0.16, 0.0)
			path[k] = Vector3(
				side * (from.x + (at.x - from.x) * size),
				from.y + (at.y - from.y) * size,
				at.z * size
			)
		var horn := MeshKit.tube(path, radii, sides, 0.0, rng)
		parts.append(GearKit.paint(horn, palette, GearKit.role(p, "role", &"bone"), rng, look, p))
	return PropKit.shaped(MeshKit.merge(parts), shape)
