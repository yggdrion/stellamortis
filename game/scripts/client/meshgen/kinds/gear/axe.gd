class_name AxeKind
extends RefCounted
## A single or double bitted axe, origin at the grip (a third up the haft), haft along +Y, the
## edge toward +X. Params: `haft` (0.8), `head` (0.2, how far the bit reaches), `double` (false),
## `role` for the head (steel), `haft_role` (wood), `wear`.

const DEFAULTS := {"haft": 0.8, "head": 0.2, "double": false}


## How far the head is from the grip.
static func total(params: Dictionary) -> float:
	var p := _merged(params)
	return float(p["haft"]) * 0.7 + 0.02


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var p := _merged(params)
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var haft: float = p["haft"]
	var reach: float = p["head"]
	var parts: Array = []
	var top := haft * 0.7
	var path := PackedVector3Array([Vector3(0, -haft * 0.3, 0), Vector3(0, top, 0)])
	var sides := PropKit.sides(lod, 6)
	var shaft := MeshKit.tube(path, PackedFloat32Array([0.022, 0.018]), sides, 0.0, rng)
	var wood := GearKit.role(p, "haft_role", &"wood")
	parts.append(GearKit.paint(shaft, palette, wood, rng, look, p))
	var bit := PackedVector2Array(
		[
			Vector2(0.0, -0.1),
			Vector2(reach * 0.8, -0.14),
			Vector2(reach, -0.02),
			Vector2(reach, 0.1),
			Vector2(reach * 0.8, 0.18),
			Vector2(0.0, 0.08),
		]
	)
	var metal := GearKit.role(p, "role", &"steel")
	for side in 2 if p["double"] else 1:
		var shaped := bit
		if side == 1:
			shaped = PackedVector2Array()
			for v in bit:
				shaped.append(Vector2(-v.x, v.y))
		var at := Vector3(0, top - 0.06, 0)
		parts.append(GearKit.prism(palette, rng, look, p, metal, shaped, 0.03, at, lod))
	var cap := Vector3(0.05, 0.05, 0.05)
	parts.append(GearKit.box(palette, rng, look, p, metal, cap, Vector3(0, top, 0), lod))
	return PropKit.shaped(MeshKit.merge(parts), shape)


static func _merged(params: Dictionary) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	return p
