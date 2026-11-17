class_name GreavesKit
extends RefCounted
## A shin guard for one leg, for a `LowerLeg` bone (origin at the knee, the shin hangs along -Y,
## the front is +Z): a plate, a knee cap and a strap. Params: `side` ("Left" or "Right", only for
## `GearKit.covers`), `role` (leather), `trim` (iron), `wear`. Covers that lower leg.


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var plate := GearKit.role(params, "role", &"leather")
	var trim := GearKit.role(params, "trim", &"iron")
	var parts: Array = []
	var shin := Vector3(0.11, 0.38, 0.12)
	parts.append(GearKit.box(palette, rng, look, params, plate, shin, Vector3(0, -0.22, 0.01), lod))
	var cap := Vector3(0.13, 0.08, 0.1)
	parts.append(GearKit.box(palette, rng, look, params, trim, cap, Vector3(0, -0.01, 0.04), lod))
	var strap := Vector3(0.125, 0.03, 0.135)
	parts.append(GearKit.box(palette, rng, look, params, trim, strap, Vector3(0, -0.3, 0.01), lod))
	return PropKit.shaped(MeshKit.merge(parts), shape)
