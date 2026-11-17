class_name HelmKit
extends RefCounted
## A rounded bascinet for the `Head` bone (origin at the neck, the face toward +Z): a dome on a
## short can, a dark eye slit and a nasal ridge. Params: `role` shell (steel), `nasal` (true),
## `crest` (false, a fin along the top), `wear`. Covers the head.


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var metal := GearKit.role(params, "role", &"steel")
	var sides := PropKit.sides(lod, 12)
	var shell := PackedVector2Array(
		[
			Vector2(0.14, -0.025),
			Vector2(0.14, 0.145),
			Vector2(0.125, 0.19),
			Vector2(0.075, 0.222),
			Vector2(0.0, 0.232),
		]
	)
	var parts: Array = []
	parts.append(
		GearKit.turned(palette, rng, look, params, metal, shell, sides, Vector3(0, 0, 0.01))
	)
	var slit := Vector3(0.19, 0.024, 0.03)
	parts.append(
		GearKit.box(palette, rng, look, params, &"iron", slit, Vector3(0, 0.1, 0.135), lod)
	)
	if params.get("nasal", true):
		var ridge := Vector3(0.022, 0.13, 0.025)
		parts.append(
			GearKit.box(palette, rng, look, params, metal, ridge, Vector3(0, 0.06, 0.148), lod)
		)
	if params.get("crest", false):
		var fin := Vector3(0.02, 0.05, 0.22)
		parts.append(
			GearKit.box(palette, rng, look, params, metal, fin, Vector3(0, 0.235, 0.01), lod)
		)
	return PropKit.shaped(MeshKit.merge(parts), shape)
