class_name CrateKind
extends RefCounted
## A crate: a box of planks with corner posts. Origin: ground, center.

const NOMINAL := Vector3(0.8, 0.8, 0.8)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var s := NOMINAL.x
	var parts: Array = [
		PropKit.box(
			palette,
			rng,
			&"wood",
			Vector3(s - 0.1, s - 0.04, s - 0.1),
			Vector3(0, s * 0.5, 0),
			look,
			lod,
			0.02
		)
	]
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var post := Vector3(0.1, s, 0.1)
			var at := Vector3(x * (s - 0.1) * 0.5, s * 0.5, z * (s - 0.1) * 0.5)
			parts.append(PropKit.box(palette, rng, &"wood", post, at, look, lod, 0.01))
	return PropKit.shaped(MeshKit.merge(parts), shape)
