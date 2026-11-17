class_name RoundShieldKind
extends RefCounted
## A round shield facing +Z, origin at the center. Params: `radius` (0.32), `role` face (wood),
## `rim` (iron), `boss` (iron), `wear`.

const DEFAULTS := {"radius": 0.32}


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var r: float = p["radius"]
	var sides := PropKit.sides(lod, 16)
	var parts: Array = []
	var rim := PackedVector2Array([Vector2(r * 1.03, -0.025), Vector2(r * 1.03, 0.025)])
	var rim_role := GearKit.role(p, "rim", &"iron")
	parts.append(GearKit.disc(palette, rng, look, p, rim_role, rim, sides, Vector3.ZERO))
	var face := PackedVector2Array([Vector2(r * 0.97, -0.02), Vector2(r * 0.97, 0.03)])
	var wood := GearKit.role(p, "role", &"wood")
	parts.append(GearKit.disc(palette, rng, look, p, wood, face, sides, Vector3.ZERO))
	var boss := PackedVector2Array(
		[Vector2(r * 0.3, 0.03), Vector2(r * 0.3, 0.06), Vector2(r * 0.14, 0.09)]
	)
	var boss_role := GearKit.role(p, "boss", &"iron")
	var round := PropKit.sides(lod, 8)
	parts.append(GearKit.disc(palette, rng, look, p, boss_role, boss, round, Vector3.ZERO))
	return PropKit.shaped(MeshKit.merge(parts), shape)
