class_name PauldronsKit
extends RefCounted
## A pair of shoulder domes (spiked if `spikes`), for the `UpperChest` bone, mirrored about X.
## Params: `role` (iron), `spikes` (true), `size` (1.0), `wear`. Covers the upper arms.


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, params := {}) -> Array:
	var shape := PropKit.shape(rng)
	var look := MeshKit.jitter(rng)
	var size := float(params.get("size", 1.0))
	var metal := GearKit.role(params, "role", &"iron")
	var dome := PackedVector2Array(
		[Vector2(0.12, 0.0), Vector2(0.105, 0.05), Vector2(0.06, 0.1), Vector2(0.0, 0.12)]
	)
	for i in dome.size():
		dome[i] *= size
	var cap := PackedVector2Array([Vector2(0.0, 0.0)])
	cap.append_array(dome)
	var parts: Array = []
	for side: float in [-1.0, 1.0]:
		var shell := MeshKit.lathe(cap, PropKit.sides(lod, 10), 0.0, rng)
		var tilt := Basis(Vector3.BACK, -side * 0.35)
		var placed := GearKit.placed(shell, Vector3(side * 0.2, 0.1, 0.0), tilt)
		parts.append(GearKit.paint(placed, palette, metal, rng, look, params))
		if params.get("spikes", true):
			var cone := PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.0, 0.16)])
			var spike := GearKit.turned(
				palette, rng, look, params, metal, cone, PropKit.sides(lod, 6), Vector3.ZERO
			)
			var lean := Basis(Vector3.BACK, -side * 0.5)
			parts.append(GearKit.placed(spike, Vector3(side * 0.25, 0.2, 0.0), lean))
	return PropKit.shaped(MeshKit.merge(parts), shape)
