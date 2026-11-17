class_name CapeKit
extends RefCounted
## A tattered cape hanging from the shoulders, for the `UpperChest` bone: strips of uneven
## length, so it reads ragged. Params: `strips` (7), `length` (1.0), `role` (cloth_dark), `wear`.
## Hangs behind the body: it covers nothing.

const DEFAULTS := {"strips": 7, "length": 1.0}


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var count: int = p["strips"]
	var cloth := GearKit.role(p, "role", &"cloth_dark")
	var lean := Basis(Vector3.RIGHT, 0.12)
	var parts: Array = []
	for i in count:
		var length := float(p["length"]) * rng.randf_range(0.8, 1.2)
		var x := (i - (count - 1) / 2.0) * 0.075
		var size := Vector3(0.08, length, 0.012)
		var at := Vector3(x, 0.12 - length / 2.0, -0.17)
		parts.append(GearKit.box(palette, rng, look, p, cloth, size, at, lod, lean))
	return PropKit.shaped(MeshKit.merge(parts), shape)
