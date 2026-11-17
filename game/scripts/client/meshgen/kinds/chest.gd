class_name ChestKind
extends RefCounted
## A wooden chest with iron bands: `build` is the body (feet on the ground, centered), `lid` the
## lid with its hinge at the origin (the back lower edge): it spans +Z and rises, so a view turns
## it about X, placed at `HINGE` on the body.

const NOMINAL := Vector3(1.0, 0.55, 0.65)
const BODY_HEIGHT := 0.35
const HINGE := Vector3(0.0, BODY_HEIGHT, -0.325)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var size := Vector3(NOMINAL.x, BODY_HEIGHT, NOMINAL.z)
	var parts: Array = [
		PropKit.box(palette, rng, &"wood", size, Vector3(0, size.y * 0.5, 0), look, lod, 0.02)
	]
	for x in [-0.34, 0.34]:
		var band := Vector3(0.07, size.y + 0.02, size.z + 0.04)
		parts.append(
			PropKit.box(palette, rng, &"iron", band, Vector3(x, size.y * 0.5, 0), look, lod, 0.01)
		)
	return PropKit.shaped(MeshKit.merge(parts), shape)


static func lid(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var shape := PropKit.shape(rng)
	var d := NOMINAL.z
	var h := NOMINAL.y - BODY_HEIGHT
	var parts: Array = [
		PropKit.box(
			palette,
			rng,
			&"wood",
			Vector3(NOMINAL.x, h * 0.6, d),
			Vector3(0, h * 0.3, d * 0.5),
			look,
			lod,
			0.02
		),
		PropKit.box(
			palette,
			rng,
			&"wood",
			Vector3(NOMINAL.x - 0.1, h * 0.4, d - 0.12),
			Vector3(0, h * 0.8, d * 0.5),
			look,
			lod,
			0.03
		),
	]
	for x in [-0.34, 0.34]:
		parts.append(
			PropKit.box(
				palette,
				rng,
				&"iron",
				Vector3(0.07, h * 0.5, d + 0.04),
				Vector3(x, h * 0.55, d * 0.5),
				look,
				lod,
				0.01
			)
		)
	return PropKit.shaped(MeshKit.merge(parts), shape)
