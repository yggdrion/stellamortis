class_name GreatswordKind
extends RefCounted
## A two handed sword (about 1.5 m with its hilt, docs/STYLE.md section 7): `SwordKind` with a
## long blade, a broad guard and a long grip.

const DEFAULTS := {"length": 1.2, "width": 0.085, "guard": 0.34, "grip": 0.3, "pommel": "disc"}


static func total(params: Dictionary) -> float:
	return SwordKind.total(_merged(params))


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	return SwordKind.build(rng, palette, lod, _merged(params))


static func _merged(params: Dictionary) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	return p
