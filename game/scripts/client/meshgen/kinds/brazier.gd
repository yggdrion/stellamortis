class_name BrazierKind
extends RefCounted
## An iron fire bowl on three legs; the flame is a `torch_flame` the caller adds in the bowl.
## Origin: ground, center.

const NOMINAL := Vector3(0.9, 1.1, 0.9)
## Where the flame's foot sits.
const FLAME_AT := Vector3(0.0, 1.0, 0.0)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var sides := PropKit.sides(lod, 10)
	var bowl := PackedVector2Array(
		[Vector2(0.12, 0.62), Vector2(0.3, 0.68), Vector2(0.42, 0.9), Vector2(0.45, 1.05)]
	)
	var parts: Array = [PropKit.turned(palette, rng, &"iron", bowl, sides, Vector3.ZERO, look)]
	var coals := PackedVector2Array([Vector2(0.38, 0.96), Vector2(0.4, 1.0)])
	if lod < Budgets.FAR:
		parts.append(PropKit.turned(palette, rng, &"stone_dark", coals, sides, Vector3.ZERO, look))
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		var out := Vector3(cos(a), 0.0, sin(a))
		var path := PackedVector3Array([out * 0.38, out * 0.15 + Vector3(0, 0.72, 0)])
		var leg_sides: int = [5, 4, 3][lod]
		var leg := MeshKit.tube(path, PackedFloat32Array([0.045, 0.05]), leg_sides, 0.0, rng)
		parts.append(MeshKit.paint(leg, palette.color(&"iron"), rng, Vector3.DOWN, look))
	return PropKit.shaped(MeshKit.merge(parts), shape)
