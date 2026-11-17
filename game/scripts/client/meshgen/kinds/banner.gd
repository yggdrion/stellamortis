class_name BannerKind
extends RefCounted
## A hanging banner: a pennant of cloth bent in a slow wave under a wooden bar, with a dark stripe
## for heraldry. Origin: ground, center; hangs in the XY plane facing +Z.

const NOMINAL := Vector3(0.9, 2.2, 0.1)


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int) -> Array:
	var look := MeshKit.jitter(rng)
	var bend := rng.randf_range(0.03, 0.05)
	var points := 6 if lod == Budgets.FULL else 3
	var path := PackedVector3Array()
	var raised := PackedVector3Array()
	for k in points:
		var t := float(k) / (points - 1)
		var p := Vector3(0.0, lerpf(2.05, 0.2, t), bend * sin(t * PI * 1.5))
		path.append(p)
		raised.append(p + Vector3(0, 0, 0.02))
	var cloth := MeshKit.blade(path, 0.8, Vector3.BACK, true)
	var stripe := MeshKit.blade(raised, 0.3, Vector3.BACK, true)
	var bar := MeshKit.tube(
		PackedVector3Array([Vector3(-0.45, 2.15, 0.0), Vector3(0.45, 2.15, 0.0)]),
		PackedFloat32Array([0.035, 0.035]),
		5 if lod == Budgets.FULL else 3,
		0.0,
		rng
	)
	return (
		MeshKit
		. merge(
			[
				MeshKit.paint(cloth, palette.color(&"cloth"), rng, Vector3.DOWN, look),
				MeshKit.paint(stripe, palette.color(&"cloth_dark"), rng, Vector3.DOWN, look),
				MeshKit.paint(bar, palette.color(&"wood"), rng, Vector3.DOWN, look),
			]
		)
	)
