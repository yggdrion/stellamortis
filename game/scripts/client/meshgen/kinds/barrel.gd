class_name BarrelKind
extends RefCounted
## A barrel: bulged staves with two iron hoops. Origin: ground, center.

const NOMINAL := Vector3(0.7, 0.9, 0.7)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var r := NOMINAL.x * 0.5
	var sides := PropKit.sides(lod, 10)
	var body := PackedVector2Array(
		[
			Vector2(r * 0.8, 0.0),
			Vector2(r * 0.95, 0.2),
			Vector2(r, 0.45),
			Vector2(r * 0.95, 0.7),
			Vector2(r * 0.8, NOMINAL.y),
		]
	)
	var parts: Array = [PropKit.turned(palette, rng, &"wood", body, sides, Vector3.ZERO, look)]
	for y in [0.2, 0.7]:
		var hoop := PackedVector2Array([Vector2(r * 0.97, y - 0.03), Vector2(r * 0.97, y + 0.03)])
		parts.append(PropKit.turned(palette, rng, &"iron", hoop, sides, Vector3.ZERO, look))
	return PropKit.shaped(MeshKit.merge(parts), shape)
