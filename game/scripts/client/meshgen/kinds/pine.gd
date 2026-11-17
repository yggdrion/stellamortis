class_name PineKind
extends RefCounted
## Pine: bare trunk, layered needle masses high up. Young: a cone stack. Grown and old: flat
## needle pads on limbs, a pad on top.

## Per id: trunk radius above the root flare and height in meters (what the scatter shape and the
## view read; heights vary by 12 % per variant).
const NOMINAL := {
	"pine_young": Vector2(0.12, 4.5),
	"pine_grown": Vector2(0.28, 11.0),
	"pine_old": Vector2(0.5, 20.0),
}
const FLARE: Array[float] = [1.0, 1.15, 1.45]
## Bare trunk as a fraction of the height.
const BARE: Array[float] = [0.22, 0.5, 0.55]
## Young: cone layers. Grown and old: pads (per level).
const MASSES: Array[Vector3i] = [Vector3i(6, 4, 2), Vector3i(4, 3, 2), Vector3i(7, 5, 3)]
## Crown radius as a fraction of the height.
const CROWN: Array[float] = [0.25, 0.16, 0.17]
const CONE_SIDES: Array[int] = [10, 7, 5]
const PAD_DETAIL: Array[int] = [1, 0, 0]


static func build(rng: RandomNumberGenerator, palette: Palette, lod: int, age: int) -> Array:
	var a := TreeKit.axis(rng, NOMINAL["pine_" + TreeKit.AGES[age]], 0.3, FLARE[age], 6.0)
	var h := a.height
	var look := MeshKit.jitter(rng)
	var bark: Array = []
	var needles: Array = []
	var count := MASSES[age][lod]
	if age == 0:
		bark.append(TreeKit.trunk(a, rng, lod, h * 0.75, TreeKit.POINTS[age][lod]))
		var layers := PackedVector3Array()
		for k in count:
			var t := float(k) / (count - 1)
			var base := lerpf(BARE[age] * h, h * 0.6, t)
			layers.append(Vector3(base, CROWN[age] * h * lerpf(1.0, 0.3, t), (h - base) * 0.5))
		needles = TreeKit.cone_layers(a, rng, layers, CONE_SIDES[lod])
	else:
		var total := MASSES[age].x
		var centers := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in total:
			var t := (i + 0.5) / total
			var y := lerpf(BARE[age] * h, h * 0.94, t) + rng.randf_range(-0.03, 0.03) * h
			var r := CROWN[age] * h * lerpf(1.0, 0.45, t) * rng.randf_range(0.85, 1.15)
			var angle := rng.randf_range(0.0, TAU)
			var off := r * rng.randf_range(0.2, 0.6) * (1.0 - t * 0.6)
			if i == total - 1:
				off = 0.0
			centers.append(a.pos(y) + Vector3(cos(angle) * off, r * 0.1, sin(angle) * off))
			radii.append(r)
		bark.append(TreeKit.trunk(a, rng, lod, h * 0.97, TreeKit.POINTS[age][lod]))
		bark.append_array(TreeKit.ridges(a, rng, TreeKit.RIDGES[age][lod]))
		for i in TreeKit.pick(total, count):
			var c := centers[i]
			var r := radii[i]
			needles.append(TreeKit.clump(rng, c, r, PAD_DETAIL[lod], 0.5))
			if i < total - 1 and lod < 2:
				var from := a.pos(maxf(c.y - r * 0.7, 0.5))
				var to := c - Vector3(0.0, r * 0.25, 0.0)
				bark.append(TreeKit.limb(from, to, a.radius(c.y) * 0.7, 0.0, lod, rng))
	return (
		MeshKit
		. merge(
			[
				TreeKit.painted(bark, &"bark", palette, rng, look),
				TreeKit.painted(needles, &"needle", palette, rng, look),
			]
		)
	)
