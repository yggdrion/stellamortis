class_name TorchKind
extends RefCounted
## A wall torch: an iron plate at the origin, an arm reaching out along +Z, a wooden stick and an
## iron basket. The flame is its own kind (`torch_flame`) so it can glow and flicker.

const NOMINAL := Vector3(0.3, 1.1, 0.5)
## Where the flame's foot sits (the basket's middle).
const FLAME_AT := Vector3(0.0, 0.85, 0.3)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var sides := PropKit.sides(lod, 8)
	var parts: Array = [
		PropKit.box(
			palette, rng, &"iron", Vector3(0.16, 0.3, 0.04), Vector3(0, 0, 0.02), look, lod, 0.01
		)
	]
	var arm := MeshKit.tube(
		PackedVector3Array([Vector3(0, 0, 0.03), Vector3(0, 0.12, 0.3)]),
		PackedFloat32Array([0.03, 0.03]),
		4,
		0.0,
		rng
	)
	parts.append(MeshKit.paint(arm, palette.color(&"iron"), rng, Vector3.DOWN, look))
	var stick := PackedVector2Array([Vector2(0.04, 0.1), Vector2(0.045, 0.75)])
	parts.append(PropKit.turned(palette, rng, &"wood", stick, sides, Vector3(0, 0, 0.3), look))
	var basket := PackedVector2Array([Vector2(0.05, 0.7), Vector2(0.12, 0.95)])
	parts.append(PropKit.turned(palette, rng, &"iron", basket, sides, Vector3(0, 0, 0.3), look))
	return PropKit.shaped(MeshKit.merge(parts), shape)
