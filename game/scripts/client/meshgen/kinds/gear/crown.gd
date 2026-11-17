class_name CrownKit
extends RefCounted
## A crown of spikes around a helm, for the `Head` bone. Params: `spikes` (7), `role` (iron),
## `wear`. A decoration: it covers nothing.

const DEFAULTS := {"spikes": 7}


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var count: int = p["spikes"]
	var metal := GearKit.role(p, "role", &"iron")
	var parts: Array = []
	for i in count:
		var angle := PI * (i / maxf(count - 1.0, 1.0) - 0.5) * 0.9
		var out := Vector3(sin(angle), 0.0, cos(angle))
		var height := 0.11 if i % 2 == 0 else 0.07
		var profile := PackedVector2Array([Vector2(0.018, 0.0), Vector2(0.0, height)])
		var spike := GearKit.turned(
			palette, rng, look, p, metal, profile, PropKit.sides(lod, 5), Vector3.ZERO
		)
		var lean := Basis.from_euler(Vector3(out.z * 0.3, 0.0, -out.x * 0.3))
		parts.append(GearKit.placed(spike, Vector3(0, 0.2, 0.01) + out * 0.11, lean))
	return PropKit.shaped(MeshKit.merge(parts), shape)
