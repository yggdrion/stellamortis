class_name AnvilKind
extends RefCounted
## An anvil on a wooden stump, horn toward +Z. Origin: ground, center of the stump.

const NOMINAL := Vector3(0.5, 0.8, 0.9)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var stump := PackedVector2Array([Vector2(0.25, 0.0), Vector2(0.22, 0.45)])
	var parts: Array = [
		PropKit.turned(palette, rng, &"wood", stump, PropKit.sides(lod, 8), Vector3.ZERO, look),
		PropKit.box(
			palette, rng, &"iron", Vector3(0.3, 0.1, 0.45), Vector3(0, 0.5, 0), look, lod, 0.01
		),
		PropKit.box(
			palette, rng, &"iron", Vector3(0.2, 0.15, 0.3), Vector3(0, 0.62, 0), look, lod, 0.01
		),
		PropKit.box(
			palette, rng, &"steel", Vector3(0.34, 0.1, 0.7), Vector3(0, 0.75, 0), look, lod, 0.01
		),
		PropKit.box(
			palette, rng, &"iron", Vector3(0.2, 0.08, 0.2), Vector3(0, 0.74, -0.4), look, lod, 0.0
		),
	]
	var horn := MeshKit.tube(
		PackedVector3Array([Vector3(0, 0.75, 0.3), Vector3(0, 0.75, 0.45)]),
		PackedFloat32Array([0.07, 0.015]),
		4,
		0.0,
		rng
	)
	parts.append(MeshKit.paint(horn, palette.color(&"steel"), rng, Vector3.DOWN, look))
	return PropKit.shaped(MeshKit.merge(parts), shape)
