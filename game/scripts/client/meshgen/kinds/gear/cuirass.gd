class_name CuirassKit
extends RefCounted
## A breastplate or shirt for the `UpperChest` bone (origin mid chest, front toward +Z): a body
## box, `plates` lames below it and a collar. Params: `role` (iron), `trim` (leather), `plates`
## (3), `wear`. Covers the upper chest and spine.

const DEFAULTS := {"plates": 3}


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var metal := GearKit.role(p, "role", &"iron")
	var trim := GearKit.role(p, "trim", &"leather")
	var parts: Array = []
	var body := Vector3(0.36, 0.34, 0.22)
	parts.append(GearKit.box(palette, rng, look, p, metal, body, Vector3(0, -0.02, 0.0), lod))
	for i in int(p["plates"]):
		var lame := Vector3(0.34 - 0.01 * i, 0.04, 0.23)
		var at := Vector3(0, -0.21 - 0.045 * i, 0.0)
		parts.append(
			GearKit.box(palette, rng, look, p, trim if i % 2 == 1 else metal, lame, at, lod)
		)
	var collar := Vector3(0.2, 0.05, 0.16)
	parts.append(GearKit.box(palette, rng, look, p, trim, collar, Vector3(0, 0.17, 0.0), lod))
	return PropKit.shaped(MeshKit.merge(parts), shape)
