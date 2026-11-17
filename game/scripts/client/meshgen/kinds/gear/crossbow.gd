class_name CrossbowKind
extends RefCounted
## A crossbow, origin at the grip, stock along +Y, bow across its front. Params: `stock` (0.62),
## `span` (0.6, bow width), `role` bow metal (steel), `stock_role` (wood), `wear`.

const DEFAULTS := {"stock": 0.62, "span": 0.6}


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var stock: float = p["stock"]
	var span: float = p["span"]
	var parts: Array = []
	var wood := GearKit.role(p, "stock_role", &"wood")
	var body := Vector3(0.05, stock, 0.06)
	parts.append(
		GearKit.box(palette, rng, look, p, wood, body, Vector3(0, stock * 0.32, 0.02), lod)
	)
	var metal := GearKit.role(p, "role", &"steel")
	var front := stock * 0.74
	for side: float in [-1.0, 1.0]:
		var limb := Vector3(span * 0.5, 0.025, 0.03)
		var tilt := Basis(Vector3.BACK, side * -0.25)
		var at := Vector3(side * span * 0.25, front, 0.03)
		parts.append(GearKit.box(palette, rng, look, p, metal, limb, at, lod, tilt))
	var string := Vector3(span * 0.96, 0.008, 0.008)
	var pulled := Vector3(0, front - 0.08, 0.03)
	parts.append(GearKit.box(palette, rng, look, p, &"iron", string, pulled, lod))
	return PropKit.shaped(MeshKit.merge(parts), shape)
