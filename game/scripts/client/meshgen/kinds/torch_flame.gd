class_name TorchFlameKind
extends RefCounted
## The flame of a torch, a brazier or a candle: a teardrop in the `ember` role (a meaning color:
## the caller gives it a material with `glow` set). Origin at its foot.

const NOMINAL := Vector3(0.14, 0.3, 0.14)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var profile := PackedVector2Array(
		[Vector2(0.06, 0.0), Vector2(0.07, 0.07), Vector2(0.05, 0.18), Vector2(0.02, 0.3)]
	)
	var flame := PropKit.turned(
		palette, rng, &"ember", profile, PropKit.sides(lod, 6), Vector3.ZERO, look
	)
	return PropKit.shaped(flame, shape)
