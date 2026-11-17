class_name TowerShieldKind
extends RefCounted
## A tall plank shield bound in iron with a boss, facing +Z, origin at the center. Params:
## `height` (1.0), `width` (0.5), `role` planks (wood), `rim` (iron), `wear`.

const DEFAULTS := {"height": 1.0, "width": 0.5}


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var h: float = p["height"]
	var w: float = p["width"]
	var parts: Array = []
	var iron := GearKit.role(p, "rim", &"iron")
	var wood := GearKit.role(p, "role", &"wood")
	parts.append(GearKit.box(palette, rng, look, p, wood, Vector3(w, h, 0.04), Vector3.ZERO, lod))
	for y: float in [-0.47, 0.47]:
		var band := Vector3(w * 1.08, 0.05, 0.06)
		parts.append(GearKit.box(palette, rng, look, p, iron, band, Vector3(0, y * h, 0), lod))
	for x: float in [-0.5, 0.5]:
		var strap := Vector3(0.04, h * 1.04, 0.06)
		parts.append(GearKit.box(palette, rng, look, p, iron, strap, Vector3(x * w, 0, 0), lod))
	var boss := PackedVector2Array([Vector2(0.09, 0.03), Vector2(0.09, 0.05), Vector2(0.04, 0.09)])
	var at := Vector3(0, h * 0.1, 0)
	parts.append(GearKit.disc(palette, rng, look, p, iron, boss, PropKit.sides(lod, 8), at))
	return PropKit.shaped(MeshKit.merge(parts), shape)
