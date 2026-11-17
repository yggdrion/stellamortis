class_name KiteShieldKind
extends RefCounted
## A kite shield facing +Z, origin at the center. Params: `height` (1.0), `width` (0.46),
## `role` face (wood), `rim` (iron), `wear`.

const DEFAULTS := {"height": 1.0, "width": 0.46}


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var h: float = p["height"]
	var w: float = float(p["width"]) * 0.5
	var outline := PackedVector2Array(
		[
			Vector2(-w, h * 0.45),
			Vector2(w, h * 0.45),
			Vector2(w * 1.05, h * 0.1),
			Vector2(0, -h * 0.55),
			Vector2(-w * 1.05, h * 0.1),
		]
	)
	var wide := PackedVector2Array()
	for v in outline:
		wide.append(v * 1.07)
	var parts: Array = []
	var rim := GearKit.role(p, "rim", &"iron")
	parts.append(GearKit.prism(palette, rng, look, p, rim, wide, 0.03, Vector3.ZERO, lod))
	var wood := GearKit.role(p, "role", &"wood")
	parts.append(GearKit.prism(palette, rng, look, p, wood, outline, 0.045, Vector3.ZERO, lod))
	var band := Vector3(w * 1.9, 0.05, 0.06)
	parts.append(GearKit.box(palette, rng, look, p, rim, band, Vector3(0, h * 0.18, 0), lod))
	var spine := Vector3(0.05, h * 0.95, 0.06)
	parts.append(GearKit.box(palette, rng, look, p, rim, spine, Vector3(0, -h * 0.03, 0), lod))
	return PropKit.shaped(MeshKit.merge(parts), shape)
