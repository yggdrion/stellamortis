class_name PineYoungKind
extends RefCounted
## A young pine: a tube trunk and a stack of cones. Sample generator of M36; M37 replaces or
## extends it. Fewer sides and layers per level, no decimation.

const HEIGHT := 4.5
const RADIUS := 1.1
const TRUNK_RADIUS := 0.16
const CLEAR := 0.8
## Per level (full, half, far).
const TRUNK_SIDES: Array[int] = [8, 5, 3]
const TRUNK_POINTS: Array[int] = [4, 3, 2]
const CONE_SIDES: Array[int] = [10, 7, 5]
const LAYERS: Array[int] = [6, 4, 2]


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var height := HEIGHT * rng.randf_range(0.75, 1.25)
	var radius := RADIUS * rng.randf_range(0.8, 1.2)
	var look := MeshKit.jitter(rng)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in TRUNK_POINTS[lod]:
		var t := float(k) / (TRUNK_POINTS[lod] - 1)
		path.append(Vector3(0.0, height * 0.7 * t, 0.0))
		radii.append(TRUNK_RADIUS * (1.0 - 0.7 * t))
	var trunk := MeshKit.tube(path, radii, TRUNK_SIDES[lod], 0.1, rng)
	var layers := PackedVector3Array()
	for k in LAYERS[lod]:
		var t := float(k) / (LAYERS[lod] - 1)
		var base := lerpf(CLEAR, height * 0.6, t)
		layers.append(Vector3(base, radius * lerpf(1.0, 0.3, t), (height - base) * 0.5))
	var cones := MeshKit.cone_stack(layers, CONE_SIDES[lod], 0.12, rng)
	return (
		MeshKit
		. merge(
			[
				MeshKit.paint(trunk, palette.color(&"bark"), rng, Vector3.DOWN, look),
				MeshKit.paint(cones, palette.color(&"needle"), rng, Vector3.DOWN, look),
			]
		)
	)
